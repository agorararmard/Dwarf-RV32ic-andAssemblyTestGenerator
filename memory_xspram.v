// file: memory.v
// author: @shalan


//`define _MEMDISP_ 	0

//MM IO
//`define    MMAP_PRINT	32'h80000000
//`define    LOGCAPH	14

`define B0_BOUND 7:0 
`define B1_BOUND 15:8 
`define B2_BOUND 23:16
`define B3_BOUND 31:24

module rv32i_mem_ctrl (baddr, bsz, bdi, mdi, mcs, bdo, mdo);
    input[1:0] baddr;
    input[1:0] bsz;
    input[31:0] bdi, mdo;
    output reg [31:0] mdi, bdo;
    output reg [3:0] mcs;

    wire szB=(bsz==2'b0);
    wire szH=(bsz==2'b01);
    wire szW=(bsz==2'b10);

    always @ * begin
    (* full_case *)
        (* parallel_case *)
        case ({baddr, szB, szH, szW})
            5'b00_001: begin mdi = bdi; mcs=4'b1111; end

            5'b00_010: begin mdi = bdi; mcs=4'b0011; end
            5'b10_010: begin mdi = bdi << 16; mcs=4'b1100; end

            5'b00_100: begin mdi = bdi; mcs=4'b0001; end
            5'b01_100: begin mdi = bdi << 8; mcs=4'b0010; end
            5'b10_100: begin mdi = bdi << 16; mcs=4'b0100; end
            5'b11_100: begin mdi = bdi << 24; mcs=4'b1000; end
        endcase

    end

    always @ * begin
    (* full_case *)
        (* parallel_case *)
        case ({baddr, szB, szH, szW})
            5'b00_001: bdo = mdo;

            5'b00_010: bdo = mdo;
            5'b10_010: bdo = mdo >> 16;

            5'b00_100: bdo = mdo;
            5'b01_100: bdo = mdo >> 8;
            5'b10_100: bdo = mdo >> 16;
            5'b11_100: bdo = mdo >> 24;
        endcase
    end

endmodule

module AHB2MEM
#(parameter MEMWIDTH = 10)					// SIZE = 1KB = 256 Words
(
	//AHBLITE INTERFACE
		//Slave Select Signals
			input wire HSEL,
		//Global Signal
			input wire HCLK,
			input wire HRESETn,
		//Address, Control & Write Data
			input wire HREADY,
			input wire [31:0] HADDR,
			input wire [1:0] HTRANS,
			input wire HWRITE,
			input wire [2:0] HSIZE,

			input wire [31:0] HWDATA,
		// Transfer Response & Read Data
			output wire HREADYOUT,
			//output reg [31:0] HRDATA
			output [31:0] HRDATA
);


  assign HREADYOUT = 1'b1; // Always ready

// Registers to store Adress Phase Signals

  reg APhase_HSEL;
  reg APhase_HWRITE;
  reg [1:0] APhase_HTRANS;
  reg [31:0] APhase_HADDR;
  reg [2:0] APhase_HSIZE;

// Memory Array
	wire[3:0] RDY;
	wire [MEMWIDTH-1:2] HADDR_;
	wire [31:0]	HRDATA_;

`ifdef _CEXT_
	wire tx_word_ =  HSIZE[1];
	wire word_at_10_ = tx_word_ & HADDR[1];
	//handle reading words at hw boundaries for _CEXT_
	assign HADDR_ = word_at_10_? HADDR[MEMWIDTH-1:2]+1'b1 : HADDR[MEMWIDTH-1:2];
`else
	assign HADDR_ = HADDR[MEMWIDTH-1:2];
`endif

	wire READ = ~HWRITE;
	//BANKS
	genvar i;
	XSPRAM_2048X8_M16P #(MEMWIDTH-2, 0) M0 (.Q(HRDATA_[`B0_BOUND]), .D(HWDATA[`B0_BOUND]),
											.A(APhase_HWRITE? APhase_HADDR[MEMWIDTH-1:2] : HADDR_), .CLK(HCLK),
	   										.CEn(~(HRESETn& (READ? HSEL : APhase_HSEL))), .WEn(~BYTE[0]), .OEn(1'b0), .RDY(RDY[0]));

	XSPRAM_2048X8_M16P #(MEMWIDTH-2, 1) M1 (.Q(HRDATA_[`B1_BOUND]), .D(HWDATA[`B1_BOUND]),
	   										.A(APhase_HWRITE? APhase_HADDR[MEMWIDTH-1:2] : HADDR_), .CLK(HCLK),
	   										.CEn(~(HRESETn& (READ? HSEL : APhase_HSEL))), .WEn(~BYTE[1]), .OEn(1'b0), .RDY(RDY[1]));

	XSPRAM_2048X8_M16P #(MEMWIDTH-2, 2) M2 (.Q(HRDATA_[`B2_BOUND]), .D(HWDATA[`B2_BOUND]),
	   										.A(APhase_HWRITE? APhase_HADDR[MEMWIDTH-1:2] : HADDR_), .CLK(HCLK),
	   										.CEn(~(HRESETn& (READ? HSEL : APhase_HSEL))), .WEn(~BYTE[2]), .OEn(1'b0), .RDY(RDY[2]));

	XSPRAM_2048X8_M16P #(MEMWIDTH-2, 3) M3 (.Q(HRDATA_[`B3_BOUND]), .D(HWDATA[`B3_BOUND]),
	   										.A(APhase_HWRITE? APhase_HADDR[MEMWIDTH-1:2] : HADDR_), .CLK(HCLK),
	   										.CEn(~(HRESETn& (READ? HSEL : APhase_HSEL))), .WEn(~BYTE[3]), .OEn(1'b0), .RDY(RDY[3]));

`ifdef _CEXT_
	//handle reading words at hw boundaries for _CEXT_
	//swap halfwords
	assign HRDATA = word_at_10? {HRDATA_[15:0], HRDATA_[31:16]} : HRDATA_;
	//assign HRDATA = HRDATA_;
`else
	assign HRDATA = HRDATA_;
`endif

`ifdef _DBUG_
	always @(*)
		$display ("HADDR = %h, HSZ= %b", HADDR, HSIZE);
	always @(*)
		$display ("HRDATA_ = %h", HRDATA_);
	always @(*)
		$display ("HRDATA = %h", HRDATA);
`endif
/*
  reg [31:0] memory[0:(2**(MEMWIDTH-2)-1)];

  initial
  begin
      $readmemh("./test.hex", memory);
  end
*/

// Sample the Address Phase
  always @(posedge HCLK or negedge HRESETn)
  begin
	 if(!HRESETn)
	 begin
		APhase_HSEL <= 1'b0;
      APhase_HWRITE <= 1'b0;
      APhase_HTRANS <= 2'b00;
		APhase_HADDR <= 32'h0;
		APhase_HSIZE <= 3'b000;
	 end
    else if(HREADY)
    begin
      APhase_HSEL <= HSEL;
      APhase_HWRITE <= HWRITE;
      APhase_HTRANS <= HTRANS;
		APhase_HADDR <= HADDR;
		APhase_HSIZE <= HSIZE;
    end
  end

// Decode the bytes lanes depending on HSIZE & HADDR[1:0]


  wire tx_byte = ~APhase_HSIZE[1] & ~APhase_HSIZE[0];
  wire tx_half = ~APhase_HSIZE[1] &  APhase_HSIZE[0];
  wire tx_word =  APhase_HSIZE[1];

  wire byte_at_00 = tx_byte & ~APhase_HADDR[1] & ~APhase_HADDR[0];
  wire byte_at_01 = tx_byte & ~APhase_HADDR[1] &  APhase_HADDR[0];
  wire byte_at_10 = tx_byte &  APhase_HADDR[1] & ~APhase_HADDR[0];
  wire byte_at_11 = tx_byte &  APhase_HADDR[1] &  APhase_HADDR[0];

  wire half_at_00 = tx_half & ~APhase_HADDR[1];
  wire half_at_10 = tx_half &  APhase_HADDR[1];

  wire word_at_00 = tx_word;
  wire word_at_10 = tx_word & APhase_HADDR[1]; //just for reading now

  wire byte0 = word_at_00 | half_at_00 | byte_at_00;
  wire byte1 = word_at_00 | half_at_00 | byte_at_01;
  wire byte2 = word_at_00 | half_at_10 | byte_at_10;
  wire byte3 = word_at_00 | half_at_10 | byte_at_11;

  wire [3:0] BYTE = {byte3, byte2, byte1, byte0} & {4{APhase_HSEL & APhase_HWRITE & APhase_HTRANS[1]}};
`ifdef _DBUG_
	always @ *
		$display("BYTE = %b, HWDATA = %h", BYTE,  HWDATA);

`endif
// Writing to the memory

/////////////////////////////////////////////////////
//TESTING ONLY:
	 `ifdef _TRACE_
  always @(posedge HCLK)
  begin
	 if(APhase_HSEL & APhase_HWRITE & APhase_HTRANS[1])
	 begin
		 $display("MEM[%0d] = %h", APhase_HADDR, HWDATA);
	  end
  end
	 `endif
/////////////////////////////////////////////////////

endmodule

`ifdef _XSPRAM_
//USE `include

// TOP_MODULE         XSPRAM_2048X8_M16P
// ADDRESSES          2048
// BITS               8
// MUX                16
// CELL_SIZE_X        381.12    [um]
// CELL_SIZE_Y        439.75    [um]
// CELL_AREA          167597.81 [um^2]
// NOM_VDD18M         1.8      [V]
// WC_VDD18M          1.62      [V]
// CYCLE              5.73      [ns]
// MAXTEMP            125       [C]
// MAXLOAD            0.2       [pF]
// PVT_FAST           wp 1.98 -40 [] [V] [C]
// PVT_TYP            tm 1.80  25 [] [V] [C]
// PVT_SLOW           ws 1.62 175 [] [V] [C]
// L_NAV_MARK_MET1    DOTTED HOLE
// L_NAV_MARK_MET1_X  6.470
// L_NAV_MARK_MET1_Y  7.330
// 
// L_NAV_MARK_METTP   DOTTED HOLE
// L_NAV_MARK_METTP_X 6.470
// L_NAV_MARK_METTP_Y 7.330


`celldefine

primitive XSPRAM_2048X8_M16P_DFF  (Q, D, C, RN, SN, NOTIFY);

    output Q;
    input  D, C, RN, SN, NOTIFY;
    reg    Q;

// FUNCTION : POSITIVE EDGE TRIGGERED D FLIP-FLOP WITH 
//            ASYNCHRONOUS ACTIVE LOW SET AND CLEAR.

    table

//  D    C    RN    SN   NTFY : Qt  : Qt+1
// ---- ---- ----- ----- ---- : --- : ----
// data clk  rst_n set_n ntfy : Qi  : Q_out           
// ---- ---- ----- ----- ---- : --- : ----

    *	 b    1     1	  ?   :  ?  :  -  ; // data changes, clk stable
    ?	 0    1     1	  ?   :  ?  :  -  ; // clocks off


    1  (0x)   1     ?	  ?   :  1  :  1  ; // possible clk of D=1, but Q=1
    0  (0x)   ?     1	  ?   :  0  :  0  ; // possible clk of D=0, but Q=0

    ?	 ?    1     0	  ?   :  ?  :  1  ; // async set
    ?	 ?    0     1	  ?   :  ?  :  0  ; // async reset

    0  (01)   ?     1	  ?   :  ?  :  0  ; // clocking D=0
    1  (01)   1     ?	  ?   :  ?  :  1  ; // clocking D=1

   					    // reduced pessimism: 
    ?    ?  (?1)    1     ?   :  ?  :  -  ; // ignore the edges on rst_n
    ?    ?    1   (?1)    ?   :  ?  :  -  ; // ignore the edges on set_n

    1  (x1)   1     ?     ?   :  1  :  1  ; // potential pos_edge clk, potential set_n, but D=1 && Qi=1
    0  (x1)   ?     1     ?   :  0  :  0  ; // potential pos_edge clk, potential rst_n, but D=0 && Qi=0

    1  (1x)   1     ?     ?   :  1  :  1  ; // to_x_edge clk, but D=1 && Qi=1
    0  (1x)   ?     1     ?   :  0  :  0  ; // to_x_edge clk, but D=0 && Qi=0

`ifdef    ATPG_RUN

    ?	 *    1     0	  ?   :  ?  :  1  ; // clk while async set	      // ATPG_RUN
    ?	 *    0     1	  ?   :  ?  :  0  ; // clk while async reset	      // ATPG_RUN
    ?	 ?    1     x	  ?   :  1  :  1  ; //   set=X, but Q=1		      // ATPG_RUN
    ?    ?    x     1	  ?   :  0  :  0  ; // reset=X, but Q=0		      // ATPG_RUN

`else
   					    // reduced pessimism: 
    1	 ?    1     x	  ?   :  1  :  1  ; //   set=X, but Q=1    	      // Vlg
    0	 b    1   (0x)	  ?   :  1  :  1  ; //   set=X, D=0, but Q=1   	      // Vlg
    0	 b    1   (1x)	  ?   :  1  :  1  ; //   set=X, D=0, but Q=1   	      // Vlg
   (??)	 b    1     ?	  ?   :  1  :  1  ; //   set=X, D=egdes, but Q=1      // Vlg
    ?  (?0)   1     x	  ?   :  1  :  1  ; //   set=X, neg_edge clk, but Q=1 // Vlg

    0    ?    x     1	  ?   :  0  :  0  ; // reset=X, but Q=0    	      // Vlg
    1    b  (0x)    1	  ?   :  0  :  0  ; // reset=X, D=1, but Q=0   	      // Vlg
    1    b  (1x)    1	  ?   :  0  :  0  ; // reset=X, D=1, but Q=0   	      // Vlg
   (??)  b    ?     1	  ?   :  0  :  0  ; // reset=X, D=egdes, but Q=0      // Vlg
    ?  (?0)   x     1	  ?   :  0  :  0  ; // reset=X, neg_edge clk, but Q=0 // Vlg
 
`endif // ATPG_RUN

    endtable

endprimitive
module XSPRAM_2048X8_M16P_RDY (CLK, RX, RY, WEn);
input CLK;
input WEn;
output RX;
output RY;

wire CLK_;
wire WEn_;
buf 	g0 (CLK_, CLK);
buf 	g1 (RX, CLK_);
buf 	g2 (RY, CLK_);
buf 	g3 (WEn_, WEn);

specify
	specparam
`ifdef DEFAULT_WORST_DELAY_OFF
		RDY_LOW_TIME_READ	=  (0.02),
		RDY_HIGH_TIME_READ =  (0.01),

		RDY_LOW_TIME_WRITE	=  (0.02),
		RDY_HIGH_TIME_WRITE =  (0.01);

`else
		RDY_LOW_TIME_READ	=  (1.05:1.65:3.25),
		RDY_HIGH_TIME_READ	=  (0.28:0.45:0.89),

		RDY_LOW_TIME_WRITE	=  (1.05:1.63:3.13),
		RDY_HIGH_TIME_WRITE	=  (0.27:0.43:0.85);
`endif
	if (WEn_ == 1'b1) (posedge CLK => (RX : 1'b0)) = (RDY_LOW_TIME_READ, 0);
	if (WEn_ == 1'b1) (posedge CLK => (RY : 1'b0)) = (RDY_HIGH_TIME_READ, 0);
	
	if (WEn_ == 1'b0) (posedge CLK => (RX : 1'b0)) = (RDY_LOW_TIME_READ, 0);
	if (WEn_ == 1'b0) (posedge CLK => (RY : 1'b0)) = (RDY_HIGH_TIME_READ, 0);

endspecify
endmodule

module XSPRAM_2048X8_M16P_RDYC (CLK, CLKD, CLKDZ);
    input CLK;
    output CLKD;
    output CLKDZ;
	wire CLK_;
    buf g0 (CLK_, CLK);
	buf g1 (CLKD, CLK_);
	buf g2 (CLKDZ, CLK_);
    specify
	(posedge CLK => (CLKD : 1'b0)) = (0.01, 0);
	(posedge CLK => (CLKDZ : 1'b0)) = (0, 0);
    endspecify
endmodule

module XSPRAM_2048X8_M16P #(parameter MEMWIDTH = 10, INDEX = 0) (Q, D, A, CLK, CEn, WEn, OEn, RDY);

localparam HBank = 2**(MEMWIDTH);

output [7:0]	 	  Q;		// RAM data output

input  [7:0]		  D;		// RAM data input bus
input  [MEMWIDTH-1:0] A;		// RAM address bus
input				CLK; 		// RAM clock
input				CEn;		// RAM enable
input				WEn;		// RAM  write enable, 0-active
input				OEn;		// RAM  output enable, 0-active
output				RDY;		// Test output

//parameter ram_init_file = "./test.hex";

wire   [7:0]   QI;
wire   [7:0]   D_;
wire   [MEMWIDTH-1:0]   A_;

wire CLK_, CEn_, WEn_, OEn_;
`ifdef NEG_TCHK
// -- specify buffers: --
wire   [7:0]   D_d;
wire   [MEMWIDTH:0]   A_d;

buf	
	gBufCLK (CLK_, CLK_d),
	gBufCEn (CEn_, CEn_d),
	gBufWEn (WEn_, WEn_d),
	gBufOEn (OEn_, OEn);
`else
buf	
	gBufCLK (CLK_, CLK),
	gBufCEn (CEn_, CEn),
	gBufWEn (WEn_, WEn),
	gBufOEn (OEn_, OEn);
`endif
//genvar i;
`ifdef NEG_TCHK
	generate
		for (i = 0; i < MEMWIDTH; i = i + 1)
			buf gBuf (A_[i], A_d[i]);
	endgenerate
	/*
	buf gBufA_1_ (A_[1], A_d[1]);
	buf gBufA_2_ (A_[2], A_d[2]);
	buf gBufA_3_ (A_[3], A_d[3]);
	buf gBufA_4_ (A_[4], A_d[4]);
	buf gBufA_5_ (A_[5], A_d[5]);
	buf gBufA_6_ (A_[6], A_d[6]);
	buf gBufA_7_ (A_[7], A_d[7]);
	buf gBufA_8_ (A_[8], A_d[8]);
	buf gBufA_9_ (A_[9], A_d[9]);
	buf gBufA_10_ (A_[10], A_d[10]);
	*/

	buf gBufD_0_ (D_[0], D_d[0]);
	buf gBufD_1_ (D_[1], D_d[1]);
	buf gBufD_2_ (D_[2], D_d[2]);
	buf gBufD_3_ (D_[3], D_d[3]);
	buf gBufD_4_ (D_[4], D_d[4]);
	buf gBufD_5_ (D_[5], D_d[5]);
	buf gBufD_6_ (D_[6], D_d[6]);
	buf gBufD_7_ (D_[7], D_d[7]);
`else
	generate
		for (i = 0; i < MEMWIDTH; i = i + 1)
			buf gBuf (A_[i], A[i]);
	endgenerate
	/*
	buf gBufA_0_ (A_[0], A[0]);
	buf gBufA_1_ (A_[1], A[1]);
	buf gBufA_2_ (A_[2], A[2]);
	buf gBufA_3_ (A_[3], A[3]);
	buf gBufA_4_ (A_[4], A[4]);
	buf gBufA_5_ (A_[5], A[5]);
	buf gBufA_6_ (A_[6], A[6]);
	buf gBufA_7_ (A_[7], A[7]);
	buf gBufA_8_ (A_[8], A[8]);
	buf gBufA_9_ (A_[9], A[9]);
	buf gBufA_10_ (A_[10], A[10]);
	*/

	buf gBufD_0_ (D_[0], D[0]);
	buf gBufD_1_ (D_[1], D[1]);
	buf gBufD_2_ (D_[2], D[2]);
	buf gBufD_3_ (D_[3], D[3]);
	buf gBufD_4_ (D_[4], D[4]);
	buf gBufD_5_ (D_[5], D[5]);
	buf gBufD_6_ (D_[6], D[6]);
	buf gBufD_7_ (D_[7], D[7]);

`endif

	bufif0 gBufQ_0_ (Q[0], QI[0], OEn_);
	bufif0 gBufQ_1_ (Q[1], QI[1], OEn_);
	bufif0 gBufQ_2_ (Q[2], QI[2], OEn_);
	bufif0 gBufQ_3_ (Q[3], QI[3], OEn_);
	bufif0 gBufQ_4_ (Q[4], QI[4], OEn_);
	bufif0 gBufQ_5_ (Q[5], QI[5], OEn_);
	bufif0 gBufQ_6_ (Q[6], QI[6], OEn_);
	bufif0 gBufQ_7_ (Q[7], QI[7], OEn_);

// logic:
wire supply_OK;
assign supply_OK = 1'b1;
wire enable;
not     gNotENM  (enable, CEn_);

`ifdef ATPG_RUN
and gAndENM (enableMem, enable, supply_OK);
`else
reg rt;
wire enableMem;
and gAndENM (enableMem, enable, supply_OK, rt);
`endif
wire WEnB;
not gNotWeb (WEnB, WEn_);
wire cleanWrite, possRead;
and gAndCleanWR  (cleanWrite, enableMem, WEnB);
and gAndPossRD  (possRead, enableMem, WEn_);

wire cleanWriteN, RW;
not gNotCW (cleanWriteN, cleanWrite);
and gAndRW (RW, possRead, cleanWriteN);

//*********************************

reg [7:0] RAM_matrix [0:HBank-1];
reg [7:0] QR;

wire T_OK_Q;
	bufif1 gBufQI_0_ (QI[0], QR[0], T_OK_Q);
	bufif1 gBufQI_1_ (QI[1], QR[1], T_OK_Q);
	bufif1 gBufQI_2_ (QI[2], QR[2], T_OK_Q);
	bufif1 gBufQI_3_ (QI[3], QR[3], T_OK_Q);
	bufif1 gBufQI_4_ (QI[4], QR[4], T_OK_Q);
	bufif1 gBufQI_5_ (QI[5], QR[5], T_OK_Q);
	bufif1 gBufQI_6_ (QI[6], QR[6], T_OK_Q);
	bufif1 gBufQI_7_ (QI[7], QR[7], T_OK_Q);


reg NOTIFY_REG, NOTIFY_A, NOTIFY_WEn;

wire T_OK_A ,T_OK_QI;
XSPRAM_2048X8_M16P_DFF CHK_A (T_OK_A, supply_OK, CLK_, 1'b1, 1'b1, NOTIFY_A);
XSPRAM_2048X8_M16P_DFF CHK_Q (T_OK_QI, supply_OK, CLK_, 1'b1, 1'b1, NOTIFY_REG);

wire RWL;
XSPRAM_2048X8_M16P_DFF CHK_WEn (RWL, RW, CLK_, 1'b1, 1'b1, NOTIFY_WEn);

wire TOK, NRWL;
and gAndOk (TOK, T_OK_QI, T_OK_A, RWL);
not gNotRW (NRWL, RWL);
or gOrOk (T_OK_Q, NRWL, TOK);

// CLK short pulse generator
wire CLKD, CLKDZ, CSP;
XSPRAM_2048X8_M16P_RDYC sub2 (CLK_, CLKD, CLKDZ);
xnor gCSP (CSP, CLKD, CLKDZ);
// 
wire RX, RY, RDYi;
XSPRAM_2048X8_M16P_RDY sub3 (CSP, RX, RY, WEn_);
xor	gRDY (RDYi, RX, RY);
//
wire RDY_, T_OK_R;
buf RDYB (RDY, RDY_);
and	g36 (RDY_, RDYi, T_OK_R);
XSPRAM_2048X8_M16P_DFF CHK_R (T_OK_R, enable, CLK_, 1'b1, 1'b1, 1'b1);

/////////////////////////////////////////////////////
//TESTING ONLY:
reg [31:0] memory[0:(2**(MEMWIDTH)-1)];
integer li;
initial
begin
    $readmemh("./test.hex", memory);
	for (li = 0; li < 2**(MEMWIDTH); li = li + 1) begin
		RAM_matrix[li] = memory[li][8*INDEX+7:8*INDEX];
	end
	//if(ram_init_file !== "")
	  // 	$readmemb(ram_init_file, RAM_matrix);
end

/////////////////////////////////////////////////////

always @(posedge CLK_) if (possRead) begin
			QR[7:0] = RAM_matrix[A_];
		end
`ifdef     ATPG_RUN	
always @(posedge CLK_) if (cleanWrite) begin
			RAM_matrix[A_] = D_[7:0];
		end
`else
		else if (cleanWrite) begin
			RAM_matrix[A_] = D_[7:0];
			QR[7:0] = 8'hX;
		// inconsistent address:
		    if (^A_ === 1'bx)
		      begin
		      $display ("\n%t WARNING: %m : RAM write with inconsistent address", $realtime);
		      end 
		    if (A_ >= HBank)
		      begin
		      $display ("\n%t WARNING: %m : RAM write to non-existent address(hex) %h", $realtime, A);
		      end 
		 end
		else if ((cleanWrite === 1'bx) || (possRead === 1'bx)) 
		  begin
		    RAM_matrix[A_] = 8'hX;
		    QR[7:0] = 8'hX;
		  end
`endif //  ATPG_RUN 

specify
`ifdef DEFAULT_WORST_DELAY_OFF
// unit delay: 
specparam
		A_SETUP_TIME   = 0.02,
		A_HOLD_TIME    = 0.02,
		CEn_SETUP_TIME = 0.02,
		CEn_HOLD_TIME  = 0.02,
		WEn_SETUP_TIME = 0.02,
		WEn_HOLD_TIME  = 0.02,
		HIGH_Z_TIME    = 0.02,
		LOW_Z_TIME     = 0.02,
		D_SETUP_TIME   = 0.02,
		D_HOLD_TIME    = 0.02,
		CLK_LOW_TIME   = 0.02,
		CLK_HIGH_TIME  = 0.02,
		CYCLE_TIME     = 0.04,
		ACCESS_TIME    = 0.02,
		RDY_HIGH_TIME_READ = 0.02,
		RDY_LOW_TIME_READ = 0.03,
		RDY_HIGH_TIME_WRITE = 0.02,
		RDY_LOW_TIME_WRITE = 0.03;

`else

// worst operating conditions according to the specification:
// PVT:          ws, 1.62V, 175C
// input slope:  0.4ns
// CLoad:        0.2pF
specparam
		A_SETUP_TIME   = 1.658,
		A_HOLD_TIME    = 1.066,
		CEn_SETUP_TIME = 2.352,
		CEn_HOLD_TIME  = 0.745,
		WEn_SETUP_TIME = 1.879,
		WEn_HOLD_TIME  = 1.033,
		HIGH_Z_TIME    = 0.537,
		LOW_Z_TIME     = 0.805,
		D_SETUP_TIME   = 0.557,
		D_HOLD_TIME    = 1.295,
		CLK_LOW_TIME   = 1.645,
		CLK_HIGH_TIME  = 1.128,
		CYCLE_TIME     = 6.141,
		ACCESS_TIME    = 4.682,
		RDY_HIGH_TIME_READ = 1.253,
		RDY_LOW_TIME_READ = 3.623,
		RDY_HIGH_TIME_WRITE = 1.214,
		RDY_LOW_TIME_WRITE = 3.513;
		
`endif      
	
	(posedge CLK => (Q[0] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[1] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[2] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[3] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[4] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[5] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[6] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);
	(posedge CLK => (Q[7] : 1'b0)) = (ACCESS_TIME, ACCESS_TIME);

	if((WEn==1'b1)&&(CLK!=1'b0)) (posedge CLK => (RDY : 1'b0)) = (RDY_HIGH_TIME_READ, RDY_LOW_TIME_READ);
	if((WEn==1'b0)&&(CLK!=1'b0)) (posedge CLK => (RDY : 1'b0)) = (RDY_HIGH_TIME_WRITE, RDY_LOW_TIME_WRITE);

	(OEn => Q[0]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[1]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[2]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[3]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[4]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[5]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[6]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);
	(OEn => Q[7]) = (LOW_Z_TIME, LOW_Z_TIME, HIGH_Z_TIME);

`ifdef     NEG_TCHK
	$setuphold  (posedge CLK &&& enableMem, posedge A[0], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[0]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[0], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[0]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[1], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[1]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[1], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[1]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[2], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[2]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[2], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[2]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[3], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[3]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[3], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[3]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[4], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[4]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[4], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[4]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[5], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[5]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[5], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[5]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[6], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[6]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[6], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[6]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[7], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[7]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[7], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[7]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[8], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[8]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[8], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[8]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[9], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[9]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[9], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[9]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[10], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[10]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[10], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[10]);
	$setuphold  (posedge CLK &&& enableMem, posedge A[11], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[11]);
	$setuphold  (posedge CLK &&& enableMem, negedge A[11], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A,,, CLK_d, A_d[11]);

	$setuphold  (posedge CLK &&& cleanWrite, posedge D[0], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[0]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[0], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[0]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[1], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[1]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[1], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[1]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[2], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[2]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[2], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[2]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[3], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[3]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[3], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[3]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[4], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[4]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[4], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[4]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[5], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[5]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[5], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[5]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[6], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[6]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[6], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[6]);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[7], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[7]);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[7], D_SETUP_TIME, D_HOLD_TIME,,,, CLK_d, D_d[7]);

	$setuphold  (posedge CLK, posedge CEn, CEn_SETUP_TIME, CEn_HOLD_TIME, NOTIFY_REG,,, CLK_d, CEn_d);
	$setuphold  (posedge CLK, negedge CEn, CEn_SETUP_TIME, CEn_HOLD_TIME, NOTIFY_REG,,, CLK_d, CEn_d);

	$setuphold  (posedge CLK &&& enableMem, posedge WEn, WEn_SETUP_TIME, WEn_HOLD_TIME, NOTIFY_WEn,,, CLK_d, WEn_d);
	$setuphold  (posedge CLK &&& enableMem, negedge WEn, WEn_SETUP_TIME, WEn_HOLD_TIME, NOTIFY_WEn,,, CLK_d, WEn_d);

`else
	$setuphold  (posedge CLK &&& enableMem, posedge A[0], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[0], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[1], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[1], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[2], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[2], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[3], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[3], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[4], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[4], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[5], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[5], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[6], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[6], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[7], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[7], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[8], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[8], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[9], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[9], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[10], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, posedge A[10], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[11], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);
	$setuphold  (posedge CLK &&& enableMem, negedge A[11], A_SETUP_TIME, A_HOLD_TIME, NOTIFY_A);

	$setuphold  (posedge CLK &&& cleanWrite, posedge D[0], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[0], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[1], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[1], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[2], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[2], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[3], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[3], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[4], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[4], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[5], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[5], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[6], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[6], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, posedge D[7], D_SETUP_TIME, D_HOLD_TIME);
	$setuphold  (posedge CLK &&& cleanWrite, negedge D[7], D_SETUP_TIME, D_HOLD_TIME);

	$setuphold  (posedge CLK, posedge CEn, CEn_SETUP_TIME, CEn_HOLD_TIME, NOTIFY_REG);
	$setuphold  (posedge CLK, negedge CEn, CEn_SETUP_TIME, CEn_HOLD_TIME, NOTIFY_REG);

	$setuphold  (posedge CLK &&& enableMem, posedge WEn, WEn_SETUP_TIME, WEn_HOLD_TIME, NOTIFY_WEn);
	$setuphold  (posedge CLK &&& enableMem, negedge WEn, WEn_SETUP_TIME, WEn_HOLD_TIME, NOTIFY_WEn);

`endif
	$width (posedge CLK &&& enableMem, CLK_HIGH_TIME, 0, NOTIFY_REG);
	$width (negedge CLK &&& enableMem, CLK_LOW_TIME, 0, NOTIFY_REG);

	$period (posedge CLK &&& enableMem, CYCLE_TIME, NOTIFY_REG);
	$period (negedge CLK &&& enableMem, CYCLE_TIME, NOTIFY_REG);

endspecify
`ifdef ATPG_RUN
`else
initial begin
	$timeformat (-9, 2, " ns", 0);
	rt = 1'b0;
	#250 ;		// no RAM activity permitted for first 250n sec. of sim.
	rt = 1'b1;
	end
always @(posedge CLK_)
	begin
	if(rt === 1'b0)
		begin
		if (CEn_ === 1'b0 ) $display ("\n%t: ERROR: %m : RAM enabled during initial 250ns: RAM content UNDEFINED\n", $realtime); 
		end
	end
`endif

endmodule

`endcelldefine

`endif
