## =============================================================================
## top.xdc - Basys 3 - Trabajo Final, paso 1 (eco por UART)
## Pines tomados del master XDC de la Basys 3 (los mismos que en uart_alu.xdc).
## =============================================================================

## Clock 100 MHz
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports i_clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports i_clk]

## Boton central (btnC) -> reset
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports i_reset]

## Puente USB-UART
set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports i_rx]
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports o_tx]

## LEDs LD0..LD7 -> ultimo byte recibido
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {o_leds[0]}]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {o_leds[1]}]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {o_leds[2]}]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {o_leds[3]}]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports {o_leds[4]}]
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports {o_leds[5]}]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {o_leds[6]}]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {o_leds[7]}]

## Configuracion
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
