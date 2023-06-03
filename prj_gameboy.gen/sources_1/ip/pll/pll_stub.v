// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
// Date        : Sat Jun  3 17:09:05 2023
// Host        : LAPTOP-FI57V2Q6 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/prj_xilinx/prj_gameboy/prj_gameboy.gen/sources_1/ip/pll/pll_stub.v
// Design      : pll
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7s25csga225-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module pll(clk_in2, clk_in_sel, clk_out1, clk_out2, 
  clk_out3, clk_out4, reset, locked, clk_in1)
/* synthesis syn_black_box black_box_pad_pin="clk_in2,clk_in_sel,clk_out1,clk_out2,clk_out3,clk_out4,reset,locked,clk_in1" */;
  input clk_in2;
  input clk_in_sel;
  output clk_out1;
  output clk_out2;
  output clk_out3;
  output clk_out4;
  input reset;
  output locked;
  input clk_in1;
endmodule
