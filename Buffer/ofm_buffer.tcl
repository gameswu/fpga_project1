# This file is a placeholder for the Vivado IP generation script (Tcl).
# To generate the OFM Buffer IP, run this Tcl script in the Vivado Tcl Console.

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name ofm_buffer

set_property -dict [list \
  CONFIG.Memory_Type {True_Dual_Port_RAM} \
  CONFIG.Write_Width_A {512} \
  CONFIG.Write_Depth_A {4096} \
  CONFIG.Read_Width_A {512} \
  CONFIG.Operating_Mode_A {READ_FIRST} \
  CONFIG.Enable_32bit_Address {false} \
  CONFIG.Use_Byte_Write_Enable {true} \
  CONFIG.Byte_Size {8} \
  CONFIG.Algorithm {Minimum_Area} \
  CONFIG.Primitive {8kx2} \
  CONFIG.Assume_Synchronous_Clk {true} \
  CONFIG.Write_Width_B {512} \
  CONFIG.Read_Width_B {512} \
  CONFIG.Operating_Mode_B {READ_FIRST} \
  CONFIG.Enable_B {Use_ENB_Pin} \
  CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
  CONFIG.Register_PortB_Output_of_Memory_Primitives {true} \
  CONFIG.Use_RSTA_Pin {false} \
  CONFIG.Use_RSTB_Pin {false} \
  CONFIG.Port_B_Clock {100} \
  CONFIG.Port_B_Write_Rate {50} \
  CONFIG.Port_B_Enable_Rate {100} \
] [get_ips ofm_buffer]

generate_target {instantiation_template} [get_files ofm_buffer.xci]
generate_target all [get_files  ofm_buffer.xci]
export_ip_user_files -of_objects [get_files ofm_buffer.xci] -no_script -sync -force -quiet
