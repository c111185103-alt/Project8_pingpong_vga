## Project8 top-level pin constraints (pong_top)
## clk / rst / VGA (5 signals) reuse the exact same wiring as Project7
## (vga_photo_top): VGA goes through the same Raspberry Pi GPIO adapter
## board (JA2 header), rst reuses GRST (BTNC / S6).
##
## Paddle buttons follow the EGO-XZ7 official user guide (Table 15, Push
## Button pinout) plus the up/down mapping confirmed by the user:
##   Player A (left):  S7 = up (BTNL), S9 = down (BTND)
##   Player B (right): S5 = up (BTNU), S8 = down (BTNR)
##
## IOSTANDARD: the official user guide groups S2~S9 all under the same
## Bank34 (Vadj). rst (=S6, same bank) is already confirmed as LVCMOS25
## in Project7's XDC, so these four buttons use LVCMOS25 by the same
## "same bank, same voltage" inference -- this was NOT individually
## re-verified against to_hardware.xdc's exact wording for these four
## specific pins. Please double check before programming; if JP1 has
## been changed to 3.3V, change all four to LVCMOS33 together.
##
## ===== System clock =====
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## ===== Reset button: reuse GRST (BTNC, S6) =====
set_property PACKAGE_PIN P16 [get_ports rst]
set_property IOSTANDARD LVCMOS25 [get_ports rst]

## ===== Paddle buttons =====
## Player A (left): S7 = up (BTNL, N15)
set_property PACKAGE_PIN N15 [get_ports btn_a_up_raw]
set_property IOSTANDARD LVCMOS25 [get_ports btn_a_up_raw]
## Player A (left): S9 = down (BTND, R16)
set_property PACKAGE_PIN R16 [get_ports btn_a_down_raw]
set_property IOSTANDARD LVCMOS25 [get_ports btn_a_down_raw]
## Player B (right): S5 = up (BTNU, T18)
set_property PACKAGE_PIN T18 [get_ports btn_b_up_raw]
set_property IOSTANDARD LVCMOS25 [get_ports btn_b_up_raw]
## Player B (right): S8 = down (BTNR, R18)
set_property PACKAGE_PIN R18 [get_ports btn_b_down_raw]
set_property IOSTANDARD LVCMOS25 [get_ports btn_b_down_raw]

## ===== VGA sync signals =====
## HSYNC -> JA2 pin13 -> GPIO_27
set_property PACKAGE_PIN AB9 [get_ports hsync]
set_property IOSTANDARD LVCMOS33 [get_ports hsync]
## VSYNC -> JA2 pin11 -> GPIO_17
set_property PACKAGE_PIN AB10 [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]

## ===== VGA Red R[3:0] =====
set_property PACKAGE_PIN AA6 [get_ports {vga_r[3]}]
set_property PACKAGE_PIN Y10 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN Y11 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN AB6 [get_ports {vga_r[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

## ===== VGA Green G[3:0] =====
set_property PACKAGE_PIN Y4  [get_ports {vga_g[3]}]
set_property PACKAGE_PIN AA4 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN R6  [get_ports {vga_g[1]}]
set_property PACKAGE_PIN T6  [get_ports {vga_g[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

## ===== VGA Blue B[3:0] =====
set_property PACKAGE_PIN AA11 [get_ports {vga_b[3]}]
set_property PACKAGE_PIN U4   [get_ports {vga_b[2]}]
set_property PACKAGE_PIN AB11 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN AA7  [get_ports {vga_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

## ===== Required for programming to succeed =====
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
