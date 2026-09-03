`timescale 1ns / 1ps
//
// AXI4 slave wrapper for Renode co-simulation of PL_DDR_BRAM.
//
// IMPORTANT - ADDRESS OFFSETS: Renode passes addresses RELATIVE to this
// peripheral's registration base in the .repl/monitor command, NOT absolute
// system addresses. This wrapper is written assuming registration at
// sysbus base 0x10000000 (confirmed by $display diagnostic evidence in prior
// debug session). If you register at a different base, recompute every
// *_BASE constant below as (absolute_address - registration_base).
//
// Relative offsets used here (registration base = 0x10000000):
//   DDR   (absolute 0x10000000) -> relative 0x00000000
//   BRAM0 (absolute 0xC0000000) -> relative 0xB0000000
//   BRAM1 (absolute 0xC2000000) -> relative 0xB2000000
//   GPIO  (absolute 0x41200000) -> relative 0x31200000
//   CDMA  (absolute 0x7E200000) -> relative 0x6E200000
//
// RESET POLARITY: rst is ACTIVE HIGH, matching axi_ram.v / Axi::reset()
// (Axi::reset() does aresetn=1 pulse then aresetn=0 hold - axi_ram.v's own
// FSMs use "if (rst) begin <reset> end", i.e. active-high on this signal
// despite the C++ variable being named "aresetn"). PL_DDR_BRAM.v genuinely
// needs active-LOW rst_n (confirmed: "if (!rst_n)" in its own source), so we
// derive pl_rst_n = !rst specifically for that instantiation.
//
// GPIO CHANNEL 1 (PS->PL control, matches C code's XGpio_DiscreteWrite ch1):
//   bit0 = DDR_BRAM0_W        bit1 = BRAM0_BRAM1_w
//   bit2 = BRAM1_DDR_W        bit3 = BRAM1_DDR_W_com
//   bit4 = restar_process_w
//
// GPIO CHANNEL 2 (PL->PS status, matches C code's poll_gpio_until_set masks):
//   bit0 = trans_out                    bit1 = DDR_BRAM0_trans_com_out
//   bit2 = BRAM0_BRAM1_trans_com_out    bit3 = comple_transaction_out
//
// NOTE ON FIX (Verilator UNSIGNED lint):
//   DDR_BASE == 32'h0, and addr/src are unsigned 32-bit values, so the
//   comparison "addr >= DDR_BASE" (i.e. addr >= 0) is always true and was
//   flagged by Verilator as a constant/tautological comparison
//   (%Warning-UNSIGNED), which the build treats as fatal. The lower-bound
//   check against DDR_BASE has been removed in all three DDR range checks
//   below since it can never be false; the upper-bound check alone is
//   sufficient to identify the DDR region. No functional change.
//
module top_axi_wrapper #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst,

    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    output reg [ID_WIDTH-1:0]       s_axi_bid,
    output reg [1:0]                s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    output reg [ID_WIDTH-1:0]       s_axi_rid,
    output reg [DATA_WIDTH-1:0]     s_axi_rdata,
    output reg [1:0]                s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);

    wire pl_rst_n = !rst;

    reg [31:0] bram0_store [0:511];
    reg [31:0] bram1_store [0:511];
    reg [31:0] ddr_store   [0:32767];

    reg [31:0] gpio_ch1;
    reg [31:0] gpio_ch2;

    reg [31:0] cdma_cr;
    reg [31:0] cdma_sr = 32'h00000002;
    reg [31:0] cdma_sa;
    reg [31:0] cdma_da;
    reg [31:0] cdma_btt;

    localparam DDR_BASE   = 32'h00000000;
    localparam BRAM0_BASE = 32'hB0000000;
    localparam BRAM1_BASE = 32'hB2000000;
    localparam GPIO_BASE  = 32'h31200000;
    localparam CDMA_BASE  = 32'h6E200000;

    // Renode sysbus registration base for this CoSimulatedPeripheral (must match
    // the address used in the .resc: "pl_ddr_bram ... @ sysbus <REG_BASE, +size>").
    // AXI target addresses (awaddr/araddr) arrive already relative to this base
    // because Renode subtracts it before invoking the co-sim callback. CDMA SA/DA
    // are register *payload data* written by the CPU using absolute system
    // addresses (as real AXI CDMA hardware requires), so Renode never touches
    // them - they must be converted to the same relative space manually before
    // being compared against DDR_BASE/BRAM0_BASE/BRAM1_BASE below, or every
    // range check silently fails and do_cdma_transfer becomes a no-op.
    localparam REG_BASE   = 32'h10000000;

    wire        pl_bram0_clkb, pl_bram1_clkb;
    wire [31:0] pl_bram0_addrb, pl_bram1_addrb;
    wire [31:0] pl_bram0_dinb,  pl_bram1_dinb;
    reg  [31:0] pl_bram0_doutb, pl_bram1_doutb;
    wire        pl_bram0_enb,   pl_bram1_enb;
    wire        pl_bram0_rstb,  pl_bram1_rstb;
    wire [3:0]  pl_bram0_web,   pl_bram1_web;

    wire trans_out_w, ddr_bram0_com_w, bram0_bram1_com_w, comple_out_w, tf_out_w, unused_out_w;

    wire pl_DDR_BRAM0_W     = gpio_ch1[0];
    wire pl_BRAM0_BRAM1_w   = gpio_ch1[1];
    wire pl_BRAM1_DDR_W     = gpio_ch1[2];
    wire pl_BRAM1_DDR_W_com = gpio_ch1[3];
    wire pl_restar_process_w= gpio_ch1[4];

    PL_DDR_BRAM u_pl (
        .clk(clk),
        .rst_n(pl_rst_n),
        .DDR_BRAM0_W(pl_DDR_BRAM0_W),
        .BRAM0_BRAM1_w(pl_BRAM0_BRAM1_w),
        .BRAM1_DDR_W(pl_BRAM1_DDR_W),
        .BRAM1_DDR_W_com(pl_BRAM1_DDR_W_com),
        .restar_process_w(pl_restar_process_w),
        .trans_out(trans_out_w),
        .DDR_BRAM0_trans_com_out(ddr_bram0_com_w),
        .BRAM0_BRAM1_trans_com_out(bram0_bram1_com_w),
        .comple_transaction_out(comple_out_w),
        .transaction_finish_out(tf_out_w),
        .unused_out(unused_out_w),
        .bram0_addrb(pl_bram0_addrb),
        .bram0_clkb(pl_bram0_clkb),
        .bram0_dinb(pl_bram0_dinb),
        .bram0_doutb(pl_bram0_doutb),
        .bram0_enb(pl_bram0_enb),
        .bram0_rstb(pl_bram0_rstb),
        .bram0_web(pl_bram0_web),
        .bram1_addrb(pl_bram1_addrb),
        .bram1_clkb(pl_bram1_clkb),
        .bram1_dinb(pl_bram1_dinb),
        .bram1_doutb(pl_bram1_doutb),
        .bram1_enb(pl_bram1_enb),
        .bram1_rstb(pl_bram1_rstb),
        .bram1_web(pl_bram1_web)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gpio_ch2 <= 32'h0;
        end else begin
            gpio_ch2[0] <= trans_out_w;
            gpio_ch2[1] <= ddr_bram0_com_w;
            gpio_ch2[2] <= bram0_bram1_com_w;
            gpio_ch2[3] <= comple_out_w;
        end
    end

    always @(posedge clk) begin
        if (pl_bram0_enb)
            pl_bram0_doutb <= bram0_store[pl_bram0_addrb[10:2]];
        if (pl_bram1_enb && pl_bram1_web != 4'h0)
            bram1_store[pl_bram1_addrb[10:2]] <= pl_bram1_dinb;
        if (pl_bram1_enb)
            pl_bram1_doutb <= bram1_store[pl_bram1_addrb[10:2]];
    end

    localparam WRITE_IDLE = 2'd0, WRITE_BURST = 2'd1, WRITE_RESP = 2'd2;
    reg [1:0] write_state = WRITE_IDLE;
    reg [31:0] write_addr_reg;
    reg [7:0]  write_count_reg;
    reg [ID_WIDTH-1:0] write_id_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_state    <= WRITE_IDLE;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
        end else begin
            case (write_state)
                WRITE_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awready && s_axi_awvalid) begin
                        write_addr_reg  <= s_axi_awaddr;
                        write_count_reg <= s_axi_awlen;
                        write_id_reg    <= s_axi_awid;
                        s_axi_awready   <= 1'b0;
                        s_axi_wready    <= 1'b1;
                        write_state     <= WRITE_BURST;
                    end
                end
                WRITE_BURST: begin
                    s_axi_wready <= 1'b1;
                    if (s_axi_wready && s_axi_wvalid) begin
                        write_word(write_addr_reg, s_axi_wdata, s_axi_wstrb);
                        write_addr_reg <= write_addr_reg + 32'h4;
                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bid    <= write_id_reg;
                            s_axi_bresp  <= 2'b00;
                            s_axi_bvalid <= 1'b1;
                            write_state  <= WRITE_RESP;
                        end
                    end
                end
                WRITE_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        write_state   <= WRITE_IDLE;
                    end
                end
                default: write_state <= WRITE_IDLE;
            endcase
        end
    end

    task write_word(input [31:0] addr, input [31:0] data, input [3:0] strb);
        begin
            if (addr < DDR_BASE + 32'h00020000) begin
                ddr_store[(addr - DDR_BASE) >> 2] = data;
            end
            else if (addr >= BRAM0_BASE && addr < BRAM0_BASE + 2048) begin
                bram0_store[(addr - BRAM0_BASE) >> 2] = data;
            end
            else if (addr >= BRAM1_BASE && addr < BRAM1_BASE + 2048) begin
                bram1_store[(addr - BRAM1_BASE) >> 2] = data;
            end
            else if (addr == GPIO_BASE) begin
                gpio_ch1 = data;
            end
            else if (addr == CDMA_BASE + 32'h00) begin
                cdma_cr = data;
                if (data[2]) cdma_cr[2] = 1'b0;
            end
            else if (addr == CDMA_BASE + 32'h18) cdma_sa  = data;
            else if (addr == CDMA_BASE + 32'h20) cdma_da  = data;
            else if (addr == CDMA_BASE + 32'h28) begin
                cdma_btt = data;
                // cdma_sa/cdma_da hold absolute system addresses as programmed by
                // the CPU (e.g. 0x10000000, 0xC0000000, 0xC2000000, 0x10010000).
                // Convert to REG_BASE-relative before use so they land in the
                // same address space as DDR_BASE/BRAM0_BASE/BRAM1_BASE.
                do_cdma_transfer(cdma_sa - REG_BASE, cdma_da - REG_BASE, data);
                cdma_sr = 32'h00001002;
            end
        end
    endtask

    integer k;
    task do_cdma_transfer(input [31:0] src, input [31:0] dst, input [31:0] btt);
        begin
            for (k = 0; k < (btt >> 2); k = k + 1) begin
                if (src < DDR_BASE + 32'h00020000)
                    write_word(dst + (k<<2), ddr_store[((src-DDR_BASE)>>2) + k], 4'hF);
                else if (src >= BRAM0_BASE && src < BRAM0_BASE+2048)
                    write_word(dst + (k<<2), bram0_store[((src-BRAM0_BASE)>>2) + k], 4'hF);
                else if (src >= BRAM1_BASE && src < BRAM1_BASE+2048)
                    write_word(dst + (k<<2), bram1_store[((src-BRAM1_BASE)>>2) + k], 4'hF);
            end
        end
    endtask

    function [31:0] read_word(input [31:0] addr);
        begin
            if (addr < DDR_BASE + 32'h00020000)
                read_word = ddr_store[(addr - DDR_BASE) >> 2];
            else if (addr >= BRAM0_BASE && addr < BRAM0_BASE + 2048)
                read_word = bram0_store[(addr - BRAM0_BASE) >> 2];
            else if (addr >= BRAM1_BASE && addr < BRAM1_BASE + 2048)
                read_word = bram1_store[(addr - BRAM1_BASE) >> 2];
            else if (addr == GPIO_BASE)
                read_word = gpio_ch1;
            else if (addr == GPIO_BASE + 32'h8)
                read_word = gpio_ch2;
            else if (addr == CDMA_BASE + 32'h00)
                read_word = cdma_cr;
            else if (addr == CDMA_BASE + 32'h04)
                read_word = cdma_sr;
            else if (addr == CDMA_BASE + 32'h18)
                read_word = cdma_sa;
            else if (addr == CDMA_BASE + 32'h20)
                read_word = cdma_da;
            else if (addr == CDMA_BASE + 32'h28)
                read_word = cdma_btt;
            else
                read_word = 32'h0;
        end
    endfunction

    localparam READ_IDLE = 1'd0, READ_BURST = 1'd1;
    reg read_state = READ_IDLE;
    reg [31:0] read_addr_reg;
    reg [7:0]  read_count_reg;
    reg [ID_WIDTH-1:0] read_id_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_state    <= READ_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
        end else begin
            case (read_state)
                READ_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arready && s_axi_arvalid) begin
                        read_addr_reg  <= s_axi_araddr;
                        read_count_reg <= s_axi_arlen;
                        read_id_reg    <= s_axi_arid;
                        s_axi_arready  <= 1'b0;
                        read_state     <= READ_BURST;
                    end
                end
                READ_BURST: begin
                    if (!s_axi_rvalid || s_axi_rready) begin
                        s_axi_rdata  <= read_word(read_addr_reg);
                        s_axi_rid    <= read_id_reg;
                        s_axi_rresp  <= 2'b00;
                        s_axi_rvalid <= 1'b1;
                        s_axi_rlast  <= (read_count_reg == 0);
                        if (read_count_reg == 0) begin
                            read_state    <= READ_IDLE;
                            s_axi_arready <= 1'b1;
                        end else begin
                            read_addr_reg  <= read_addr_reg + 32'h4;
                            read_count_reg <= read_count_reg - 1'b1;
                        end
                    end
                end
                default: read_state <= READ_IDLE;
            endcase
        end
    end

endmodule