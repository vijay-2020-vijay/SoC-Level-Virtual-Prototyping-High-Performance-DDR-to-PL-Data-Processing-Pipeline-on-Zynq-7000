`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////idia of this module //////////////////////////////////////////////////////////////////////////////////////////////
//DDR ──(64-bit AXI)──> CDMA ──(64-bit)──> AXI_BRAM_Ctrl0 ──(64-bit Port A)──> BRAM0 ──(32-bit Port B)──> PL Processing Unit
// ──(32-bit Port B)──> BRAM1 ──(64-bit Port A)──> AXI_BRAM_Ctrl1 ──(64-bit)──> CDMA ──> DDR//////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////biuilding a proper Handshakeing mechanisim with PS(ARM_Cotex_A9_processor)/////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module PL_DDR_BRAM (
    // System Signals
    input  wire        clk,////system//clk///conected to //FCLK_CLK0 of zynq_ps//50 Mhz//
    input  wire        rst_n,///////connected to the  peripheral_aresetn of processor system reset IP//

    // PS Control Inputs (from AXI GPIO / PS)
    input  wire        DDR_BRAM0_W,    // gpio_io_o[0]
    input  wire        BRAM0_BRAM1_w,  // gpio_io_o[1]
    input  wire        BRAM1_DDR_W,    // gpio_io_o[2]
    input  wire        BRAM1_DDR_W_com,// gpio_io_o[3]
    input  wire        restar_process_w,//gpio_io_o[4]

    // PL Status Outputs (to AXI GPIO / PS)
    output reg         trans_out,  /// gpio2_io_i[0]
    output reg         DDR_BRAM0_trans_com_out, /// gpio2_io_i[1]
    output reg         BRAM0_BRAM1_trans_com_out, /// gpio2_io_i[2]
    output reg         comple_transaction_out,   /// gpio2_io_i[3]
    output reg         transaction_finish_out,////external///comnnect to PACKAGE_PIN E15 
    output wire        unused_out,////external///connected to PACKAGE_PIN D15

    // BRAM0 Port B Interface (Read Input Data)
    output reg [31:0]  bram0_addrb,
    output wire        bram0_clkb,
    output reg [31:0]  bram0_dinb,   // Unused (read-only)
    input  wire[31:0]  bram0_doutb,  // Data read from BRAM0
    output reg         bram0_enb,
    output reg         bram0_rstb,
    output reg [3:0]   bram0_web,    // Read-only (4'h0)

    // BRAM1 Port B Interface (Write Output Data)
    output reg [31:0]  bram1_addrb,
    output wire        bram1_clkb,
    output reg [31:0]  bram1_dinb,   // Data to write to BRAM1
    input  wire[31:0]  bram1_doutb,  // Unused (write-only)
    output reg         bram1_enb,
    output reg         bram1_rstb,
    output reg [3:0]   bram1_web     // Write byte enables (4'hF)
);

reg [2:0] state;
//////////////actaully we will transfer 256 data from DDR to BRAM0///each data contain 64 bit ////BRAM0 and BRAM1 both are in BRAM_control_mode
/////////so they have 32 bit address ///byte addressable /////thats why we have chosen 512 ////////////////////////////////////////////////////
// Change this line from 256 to 512 (256 * 2)
localparam total_data = 10'd512;
localparam s0=3'd0; localparam s1=3'd1; localparam s2=3'd2;
localparam s3=3'd3; localparam s4=3'd4; localparam s5=3'd5;

reg [9:0] data_count;
assign bram0_clkb = clk;
assign bram1_clkb = clk;
assign unused_out = &bram1_doutb;  // Unused assignment wrapper///doing this to avoid unecessery warning///

always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                     <= s0; 
            trans_out                 <= 1'b0;  
            DDR_BRAM0_trans_com_out   <= 1'b0;
            BRAM0_BRAM1_trans_com_out <= 1'b0;
            comple_transaction_out    <= 1'b0;
            transaction_finish_out    <= 1'b0;
            
            bram0_addrb               <= 32'd0;
            bram0_dinb                <= 32'd0;
            bram0_enb                 <= 1'b0;
            bram0_rstb                <= 1'b0;
            bram0_web                 <= 4'h0;

            bram1_addrb               <= 32'd0;
            bram1_dinb                <= 32'd0;
            bram1_enb                 <= 1'b0;
            bram1_rstb                <= 1'b0;
            bram1_web                 <= 4'h0;

            data_count                <= 10'd0;
        end else begin
            case (state)
            s0: begin // Waiting for DDR -> BRAM0 transfer acknowledgment
               if (DDR_BRAM0_W == 1'b1) begin  /////once DDR is ready and start to send the data from that time //it will send DDR_BRAM0_W == 1'b1.
                  trans_out               <= 1'b1;/// means any data transformetion happend pl will infrm to ps  by "trans_out=1"/////////////////
                  DDR_BRAM0_trans_com_out <= 1'b0;///means pl will inform to ps that "transformetion is going on"
                  state                   <= s0;
               end
               else if (trans_out ==1'b1 && DDR_BRAM0_W == 1'b0) begin/////when DDR transfered all the 256 data to BRAM0 then //it will send DDR_BRAM0_W == 1'b0.
                  trans_out               <= 1'b0;
                  DDR_BRAM0_trans_com_out <= 1'b1;///certain conformetion send by pl to PS that we are ready to to receive next order 
                  ////"please do BRAM0_BRAM1_w == 1'b1"//
                  state                   <= s1;
               end   
            end     
            
            s1: begin // Ready for BRAM0 -> BRAM1 Processing
               if (BRAM0_BRAM1_w == 1'b1) begin//////////that means Ps have ordered to pl start transsition data between BRAM0 to BRAM1
                  trans_out               <= 1'b1;////means any transformetion happen pl will inform to PS by doing trans_out=1///////
                  DDR_BRAM0_trans_com_out <= 1'b0;////now it has no work ////so pl do it zero
                  /////reading happening from BRAM0 and writting happening on BRAM1//////required control signals has to be ativeted//
                  bram0_enb  <= 1'b1;  bram0_web  <= 4'h0;  bram0_rstb <= 1'b0;   ////reading happening
                  bram0_dinb <= 32'd0;
                  bram1_enb  <= 1'b1;  bram1_web  <= 4'hf;  bram1_rstb <= 1'b0;  /////writting happening
                  bram1_dinb <= 32'd0;
                  data_count <= 10'd0;
                  bram0_addrb<= 32'h0000_0000;
                  bram1_addrb<= 32'h0000_0000;
                  state      <= s2; 
               end
               else begin
                  state      <= s1; 
               end
            end
            s2: begin // Pipelined 32-bit Processing (BRAM0 Port B -> BRAM1 Port B)
               if (data_count == 10'd0) begin 
                   data_count  <= data_count + 1'b1;
               end
               else if (data_count <= total_data) begin
                   // Step address by 4 bytes for 32-bit asymmetric access width
                   ////not need to requird to adjust lsatency //here just motive is transformetion is happenig or not  
                   bram0_addrb <= bram0_addrb + 32'h4;
                   bram1_dinb  <= bram0_doutb + 32'h5;//////modifited the data slightly//////////////////////////            
                   if (data_count > 1) begin
                       bram1_addrb <= bram1_addrb + 32'h4; 
                   end
                   data_count <= data_count + 1'b1;
               end
               else if (data_count > total_data) begin
                   bram1_web                 <= 4'h0; 
                   bram0_web                 <= 4'h0; 
                   bram0_enb                 <= 1'b0; 
                   bram1_enb                 <= 1'b0;
                   BRAM0_BRAM1_trans_com_out <= 1'b1;/////////it will inform to ps that transformetion data from BRAM0 to BRAM1 is completed
                   ///please order me the next task/////means at the next time you need to sent "BRAM1_DDR_W == 1'b1" ok.
                   trans_out                 <= 1'b0;/////this also inform to ps that "now no dtata transformetion going on "
                   data_count                <= 10'd0;
                   state                     <= s3;
               end
            end
            s3: begin 
               if (BRAM1_DDR_W == 1'b1) begin///////////ps will give conformetion to pl ; start data transtion from BRAM1 to DDR
                  BRAM0_BRAM1_trans_com_out <= 1'b0;////its job is finished
                  trans_out                 <= 1'b1;////this shows that certain data transformetio is going on/////////////////
                  state                     <= s4;
               end
               else begin
                  state                     <= s3;
               end
            end
                 
            s4: begin // Final Completion & Reset Management
               if (BRAM1_DDR_W_com) begin/////////////////this is the kind of conformetion signl will be sent by ps to pl thaat all data
               /////////////////////////successfully reached to the DDR////
                  trans_out              <= 1'b0;////////no transformetion is happening
                  comple_transaction_out <= 1'b1;////this is the kind of conformetion signal sent to ps by pl that no further more trasformetion will happen 
                  transaction_finish_out <= 1'b1;/////external connect to certain mio pin /////
               end
               else if (restar_process_w == 1'b1) begin/// this time we donot need to reset the process////
               /////////////////////////////////in c code when ps show comple_transaction_out <= 1'b1 then it will sent restar_process_w == 1'b0;
               ////////because in that case only one cycle of transformetion i need ok.
                  comple_transaction_out <= 1'b0;
                  transaction_finish_out <= 1'b0;
                  state                  <= s0;
               end
               else begin
                  state                  <= s4;
               end
            end       
                     
            default: state <= s0;
            endcase
        end
    end

endmodule