/**
 * @file	tb_wb_esp.sv
 * @brief	Self-checking testbench for the wb_esp UART peripheral
 *
 * Drives wb_esp directly over Wishbone (one-cycle STB, CYC held until ACK, as
 * axilite2wbsp does) and models the ESP32 side of the link: a UART sender that
 * honors RTS like the ESP32 hardware flow control, and a UART receiver that
 * decodes everything on ESP_TXD.
 *
 * Small FIFOs (64 RX / 32 TX) keep the flow-control and overflow tests short.
 */
`timescale 1ns/1ps
`default_nettype wire

module tb_wb_esp;

    localparam int  DIV    = 50;			// 2 Mbaud at 100 MHz
    localparam time BIT    = DIV * 10;		// ns
    localparam int  RX_LG  = 6;				// 64-byte RX FIFO
    localparam int  TX_LG  = 5;				// 32-byte TX FIFO
    localparam int  MARGIN = 8;

    localparam logic [7:0] R_CTRL=8'h00, R_STATUS=8'h04, R_BAUDDIV=8'h08, R_LEVEL=8'h0C,
                           R_RXTHRESH=8'h10, R_RXTIMEOUT=8'h14, R_TXTHRESH=8'h18,
                           R_TXDATA=8'h20, R_TXDATA32=8'h24, R_RXDATA=8'h28,
                           R_RXDATA32=8'h2C, R_ID=8'h30, R_FIFOSZ=8'h34;

    // CTRL bits
    localparam logic [31:0] C_RXIRQ=32'h01, C_TXIRQ=32'h02, C_FLOW=32'h04, C_LOOP=32'h08,
                            C_RXFLUSH=32'h10, C_TXFLUSH=32'h20;
    // STATUS bits
    localparam int S_RXAVAIL=0, S_RXFULL=1, S_TXEMPTY=2, S_TXFULL=3, S_TXIDLE=4,
                   S_RXBUSY=5, S_TIMEOUT=6, S_IRQ=7, S_OVR=16, S_FRM=17, S_UND=18,
                   S_CTS=24, S_RTS=25;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;		// 100 MHz

    logic cyc=0, stb=0, we=0;
    logic [31:0] addr=0, wdata=0, rdata;
    logic ack;

    logic txd, rxd = 1, rts_n, cts_n = 0, irq;

    wb_esp #(
        .RX_LG(RX_LG), .TX_LG(TX_LG), .RTS_MARGIN(MARGIN)
    ) dut (
        .i_clk(clk), .i_reset(rst),
        .i_wb_cyc(cyc), .i_wb_stb(stb), .i_wb_we(we), .i_wb_addr(addr),
        .i_wb_data(wdata), .i_wb_sel(4'hF), .o_wb_data(rdata), .o_wb_ack(ack),
        .ESP_TXD(txd), .ESP_RXD(rxd), .ESP_RTS_N(rts_n), .ESP_CTS_N(cts_n),
        .o_irq(irq)
    );

    int errors = 0;
    `define CHECK(cond, msg) if (!(cond)) begin $error msg; errors++; end

    // ---------------- Wishbone master ----------------
    int max_ack_wait = 0;
    task automatic wb_xfer(input logic w, input logic [7:0] off, input logic [31:0] d,
                           output logic [31:0] q);
        int n = 0;
        @(posedge clk);
        cyc <= 1; stb <= 1; we <= w; addr <= {24'h0, off}; wdata <= d;
        @(posedge clk);
        stb <= 0;
        while (!ack) begin @(posedge clk); n++; end
        q = rdata;
        cyc <= 0; we <= 0;
        if (n > max_ack_wait) max_ack_wait = n;
    endtask
    task automatic wr(input logic [7:0] off, input logic [31:0] d);
        logic [31:0] q; wb_xfer(1, off, d, q);
    endtask
    task automatic rd(input logic [7:0] off, output logic [31:0] q);
        wb_xfer(0, off, 0, q);
    endtask
    task automatic wait_tx_idle();
        logic [31:0] st;
        do rd(R_STATUS, st); while (!st[S_TXIDLE]);
        #(BIT);							// let the monitor finish the stop bit
    endtask

    // ---------------- ESP32 model: receiver on ESP_TXD ----------------
    logic [7:0] got [$];
    initial begin
        logic [7:0] b;
        forever begin
            @(negedge txd);
            #(BIT/2);
            if (txd !== 1'b0) begin
                $error("TX start bit glitch"); errors++;
                continue;
            end
            for (int i = 0; i < 8; i++) begin #(BIT); b[i] = txd; end
            #(BIT);
            if (txd !== 1'b1) begin $error("TX stop bit low"); errors++; end
            got.push_back(b);
        end
    end

    // ---------------- ESP32 model: sender on ESP_RXD ----------------
    bit respect_rts = 0;
    task automatic ext_send(input logic [7:0] b, input logic good_stop = 1'b1);
        if (respect_rts) while (rts_n !== 1'b0) #(BIT/4);	// ESP32 checks CTS per byte
        rxd = 1'b0; #(BIT);
        for (int i = 0; i < 8; i++) begin rxd = b[i]; #(BIT); end
        rxd = good_stop; #(BIT);
        if (!good_stop) begin rxd = 1'b1; #(2*BIT); end
    endtask
    task automatic ext_send_str(input string s);
        foreach (s[i]) ext_send(s[i]);
    endtask

    task automatic expect_got(input logic [7:0] exp [$], input string what);
        if (got.size() != exp.size()) begin
            $error("%s: got %0d bytes, expected %0d", what, got.size(), exp.size()); errors++;
        end
        for (int i = 0; i < exp.size() && i < got.size(); i++)
            if (got[i] !== exp[i]) begin
                $error("%s: byte %0d = %02h, expected %02h", what, i, got[i], exp[i]); errors++;
            end
        got.delete();
    endtask

    logic [31:0] q, st;
    logic [7:0]  exp [$];
    time t0;
    int  n_read;

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // ================= 1. reset values =================
        rd(R_ID, q);        `CHECK(q === 32'h4553_3332, ("ID %h", q))
        rd(R_FIFOSZ, q);    `CHECK(q === {16'd32, 16'd64}, ("FIFOSZ %h", q))
        rd(R_BAUDDIV, q);   `CHECK(q === 868, ("BAUDDIV reset %0d", q))
        rd(R_CTRL, q);      `CHECK(q === 0, ("CTRL reset %h", q))
        rd(R_RXTHRESH, q);  `CHECK(q === 1, ("RXTHRESH reset %0d", q))
        rd(R_RXTIMEOUT, q); `CHECK(q === 40, ("RXTIMEOUT reset %0d", q))
        rd(R_STATUS, q);
        `CHECK(q[S_RXAVAIL] === 0 && q[S_TXEMPTY] === 1 && q[S_TXIDLE] === 1 && q[S_RTS] === 1,
               ("STATUS reset %h", q))
        rd(R_RXDATA, q);    `CHECK(q === 32'h8000_0000, ("RXDATA empty %h", q))
        `CHECK(txd === 1 && rts_n === 0 && irq === 0, ("pin reset state"))
        $display("[%0t] 1. reset values done", $time);

        // ================= 2. baud divider clamp =================
        wr(R_BAUDDIV, 3);   rd(R_BAUDDIV, q); `CHECK(q === 8, ("BAUDDIV clamp %0d", q))
        wr(R_BAUDDIV, DIV); rd(R_BAUDDIV, q); `CHECK(q === DIV, ("BAUDDIV %0d", q))

        // ================= 3. transmit to ESP32 + bit timing =================
        fork
            begin
                @(negedge txd); t0 = $time;		// start bit of 0x55
                @(posedge txd);					// bit 0 = 1
                `CHECK($time - t0 == BIT, ("bit time %0t, expected %0t", $time - t0, BIT))
            end
        join_none
        wr(R_TXDATA, 8'h55);
        wr(R_TXDATA, "H"); wr(R_TXDATA, "i"); wr(R_TXDATA, "!");
        wr(R_TXDATA32, 32'h4443_4241);			// "ABCD", A first
        wait_tx_idle();
        exp = '{8'h55, "H", "i", "!", "A", "B", "C", "D"};
        expect_got(exp, "TX");
        $display("[%0t] 3. transmit done", $time);

        // ================= 4. receive from ESP32 =================
        ext_send_str("hello");
        rd(R_LEVEL, q);     `CHECK(q[15:0] === 5, ("RX level %0d", q[15:0]))
        begin
            automatic string s = "hello";
            foreach (s[i]) begin
                rd(R_RXDATA, q);
                `CHECK(q === {24'h0, s[i]}, ("RXDATA %0d = %h", i, q))
            end
        end
        rd(R_RXDATA, q);    `CHECK(q === 32'h8000_0000, ("RXDATA after drain %h", q))
        $display("[%0t] 4. receive done", $time);

        // ================= 5. 32-bit reads and underrun =================
        for (int i = 1; i <= 5; i++) ext_send(8'(i));
        rd(R_RXDATA32, q);  `CHECK(q === 32'h0403_0201, ("RXDATA32 %h", q))
        rd(R_RXDATA32, q);  `CHECK(q === 0, ("RXDATA32 underrun value %h", q))
        rd(R_STATUS, q);    `CHECK(q[S_UND] === 1, ("UNDERRUN not set"))
        rd(R_RXDATA, q);    `CHECK(q === 32'h05, ("byte after underrun %h", q))
        wr(R_STATUS, 32'h1 << S_UND);
        rd(R_STATUS, q);    `CHECK(q[S_UND] === 0, ("UNDERRUN not cleared"))
        $display("[%0t] 5. RXDATA32 done", $time);

        // ================= 6. RX interrupt: timeout and threshold =================
        wr(R_RXTHRESH, 4);
        wr(R_RXTIMEOUT, 20);
        wr(R_CTRL, C_RXIRQ);
        `CHECK(irq === 0, ("IRQ with empty FIFO"))
        ext_send(8'hA1); ext_send(8'hA2);
        `CHECK(irq === 0, ("IRQ right after 2 bytes (below threshold)"))
        #(15*BIT);
        `CHECK(irq === 0, ("IRQ before timeout"))
        #(10*BIT);
        `CHECK(irq === 1, ("timeout IRQ missing"))
        rd(R_STATUS, q);    `CHECK(q[S_TIMEOUT] === 1 && q[S_IRQ] === 1, ("STATUS timeout %h", q))
        rd(R_RXDATA, q);    `CHECK(q === 32'hA1, ("timeout byte 0 %h", q))
        `CHECK(irq === 0, ("timeout IRQ not restarted by read"))
        rd(R_RXDATA, q);    `CHECK(q === 32'hA2, ("timeout byte 1 %h", q))

        wr(R_RXTIMEOUT, 0);
        for (int i = 0; i < 3; i++) ext_send(8'(8'hB0 + i));
        #(30*BIT);
        `CHECK(irq === 0, ("IRQ at 3 bytes with threshold 4 and timeout off"))
        ext_send(8'hB3);
        repeat (3) @(posedge clk);
        `CHECK(irq === 1, ("threshold IRQ missing"))
        rd(R_RXDATA, q);
        `CHECK(irq === 0, ("threshold IRQ still set below threshold"))
        wr(R_CTRL, C_RXIRQ | C_RXFLUSH);
        rd(R_LEVEL, q);     `CHECK(q[15:0] === 0, ("RX flush, level %0d", q[15:0]))
        wr(R_CTRL, 0);
        wr(R_RXTHRESH, 1);
        wr(R_RXTIMEOUT, 40);
        $display("[%0t] 6. RX interrupt done", $time);

        // ================= 7. TX interrupt =================
        wr(R_TXTHRESH, 0);
        wr(R_CTRL, C_TXIRQ);
        `CHECK(irq === 1, ("TX IRQ with empty FIFO"))
        wr(R_TXDATA32, 32'h0403_0201);
        `CHECK(irq === 0, ("TX IRQ with data queued"))
        wait_tx_idle();
        `CHECK(irq === 1, ("TX IRQ after drain"))
        wr(R_CTRL, 0);
        got.delete();
        $display("[%0t] 7. TX interrupt done", $time);

        // ================= 8. internal loopback =================
        wr(R_CTRL, C_LOOP);
        wr(R_TXDATA32, 32'h5A59_5857);			// "WXYZ"
        wait_tx_idle();
        #(2*BIT);
        `CHECK(got.size() == 0, ("loopback leaked %0d bytes onto ESP_TXD", got.size()))
        rd(R_RXDATA32, q);  `CHECK(q === 32'h5A59_5857, ("loopback data %h", q))
        wr(R_CTRL, 0);
        $display("[%0t] 8. loopback done", $time);

        // ================= 9. RX flow control (RTS) =================
        wr(R_CTRL, C_FLOW);
        respect_rts = 1;
        n_read = 0;
        fork
            for (int i = 0; i < 150; i++) ext_send(8'(i));
            begin
                // let the FIFO fill up and RTS drop before draining
                wait (rts_n === 1'b1);
                rd(R_LEVEL, q);
                `CHECK(q[15:0] >= 64 - MARGIN, ("RTS dropped early at level %0d", q[15:0]))
                #(40*BIT);
                rd(R_LEVEL, q);
                `CHECK(q[15:0] <= 64 - MARGIN + 1,
                       ("sender ignored RTS: level %0d", q[15:0]))
                while (n_read < 150) begin
                    rd(R_STATUS, st);
                    if (st[S_RXAVAIL]) begin
                        rd(R_RXDATA, q);
                        `CHECK(q === 32'(n_read[7:0]), ("flow byte %0d = %h", n_read, q))
                        n_read++;
                    end
                end
            end
        join
        rd(R_STATUS, q);    `CHECK(q[S_OVR] === 0, ("overrun with flow control"))
        `CHECK(rts_n === 0, ("RTS not reasserted after drain"))
        respect_rts = 0;
        $display("[%0t] 9. RX flow control done", $time);

        // ================= 10. TX flow control (CTS) =================
        cts_n = 1;
        wr(R_TXDATA, 8'hC0); wr(R_TXDATA, 8'hC1); wr(R_TXDATA, 8'hC2);
        #(30*BIT);
        `CHECK(got.size() == 0, ("sent %0d bytes while CTS high", got.size()))
        rd(R_STATUS, q);    `CHECK(q[S_CTS] === 0, ("STATUS.CTS with CTS_N high"))
        rd(R_LEVEL, q);     `CHECK(q[31:16] === 3, ("TX level %0d while blocked", q[31:16]))
        cts_n = 0;
        wait_tx_idle();
        exp = '{8'hC0, 8'hC1, 8'hC2};
        expect_got(exp, "CTS");
        wr(R_CTRL, 0);
        $display("[%0t] 10. TX flow control done", $time);

        // ================= 11. TX FIFO full: ACK stalls, nothing lost =================
        exp.delete();
        max_ack_wait = 0;
        for (int i = 0; i < 50; i++) begin
            wr(R_TXDATA, 8'(8'h80 + i));
            exp.push_back(8'(8'h80 + i));
        end
        `CHECK(max_ack_wait > 10, ("ACK never stalled on a full TX FIFO"))
        wait_tx_idle();
        expect_got(exp, "TX backpressure");
        $display("[%0t] 11. TX backpressure done (max ack wait %0d cycles)", $time, max_ack_wait);

        // ================= 12. RX overrun without flow control =================
        for (int i = 0; i < 70; i++) ext_send(8'(i));
        rd(R_STATUS, q);
        `CHECK(q[S_OVR] === 1 && q[S_RXFULL] === 1, ("overrun STATUS %h", q))
        rd(R_LEVEL, q);     `CHECK(q[15:0] === 64, ("RX level after overrun %0d", q[15:0]))
        rd(R_RXDATA, q);    `CHECK(q === 0, ("first byte after overrun %h", q))
        wr(R_CTRL, C_RXFLUSH);
        wr(R_STATUS, 32'h1 << S_OVR);
        rd(R_STATUS, q);    `CHECK(q[S_OVR] === 0 && q[S_RXAVAIL] === 0, ("overrun clear %h", q))
        $display("[%0t] 12. overrun done", $time);

        // ================= 13. framing error =================
        ext_send(8'h00, 1'b0);					// bad stop bit
        ext_send(8'h42);
        rd(R_STATUS, q);    `CHECK(q[S_FRM] === 1, ("FRAME_ERR not set"))
        rd(R_LEVEL, q);     `CHECK(q[15:0] === 1, ("level after framing error %0d", q[15:0]))
        rd(R_RXDATA, q);    `CHECK(q === 32'h42, ("byte after framing error %h", q))
        wr(R_STATUS, 32'h1 << S_FRM);
        rd(R_STATUS, q);    `CHECK(q[S_FRM] === 0, ("FRAME_ERR not cleared"))
        $display("[%0t] 13. framing error done", $time);

        // ================= 14. TX flush =================
        wr(R_CTRL, C_FLOW);
        cts_n = 1;
        for (int i = 0; i < 10; i++) wr(R_TXDATA, 8'hEE);
        wr(R_CTRL, C_FLOW | C_TXFLUSH);
        rd(R_LEVEL, q);     `CHECK(q[31:16] === 0, ("TX level after flush %0d", q[31:16]))
        cts_n = 0;
        #(30*BIT);
        `CHECK(got.size() == 0, ("%0d bytes sent after TX flush", got.size()))
        wr(R_CTRL, 0);
        $display("[%0t] 14. TX flush done", $time);

        if (errors == 0) $display("*** TEST PASSED ***");
        else             $display("*** TEST FAILED: %0d errors ***", errors);
        $finish;
    end

    initial begin
        #50ms; $fatal(1, "timeout");
    end

endmodule
