# This file is a placeholder for the Vivado IP generation script (Tcl).
# To generate the IFM Buffer IP, run this Tcl script in the Vivado Tcl Console.

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name ifm_buffer

set_property -dict [list \
  CONFIG.Memory_Type {Simple_Dual_Port_RAM} \
  CONFIG.Write_Width_A {32} \
  CONFIG.Write_Depth_A {65536} \
  CONFIG.Read_Width_A {32} \
  CONFIG.Operating_Mode_A {NO_CHANGE} \
  CONFIG.Enable_32bit_Address {false} \
  CONFIG.Use_Byte_Write_Enable {false} \
  CONFIG.Byte_Size {9} \
  CONFIG.Algorithm {Minimum_Area} \
  CONFIG.Primitive {8kx2} \
  CONFIG.Assume_Synchronous_Clk {true} \
  CONFIG.Write_Width_B {256} \
  CONFIG.Read_Width_B {256} \
  CONFIG.Operating_Mode_B {READ_FIRST} \
  CONFIG.Enable_B {Use_ENB_Pin} \
  CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
  CONFIG.Register_PortB_Output_of_Memory_Primitives {true} \
  CONFIG.Use_RSTA_Pin {false} \
  CONFIG.Use_RSTB_Pin {false} \
  CONFIG.Port_B_Clock {100} \
  CONFIG.Port_B_Write_Rate {0} \
  CONFIG.Port_B_Enable_Rate {100} \
] [get_ips ifm_buffer]

generate_target {instantiation_template} [get_files ifm_buffer.xci]
generate_target all [get_files  ifm_buffer.xci]
export_ip_user_files -of_objects [get_files ifm_buffer.xci] -no_script -sync -force -quiet
