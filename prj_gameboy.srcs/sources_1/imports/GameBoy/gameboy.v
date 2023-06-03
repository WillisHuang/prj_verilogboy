`timescale 1ns / 1ps
`include "cpu.vh"
`default_nettype wire
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Wenting Zhang
// 
// Create Date:    17:30:26 02/08/2018 
// Module Name:    gameboy 
// Project Name:   VerilogBoy
// Description: 
//   Gameboy main file
// Dependencies: 
// 
// Additional Comments: 
//   Hardware specific code should be implemented outside of this file
//////////////////////////////////////////////////////////////////////////////////

module gameboy(
    input rst, // Async Reset Input
    input clk, // 4.19MHz Clock Input
    input clk_mem, // High Speed Memory Clock Input
    input clk_audio, // 12.288MHz Audio Clock Input 
    // Cartridge interface
    output [15:0] a, // Address Bus
    output [7:0] dout,  // Data Bus
    input  [7:0] din,
    output wr, // Write Enable
    output rd, // Read Enable
    output cs, // External RAM Chip Select
    // Keyboard input
    input [7:0] key,
    // LCD output
    output hs, // Horizontal Sync Output
    output vs, // Vertical Sync Output
    output cpl, // Pixel Data Latch
    output [1:0] pixel, // Pixel Data
    output valid,
    // Sound output
    output [19:0] left,
    output [19:0] right,
    // Debug
    output halt, // not quite implemented?
    output debug_halt, // Debug mode status output
    output [7:0] A_data, // Accumulator debug output
    output [7:0] F_data, // Flags debug output
    output [4:0] IE_data,
    output [4:0] IF_data,
    output [7:0]  high_mem_data, // Debug high mem data output
    output [15:0] high_mem_addr, // Debug high mem addr output
    output [7:0] instruction, // Debug current instruction output
    output [79:0] regs_data, // Debug all reg data output
    input [15:0] bp_addr, // Debug breakpoint PC
    input bp_step, // Debug single step
    input bp_continue, // Debug continue
    output [7:0] dma_chipscope,
    output [7:0] scx,
    output [7:0] scy,
    output [3:0] ch1_level,
    output [3:0] ch2_level,
    output [3:0] ch3_level,
    output [3:0] ch4_level,
    output [7:0] joystick
    );
    
    wire clk_1m; // CPU Internal 1MHz machine cycle clock
    
    // Bus & Memory Signals
    wire [15:0] addr_ext; // Main Address Bus
    wire [7:0]  data_ext; // Main Data Bus
    wire [7:0]  do_video; // PPU & VRAM & OAM Data Output
    wire [7:0]  do_audio; // Audio Data Output
    wire [7:0]  do_timer; // Timer Data Output

    wire mem_we; //Bus Master Memory Write Enable
    wire mem_re; //Bus Master Memory Read Enable
    wire cpu_mem_we; // CPU Memory Write Enable
    wire cpu_mem_re; // CPU Memory Read Enable
    wire dma_mem_re; // DMA Memory Write Enable
    wire dma_mem_we; // DMA Memory Read Enable
    wire cpu_mem_disable; //Disable CPU memory read when DMA is busy
    
    wire addr_in_IF;
    wire addr_in_IE;
    wire addr_in_wram;
    wire addr_in_junk;
    wire addr_in_dma;
    wire addr_in_timer;
    wire addr_in_echo;
    wire addr_in_audio;
    wire addr_in_bootstrap;
    wire addr_in_brom;
    wire addr_in_cart;
    wire addr_in_cram;
    wire addr_in_ppu;
    wire addr_in_vram;
    wire addr_in_oamram;
    wire addr_in_joystick;
    
    wire brom_tri_en; // Allow BROM output to the Data bus
    wire wram_tri_en; // Allow WRAM
    wire junk_tri_en; // Undefined
    wire sound_tri_en; // Allow Sound Registers
    wire video_tri_en; // Allow PPU (including VRAM and OAM)
    wire bootstrap_tri_en; // Allow BROM enable reg
    wire cart_tri_en; // Allow Cartridge
    wire ie_tri_en; // Allow Interrupt Enable
    wire if_tri_en; // Allow Interrupt Flag
    wire joystick_tri_en; // Allow Joystick Register
    
    wire [7:0] bootstrap_reg_data;
    wire [7:0] joystick_reg_data;
    wire [7:0] brom_data;
    
    // Interrupt Signals
    // IE: Interrupt Enable
    // IF: Interrupt Flag
    //wire [4:0]  IE_data;  // IE output 
    wire [4:0]  IF_in;    // IE input
    //wire [4:0]  IF_data;  // IF output
    wire [4:0]  IE_in;    // IE input
    wire [4:0]  IF_in_int;// ?
    wire        IE_load;  // IE load to CPU enable
    wire        IF_load;  // IF load to CPU enable
    
    localparam I_HILO = 4;
    localparam I_SERIAL = 3;
    localparam I_TIMER = 2;
    localparam I_LCDC = 1;
    localparam I_VBLANK = 0;
    
    wire int_vblank_req;
    wire int_lcdc_req;
    wire int_vblank_ack;
    wire int_lcdc_ack;
    wire int_tim_req;
    wire int_tim_ack;
   
    //DMA
    dma gb80_dma(
        .dma_mem_re(dma_mem_re),
        .dma_mem_we(dma_mem_we),
        .addr_ext(addr_ext),
        .data_ext(data_ext),
        .mem_we(cpu_mem_we),
        .mem_re(cpu_mem_re),
        .cpu_mem_disable(cpu_mem_disable),
        .clock(clk),
        .reset(rst),
        .dma_chipscope(dma_chipscope));

    assign mem_we = cpu_mem_we | dma_mem_we;
    assign mem_re = cpu_mem_re | dma_mem_re;

    // Interrupt
    assign addr_in_IF = addr_ext == `MMIO_IF;
    assign addr_in_IE = addr_ext == `MMIO_IE;
    
    // IE loading is taken care of CPU-internally
    assign IE_load = 1'b0;
    assign IE_in = 5'd0;
    
    assign int_lcdc_ack = IF_data[I_LCDC];
    assign int_vblank_ack = IF_data[I_VBLANK];
    assign int_tim_ack = IF_data[I_TIMER];
    
    assign IF_load = int_lcdc_req | int_vblank_req | int_tim_req | (addr_in_IF & mem_we);
    
    assign IF_in_int[I_VBLANK] = int_vblank_req | (IF_data[I_VBLANK] & IF_load);
    assign IF_in_int[I_LCDC] = int_lcdc_req | (IF_data[I_LCDC] & IF_load);
    assign IF_in_int[I_TIMER] = int_tim_req | (IF_data[I_TIMER] & IF_load);
   
    assign IF_in = (addr_in_IF & mem_we) ? data_ext : IF_in_int;
    
    // CPU
    cpu cpu(
        .mem_we(cpu_mem_we),
        .mem_re(cpu_mem_re),
        .halt(halt),
        .debug_halt(debug_halt),
        .addr_ext(addr_ext),
        .data_ext(data_ext),
        .clock(clk),
        .reset(rst),
        .clk_1m(clk_1m),
        .A_data(A_data),
        .F_data(F_data),
        .high_mem_data(high_mem_data[7:0]),
        .high_mem_addr(high_mem_addr[15:0]),
        .instruction(instruction),
        .regs_data(regs_data),
        .IF_data(IF_data),
        .IE_data(IE_data),
        .IF_in(IF_in),
        .IE_in(IE_in),
        .IF_load(IF_load),
        .IE_load(IE_load),
        .cpu_mem_disable(cpu_mem_disable),
        .bp_addr(bp_addr),
        .bp_step(bp_step),
        .bp_continue(bp_continue));
        
    // PPU
    ppu ppu(
        .clk(clk),
        .clk_mem(clk_mem),
        .rst(rst),
        .a(addr_ext),
        .dout(do_video), // VRAM & OAM RW goes through PPU
        .din(data_ext),
        .rd(mem_re), 
        .wr(mem_we),
        .int_vblank_req(int_vblank_req),
        .int_lcdc_req(int_lcdc_req),
        .int_vblank_ack(int_vblank_ack),
        .int_lcdc_ack(int_lcdc_ack),
        .cpl(cpl), // Pixel clock
        .pixel(pixel), // Pixel Data (2bpp)
        .valid(valid),
        .hs(hs), // Horizontal Sync, Low Active
        .vs(vs), // Vertical Sync, Low Active
        //Debug
        .scx(scx),
        .scy(scy)
    );
    
    // Audio
    sound sound(
        .clk(clk),
        .rst(rst),
        .a(addr_ext),
        .dout(do_audio),
        .din(data_ext),
        .rd(mem_re),
        .wr(mem_we),
        .left(left),
        .right(right),
        .ch1_level(ch1_level),
        .ch2_level(ch2_level),
        .ch3_level(ch3_level),
        .ch4_level(ch4_level)
    );
    
    // Timer 
    timer timer(
        .clk(clk),
        .clk_1m(clk_1m),
        .rst(rst),
        .a(addr_ext),
        .dout(do_timer),
        .din(data_ext),
        .rd(mem_re),
        .wr(mem_we),
        .int_tim_req(int_tim_req),
        .int_tim_ack(int_tim_ack)
    );
    
    // Joystick
    register #(4) joystick_reg(
        .d(data_ext[7:4]),
        .q(joystick_reg_data[7:4]),
        .load(addr_in_joystick & mem_we),
        .reset(rst),
        .clock(clk));
    assign joystick_reg_data[3:0] = 
        ~(((joystick_reg_data[5] == 1'b1) ? (key[7:4]) : 4'h0) | 
          ((joystick_reg_data[4] == 1'b1) ? (key[3:0]) : 4'h0)); 
    assign joystick[7:0] = joystick_reg_data[7:0];
    
    // Memory related
    assign addr_in_brom = (bootstrap_reg_data[0]) ? 1'b0 : addr_ext < 16'h103;
    assign addr_in_bootstrap = addr_ext == `MMIO_BOOTSTRAP;
    assign addr_in_echo   = (addr_ext >= `MEM_ECHO_START) & (addr_ext <= `MEM_ECHO_END);
    assign addr_in_wram   = (addr_ext >= `MEM_WRAM_START) & (addr_ext <= `MEM_WRAM_END);
    assign addr_in_dma    =  addr_ext == `MMIO_DMA;
    assign addr_in_timer  = (addr_ext == `MMIO_DIV) |
                            (addr_ext == `MMIO_TMA) |
                            (addr_ext == `MMIO_TIMA) |
                            (addr_ext == `MMIO_TAC);
    assign addr_in_audio  =((addr_ext >= 16'hFF10 && addr_ext <= 16'hFF1E) ||
                            (addr_ext >= 16'hFF30 && addr_ext <= 16'hFF3F) ||
                            (addr_ext >= 16'hFF20 && addr_ext <= 16'hFF26));
    assign addr_in_ppu    = (addr_ext >= 16'hFF40 && addr_ext <= 16'hFF4B && addr_ext != `MMIO_DMA);
    assign addr_in_vram   = (addr_ext >= 16'h8000 && addr_ext <= 16'h9FFF);
    assign addr_in_oamram = (addr_ext >= 16'hFE00 && addr_ext <= 16'hFE9F);
    assign addr_in_cram = ((`MEM_CRAM_START <= addr_ext) && 
                          (addr_ext <= `MEM_CRAM_END));
    assign addr_in_cart = (bootstrap_reg_data[0]) ?
                          // Cart ROM
                          (((`MEM_CART_START <= addr_ext) && (addr_ext <= `MEM_CART_END)) |
                          // OR cart RAM
                          addr_in_cram) :
                          // Cart ROM minus the bootstrap
                          // Should the start be 100 or 104?
                          (((16'h100 <= addr_ext) && (addr_ext <= `MEM_CART_END)) |
                          // OR cart RAM
                          addr_in_cram);
    assign addr_in_joystick = (addr_ext == `MMIO_JOYSTICK);
    assign addr_in_junk = ~addr_in_brom & ~addr_in_audio &
                          ~addr_in_timer & ~addr_in_wram &
                          ~addr_in_dma &  
                          ~addr_in_ppu & ~addr_in_vram &
                          ~addr_in_oamram & ~addr_in_joystick &
                          ~addr_in_cart & ~addr_in_echo & 
                          ~addr_in_IE & ~addr_in_IF;
    /*assign addr_in_junk = ~addr_in_brom & ~addr_in_audio &
                          ~addr_in_tima & ~addr_in_wram &
                          ~addr_in_dma & ~addr_in_tima & 
                          ~video_reg_w_enable & ~video_vram_w_enable &
                          ~video_oam_w_enable & ~addr_in_bootstrap_reg & 
                          ~addr_in_cart & ~addr_in_echo & ~addr_in_controller &
                          ~addr_in_IE & ~addr_in_IF & ~addr_in_SB & ~addr_in_SC;*/
    // WRAM
    wire        wram_we;
    wire [12:0] wram_addr;
    wire [7:0]  wram_data_in;
    wire [7:0]  wram_data_out;
    wire [15:0] wram_addr_long;
    assign wram_data_in = data_ext;
    assign wram_we = addr_in_wram & mem_we;
    assign wram_addr_long = (addr_in_echo) ? 
                            addr_ext - `MEM_ECHO_START : 
                            addr_ext - `MEM_WRAM_START;
    assign wram_addr = wram_addr_long[12:0]; // 8192 elts 

    blockram8192 br_wram(
        .clka(clk_mem),
        .wea(wram_we),
        .addra(wram_addr),
        .dina(wram_data_in),
        .douta(wram_data_out));
             
    // BROM
    register #(8) bootstrap_reg(
        .d(data_ext),
        .q(bootstrap_reg_data),
        .load(addr_in_bootstrap & mem_we),
        .reset(rst),
        .clock(clk));
    brom brom(
        .a(addr_ext[7:0]),
        .d(brom_data));
        
    // Bus
    assign dout = data_ext;
    assign a = addr_ext;
    assign wr = mem_we;
    assign rd = mem_re;
    
    assign brom_tri_en = addr_in_brom & ~mem_we;
    assign bootstrap_tri_en = addr_in_bootstrap & ~mem_we;
    assign wram_tri_en = (addr_in_wram | addr_in_echo) & ~mem_we & mem_re;
    assign junk_tri_en = addr_in_junk & ~mem_we;
    assign sound_tri_en = (addr_in_audio) & ~mem_we;
    assign timer_tri_en = (addr_in_timer) & ~mem_we;
    assign video_tri_en = (addr_in_ppu | addr_in_vram | addr_in_oamram) & ~mem_we;
    assign cart_tri_en = addr_in_cart & ~mem_we;
    assign joystick_tri_en = addr_in_joystick & ~mem_we;
    assign ie_tri_en = addr_in_IE & mem_re;
    assign if_tri_en = addr_in_IF & mem_re;
    
    tristate #(8) gating_brom(
        .out(data_ext),
        .in(brom_data),
        .en(brom_tri_en));
    tristate #(8) gating_boostrap_reg(
        .out(data_ext),
        .in(bootstrap_reg_data),
        .en(bootstrap_tri_en));
    tristate #(8) gating_wram(
        .out(data_ext),
        .in(wram_data_out),
        .en(wram_tri_en));
    tristate #(8) gating_junk(
        .out(data_ext),
        .in(8'h00),
        .en(junk_tri_en));
    tristate #(8) gating_video_regs(
        .out(data_ext),
        .in(do_video),
        .en(video_tri_en));
    tristate #(8) gating_timer(
        .out(data_ext),
        .in(do_timer),
        .en(timer_tri_en));
    tristate #(8) gating_cart(
        .out(data_ext),
        .in(din),
        .en(cart_tri_en));
    tristate #(8) gating_joystick(
        .out(data_ext),
        .in(joystick_reg_data),
        .en(joystick_tri_en));
    tristate #(8) gating_sound_regs(
        .out(data_ext),
        .in(do_audio), 
        .en(sound_tri_en));
    tristate #(8) gating_IE(
        .out(data_ext),
        .in({3'd0, IE_data}),
        .en(ie_tri_en));
    tristate #(8) gating_IF(
        .out(data_ext),
        .in({3'd0, IF_data}),
        .en(if_tri_en));
    

   /*// Magic controller disable bits: 10101010 (AA)
   wire [7:0]  cont_reg_in;
   assign cont_reg_in = (bp_addr_part_in == 8'b10101010) ?
                        8'hff :
                        FF00_data_out;
   tristate #(8) gating_cont_reg(.out(data_ext),
                                 .in(FF00_data_out),
                                 .en(addr_in_controller & ~mem_we));*/
   
   
   
   
   

endmodule
