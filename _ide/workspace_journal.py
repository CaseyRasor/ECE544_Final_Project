# 2026-11-17T09:09:25.915515500
import vitis

client = vitis.create_client()
client.set_workspace(path="final_project")

platform = client.create_platform_component(name = "lcd_platform",hw_design = "$COMPONENT_LOCATION/../mbc_wb_nexys4DDR.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

comp = client.create_app_component(name="lcd_test_standalone",platform = "$COMPONENT_LOCATION/../lcd_platform/export/lcd_platform/lcd_platform.xpfm",domain = "standalone_microblaze_0")

comp = client.get_component(name="lcd_test_standalone")
status = comp.import_files(from_loc="", files=["C:\Users\casey\Vivado\final_project\sw\apps\test_mbwb_lcd.c", "C:\Users\casey\Vivado\final_project\sw\mbc_wb_drivers\source\MBWB_BIO.c", "C:\Users\casey\Vivado\final_project\sw\mbc_wb_drivers\source\MBWB_LCD.c", "C:\Users\casey\Vivado\final_project\sw\mbc_wb_drivers\source\MBWB_LCD_font.c", "C:\Users\casey\Vivado\final_project\sw\mbc_wb_drivers\source\MBWB_SSEG.c"], is_skip_copy_sources = True)

platform = client.get_component(name="lcd_platform")
status = platform.build()

comp.set_app_config(key = "USER_INCLUDE_DIRECTORIES", values = ["C:/Users/casey/Vivado/final_project/sw/mbc_wb_drivers/include"])

status = platform.build()

comp = client.get_component(name="lcd_test_standalone")
comp.build()

status = platform.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../mbc_wb_nexys4DDR.xsa")

status = platform.build()

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../mbc_wb_nexys4DDR.xsa")

status = platform.build()

status = platform.build()

comp = client.create_app_component(name="esp_test_standalone",platform = "$COMPONENT_LOCATION/../lcd_platform/export/lcd_platform/lcd_platform.xpfm",domain = "standalone_microblaze_0")

comp = client.get_component(name="esp_test_standalone")
status = comp.import_files(from_loc="", files=["C:\Users\casey\Vivado\final_project\sw\mbc_wb_drivers\source", "C:\Users\casey\Vivado\final_project\sw\apps\test_mbwb_esp.c"], is_skip_copy_sources = True)

comp.set_app_config(key = "USER_INCLUDE_DIRECTORIES", values = ["C:/Users/casey/Vivado/final_project/sw/mbc_wb_drivers/include"])

status = platform.build()

comp = client.get_component(name="esp_test_standalone")
comp.build()

