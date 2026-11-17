/**
 * @file	tb_wb_lcd.sv
 * @brief	Self-checking testbench for wb_lcd through wb_subsystem
 *
 * Drives the Wishbone bus the way axilite2wbsp does (one-cycle STB, CYC held
 * until ACK) and decodes the SPI stream (mode 0) with a simple monitor.
 */
`timescale 1ns/1ps
`default_nettype wire

module tb_wb_lcd;

    localparam logic [31:0] LCD_BASE = 32'h0003_0000;	// wb_mux region 2'b11
    localparam logic [7:0] R_CTRL=8'h00, R_STATUS=8'h04, R_CLKDIV=8'h08, R_FILLCNT=8'h0C,
                           R_CMD=8'h10, R_DATA8=8'h14, R_DATA16=8'h18, R_FILL=8'h1C,
                           R_ID=8'h20, R_FIFOSZ=8'h24;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;		// 100 MHz

    logic cyc=0, stb=0, we=0;
    logic [31:0] addr=0, wdata=0, rdata;
    logic ack;
    logic [3:0] sel = 4'hF;

    logic sclk, mosi, cs_n, dc, rst_n, bl;
    logic irq0, irq1, irq2;
    logic esp_txd, esp_rts_n;

    wb_subsystem dut (
        .i_clk(clk), .i_reset(rst),
        .i_wb_cyc(cyc), .i_wb_stb(stb), .i_wb_we(we), .i_wb_addr(addr),
        .i_wb_data(wdata), .i_wb_sel(sel), .o_wb_ack(ack), .o_wb_data(rdata),
        .o_irq0(irq0), .o_irq1(irq1), .o_irq2(irq2),
        .btns('0), .sw('0), .leds(), .rgb1RGB(), .rgb2RGB(),
        .AN(), .DP(), .Digits_Bits(),
        .LCD_SCLK(sclk), .LCD_MOSI(mosi), .LCD_CS_N(cs_n), .LCD_DC(dc),
        .LCD_RST_N(rst_n), .LCD_BL(bl),
        .ESP_TXD(esp_txd), .ESP_RXD(1'b1), .ESP_RTS_N(esp_rts_n), .ESP_CTS_N(1'b1),
        .wb_debug()
    );

    // ---------------- Wishbone master tasks ----------------
    int max_ack_wait = 0;
    task automatic wb_xfer(input logic w, input logic [7:0] off, input logic [31:0] d,
                           output logic [31:0] q);
        wb_xfer_abs(w, LCD_BASE + off, d, q);
    endtask
    task automatic wb_xfer_abs(input logic w, input logic [31:0] a, input logic [31:0] d,
                               output logic [31:0] q);
        int n = 0;
        @(posedge clk);
        cyc <= 1; stb <= 1; we <= w; addr <= a; wdata <= d;
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

    // ---------------- SPI monitor ----------------
    // captured bytes: {dc, byte}
    logic [8:0] got [$];
    logic [7:0] sh; int nb = 0;
    always @(posedge sclk) begin
        if (cs_n) $error("SCLK rising edge with CS# high");
        sh = {sh[6:0], mosi};
        nb++;
        if (nb == 8) begin
            got.push_back({dc, sh});
            nb = 0;
        end
    end
    // DC must not change while SCLK is high
    always @(dc) if (sclk && !cs_n) $error("DC changed while SCLK high");

    int errors = 0;
    task automatic expect_bytes(input logic [8:0] exp [$]);
        if (got.size() != exp.size()) begin
            $error("byte count: got %0d expected %0d", got.size(), exp.size()); errors++;
        end
        for (int i = 0; i < exp.size() && i < got.size(); i++)
            if (got[i] !== exp[i]) begin
                $error("byte %0d: got dc=%b %02h expected dc=%b %02h",
                       i, got[i][8], got[i][7:0], exp[i][8], exp[i][7:0]); errors++;
            end
        got.delete();
    endtask

    task automatic wait_idle();
        logic [31:0] st;
        do rd(R_STATUS, st); while (st[0]);
    endtask

    logic [31:0] q;
    logic [8:0] exp [$];
    time t0;

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // ---- ID / reset values ----
        rd(R_ID, q);      if (q !== 32'h37373936) begin $error("ID %h", q); errors++; end
        rd(R_FIFOSZ, q);  if (q !== 512) begin $error("FIFOSZ %0d", q); errors++; end
        rd(R_CTRL, q);    if (q !== 32'h1) begin $error("CTRL reset %h", q); errors++; end
        if (rst_n !== 0 || bl !== 0) begin $error("panel reset/BL reset state"); errors++; end
        rd(R_CLKDIV, q);  if (q !== 3) begin $error("CLKDIV reset %0d", q); errors++; end
        rd(R_STATUS, q);  if (q[2:0] !== 3'b100) begin $error("STATUS reset %h", q); errors++; end

        wr(R_CTRL, 32'b0110);			// release reset, BL on, IRQ en
        rd(R_CTRL, q);
        if (rst_n !== 1 || bl !== 1 || q !== 32'b0110) begin $error("CTRL write"); errors++; end
        if (irq1 !== 1) begin $error("idle IRQ not asserted"); errors++; end

        // ---- basic command/data/pixel/fill stream @ 25 MHz ----
        wr(R_CLKDIV, 1);
        wr(R_CMD,    32'hFFFF_FF2C);
        wr(R_DATA8,  32'h0000_0111);
        wr(R_DATA16, 32'h0000_ABCD);
        wr(R_FILLCNT, 3);
        wr(R_FILL,   32'h0000_1234);
        wr(R_FILLCNT, 0);
        wr(R_FILL,   32'h0000_5555);		// zero count -> nothing sent
        wr(R_CMD,    32'h29);
        @(posedge clk); #1;
        if (irq1 !== 0) begin $error("IRQ asserted while busy"); errors++; end
        wait_idle();
        exp = '{9'h02C, 9'h111, 9'h1AB, 9'h1CD,
                9'h112, 9'h134, 9'h112, 9'h134, 9'h112, 9'h134, 9'h029};
        expect_bytes(exp);
        if (cs_n !== 1) begin $error("CS# not released when idle"); errors++; end
        $display("[%0t] basic stream test done", $time);

        // ---- SCLK frequency check: clkdiv=1 -> 40 ns period ----
        wr(R_FILLCNT, 1);
        wr(R_DATA8, 8'hA5);
        @(posedge sclk); t0 = $time; @(posedge sclk);
        if ($time - t0 != 40) begin $error("SCLK period %0t", $time - t0); errors++; end
        wait_idle(); got.delete();

        // ---- FIFO overflow: ACK must be held, nothing lost ----
        wr(R_CLKDIV, 20);
        exp.delete();
        max_ack_wait = 0;
        for (int i = 0; i < 700; i++) begin
            wr(R_DATA8, i[7:0]);
            exp.push_back({1'b1, 8'(i)});
        end
        if (max_ack_wait < 10) begin $error("ACK never stalled on full FIFO"); errors++; end
        wait_idle();
        expect_bytes(exp);
        $display("[%0t] overflow test done (max ack wait %0d cycles)", $time, max_ack_wait);

        // ---- large hardware fill (full screen 320x480) at 50 MHz ----
        wr(R_CLKDIV, 0);
        wr(R_FILLCNT, 320*480);
        wr(R_FILL, 16'hF800);
        wait_idle();
        if (got.size() != 2*320*480) begin $error("fill bytes %0d", got.size()); errors++; end
        foreach (got[i]) if (got[i] !== ((i%2) ? 9'h100 : 9'h1F8)) begin
            $error("fill byte %0d = %h", i, got[i]); errors++; break; end
        got.delete();
        $display("[%0t] full-screen fill done", $time);

        // ---- flush aborts a transfer ----
        wr(R_CLKDIV, 3);
        wr(R_FILLCNT, 1000);
        wr(R_FILL, 16'h07E0);
        for (int i = 0; i < 20; i++) wr(R_CMD, 8'h00);
        repeat (300) @(posedge clk);
        wr(R_CTRL, 32'b1110);			// flush (keep BL/IRQ_EN)
        rd(R_STATUS, q);
        if (q[0] !== 0 || q[2] !== 1 || q[25:16] !== 0) begin $error("STATUS after flush %h", q); errors++; end
        if (cs_n !== 1) begin $error("CS# low after flush"); errors++; end
        nb = 0; got.delete();
        // engine still works afterwards
        wr(R_CMD, 8'h11);
        wait_idle();
        exp = '{9'h011};
        expect_bytes(exp);
        $display("[%0t] flush test done", $time);

        // ---- ESP32 UART in region 4, and unused regions 5-7 ----
        wb_xfer_abs(0, 32'h0004_0030, 0, q);		// ESP_ID
        if (q !== 32'h4553_3332) begin $error("ESP ID %h", q); errors++; end
        wb_xfer_abs(1, 32'h0004_0008, 50, q);		// BAUDDIV = 2 Mbaud
        wb_xfer_abs(1, 32'h0004_0000, 32'h9, q);	// LOOPBACK | RX_IRQ_EN
        if (irq2 !== 0) begin $error("ESP IRQ before data"); errors++; end
        wb_xfer_abs(1, 32'h0004_0020, 32'h5A, q);	// TXDATA
        do wb_xfer_abs(0, 32'h0004_000C, 0, q); while (q[15:0] == 0);	// wait for RX level
        if (irq2 !== 1) begin $error("ESP IRQ not on o_irq2"); errors++; end
        wb_xfer_abs(0, 32'h0004_0028, 0, q);		// RXDATA
        if (q !== 32'h5A) begin $error("ESP loopback byte %h", q); errors++; end
        if (esp_txd !== 1) begin $error("ESP_TXD not idle in loopback"); errors++; end
        for (int r = 5; r < 8; r++) begin			// free regions must still ACK
            wb_xfer_abs(0, 32'(r) << 16, 0, q);
            if (q !== 32'hDEAD_BEEF) begin $error("region %0d read %h", r, q); errors++; end
            wb_xfer_abs(1, 32'(r) << 16, 32'hDEAD_BEEF, q);
        end
        wb_xfer_abs(0, LCD_BASE + R_ID, 0, q);		// LCD still decodes in region 3
        if (q !== 32'h37373936) begin $error("LCD ID after region test %h", q); errors++; end
        $display("[%0t] ESP region 4 / free regions test done", $time);

        if (errors == 0) $display("*** TEST PASSED ***");
        else             $display("*** TEST FAILED: %0d errors ***", errors);
        $finish;
    end

    initial begin
        #200ms; $fatal(1, "timeout");
    end

endmodule
