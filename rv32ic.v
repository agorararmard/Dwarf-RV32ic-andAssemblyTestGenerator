/// file: phrv32CPU.v
// author: @shalan

/*  ********************************************************************************
3-Stages pipelined rv32i CPU

notes:
Every stage needs 2 clock cycles to avoid the need for L1 I & D caches.
The CPU fetches the instruction word @ the first clock cycle, c0 and
read/write memory @ the 2nd clock cycle c1

Target Performance (ASIC with custom Register File):
100 MHZ @ OSU 350nm process
~2500 cells + ~ 10 32-bit registers

log:
June 25, 17:    interlocked pieline that supports R & I arithmetic and
logic instructions (missing slt instructions).

June 26, 17:    added branch, and jal instructions. The pipeline is flushed
whenever a control instruction is observed. implement a simple
predictor (flush only when the branch is taken!)/

June 27, 17:    Added support for slt/sltu/slti/sltiu, load and store,
and LUI instructions. Need to add more test cases for load
instructions as well as JALR.

July 10, 17:    Code clean up, bugs fixing + some optimizations.

July 11, 17:    Added support for auipc instruction

July 16, 17:    More bugs fixing
Now passes test1, ui, loadstore, sub, shift, or, and j tests
sum.c test fails!

July 17, 17:    Fixed PC update logic to fix sum.c bug

July 20, 17:    Fixed most of the bugs. All test cases are OK now.
Had to update the build options in test.sh to get most of
them passed.

to do: revisit the code for optimizations:
(1) Propagate the control signals instead of IR
(2) revisit PC update logic
(3) revisit R1 and R2 registers

July 22, 17:    Adding support for multiplication through non-standard ext.
use opcode 10_001 - func3 will be used to specify the inst
For now, 000 UMUL

July 23, 17:    Added extensions support. Need to debug it as it is still
not fully working (add cu_custom_ control signal to R1 and
R2 write control).
It works now but 2 rf_wr cycles are generated. It is ok but
better to have one only.

July 24, 17:    Now extension works as an external component to the CPU

July 25, 17:    Refactored the code to isolate the control unit!
cpu.best.ys (ssh -i ~/.ssh/id_rsa root@51.15.57.38) is given:
Area: 3800 cells (326 FFs)
Clock Cycle: 5574 ps

To do:
+ Add Interrupts support (epc, cause, eret, ...)
+ Add performance counters (cycle and compare)

July 30, 17:    Specs for Interrupts Handeling (ver. 0.1)
* 6 vectors for RST=0, ecall=16, ebreak=32, timer=48,
error=64, ext. int=80
* Counters: 64-bit CYCLE and TIME counters only
* epc is used to store the return address
* uret instruction is used to return from an interrupt
pc <- epc
* non-standard CSR is used to enable/disable

July 31, 17:    Implemented Interrupts, counters and system instructions
Fix the timer interrupt (make it count micro seconds) and add
timer compare register

Aug 1, 2017:    mul.c fails when using the HW extension. Check it out (the rv32sim
could be the problem as it does not support the extension opcode)

Here is the updated plan for interrupts and counters/control registers:
(1) Only 32-bit Cycle and Time counters
(2) Only rdcycle/rdtime (csrrs using x0) and wrcycle/wrtime/wruie (csrrw)
instructions. The first 2 instructions are already supported pseudo
instructions. The other 2 instructions will be implemented as macros
using csrrw
(3) Timer is a down counter and generates an interrupt when it reaches 0.
Writing 0 to Timer disables it.
(4) WFI instruction is supported and must be followed by 2 nop instructions!
(5) URET instruction is implemented to return from an ISR
(6) There are 4 interrupt vectors starting from address 16. 4 words are left
for every ISR entry instructions.
(7) uie register is used for enabling and disabling interrupts

Aug 3, 2017:    Fixed several bugs and now Timer is functional and generates interrupts
uret is functional as well

Aug 5, 2017:    Needs major code review to refactor the code and discover possible hidden bugs.

Aug 6, 2017:    Did major re-structuring and code re-factoring

Aug 7, 2017:    Created a small interrupts controller.

Aug 8, 2017:    Need more testing for Interrupts
Idea:   move the rgister file write back to C1 to reduce the RF requirements.
This way a memory with 1 RW port and 1 R port is enough (RF has 3 ports)
Idea:   Port a simple RTOS!

Aug 17, 2017:   Noticed a bug in the interrupts.

Aug 19, 2017:   Fixed Interrupts handeling 
**********************************************************************************************  */


`timescale 1ns/1ns

`define     IR_rs1          19:15
`define     IR_rs2          24:20
`define     IR_rd           11:7
`define     IR_opcode       6:2
`define     IR_funct3       14:12
`define     IR_funct7       31:25
`define     IR_shamt        24:20
`define     IR_csr          31:20

`define     OPCODE_Branch   5'b11_000
`define     OPCODE_Load     5'b00_000
`define     OPCODE_Store    5'b01_000
`define     OPCODE_JALR     5'b11_001
`define     OPCODE_JAL      5'b11_011
`define     OPCODE_Arith_I  5'b00_100
`define     OPCODE_Arith_R  5'b01_100
`define     OPCODE_AUIPC    5'b00_101
`define     OPCODE_LUI      5'b01_101
`define     OPCODE_SYSTEM   5'b11_100 
`define     OPCODE_Custom   5'b10_001

`define     F3_ADD          3'b000
`define     F3_SLL          3'b001
`define     F3_SLT          3'b010
`define     F3_SLTU         3'b011
`define     F3_XOR          3'b100
`define     F3_SRL          3'b101
`define     F3_OR           3'b110
`define     F3_AND          3'b111

`define     BR_BEQ          3'b000
`define     BR_BNE          3'b001
`define     BR_BLT          3'b100
`define     BR_BGE          3'b101
`define     BR_BLTU         3'b110
`define     BR_BGEU         3'b111

`define     CUST_MUL        3'b000

`define     SYS_CSRRS       3'b010
`define     SYS_CSRRW       3'b001
`define     SYS_CSRRC       3'b011
`define     SYS_CSRRCI      3'b111
`define     CSR_cycle       12'hc00
`define     CSR_time        12'hc01
`define     CSR_instret     12'hc02
`define     CSR_uie         12'h004

`define     INST_NOP        32'h13
/*
`define     INST_CLRC       32'hc0101073
`define     INST_CLRCH      32'hc8101073
`define     INST_CLRT       32'hc0001073
`define     INST_CLRTH      32'hc8001073
*/
`define     INST_WFI        32'h10500073
`define     INST_EBREAK     32'h00100073
`define     INST_ECALL      32'h00000073
`define     INST_URET       32'h00200073

//`define     TICK            64'd30   // 0.01 msec @ 100MHz

`define     RESET_VEC       32'd0
`define     ECALL_VEC       32'd16
`define     EBREAK_VEC      32'd32
`define     TIMER_VEC       32'd48
`define     EINT_VEC        32'd64
//an address that selects none of the io dvcs
`define     ADDR_SELNONE    32'h40404040

//enablers

//`define     _EN_EXT_ 0  //for simulation only
`define     _XSPRAM_ 0
`define     _AHBL_ 0
//`define _FPGA_ 0


module top_kit(
		input clk, rst,

		output[31:0] bdi, baddr,
		output bwr,
		output[1:0] bsz,
		input[31:0] bdo,
		input brdy,

		output[4:0] rfrd, rfrs1, rfrs2,
		output rfwr,
		output[31:0] rfD,
		input[31:0] rfRS1, rfRS2,
		input [15:0] INT //reg for sim
	    );


	wire IRQ;
	wire [3:0] IRQnum;
	wire [15:0] IRQen;

	
	wire[2:0] extFunc3;

	IntCtrl INTCU(
			.clk(clk), .rst(rst),
			.INT(INT), .IRQen(IRQen),
			.IRQ(IRQ), .IRQnum(IRQnum)
		     );

	rv32_CPU_v2 CPU(
			.clk(clk),
			.rst(rst),
			.bdi(bdi), .bdo(bdo), .baddr(baddr), .bsz(bsz), .bwr(bwr),
			.rfwr(rfwr), .rfrd(rfrd), .rfrs1(rfrs1), .rfrs2(rfrs2), .rfD(rfD), .rfRS1(rfRS1), .rfRS2(rfRS2),

			.brdy(brdy),
			.IRQ(IRQ), .IRQnum(IRQnum), .IRQen(IRQen)
		       );


endmodule


module IntCtrl( 
	input clk, rst,
	input[15:0] INT, IRQen,
	output IRQ,
	output reg [3:0] IRQnum
);

	wire [15:0] IRQenINT = (INT & IRQen);
	assign IRQ = | IRQenINT;


	//always @ (posedge rst)
	//	IRQnum <= 4'd0;

	integer i;
	always @(*) begin
		IRQnum = 4'd0;
		for(i=1; i<16; i=i+1)
			if(IRQenINT[i] == 1'b1) IRQnum = i;
	end


endmodule

module rv32Counters(
	input clk, cyc, rst,
	output reg [31:0] Cycle, Timer, Instret, UIE, 
	output reg [3:0] UCause,
	input[31:0] wdata,
	input[4:0] uimm,
	input[3:0] IRQnum,
	input ld_cycle, ld_timer, ld_uie, inc_ret, 
	input c_cycle, c_timer, c_uie,
	output gie, tie, eie,
	output tif
);


	always @ (posedge clk or posedge rst)
		if(rst) Timer <= 32'd0;
		//csrrw
		else if(ld_timer && cyc) Timer <= wdata;
		//csrrci
		else if (c_timer && cyc) Timer <= Timer & {27'h7ffffff, ~uimm};
		else if(Timer!=32'b0) Timer <= Timer - 32'b1;

	always @ (posedge clk or posedge rst)
		if(rst) Cycle <= 32'd0;
		else if(ld_cycle && cyc) Cycle <= wdata;
		else if (c_cycle && cyc) Cycle <= Cycle & {27'h7ffffff, ~uimm};
		else Cycle <= Cycle + 32'b1;

	always @ (posedge clk or posedge rst)
		if(rst) Instret <= 32'd0;
		else if (inc_ret) Instret <= Instret + 32'b1;

	always @ (posedge clk or posedge rst)
		if(rst) UIE <= 32'd0; //optimize width
		else if(ld_uie && cyc) UIE <= wdata;
		else if (c_uie && cyc) UIE <= UIE & {27'h7ffffff, ~uimm};

	always @ (posedge clk or posedge rst)
		if(rst) UCause <= 32'd0;
		else UCause <= IRQnum;

	assign {eie, tie, gie} = UIE[2:0];
	assign tif = (Timer == 32'b1);



endmodule

module rv32dec(
	input[31:0] IR,
	output cu_br_inst,
	cu_jal_inst,
	cu_jalr_inst,
	cu_alu_i_inst,
	cu_alu_r_inst,
	cu_load_inst,
	cu_store_inst,
	cu_lui_inst,
	cu_auipc_inst,
	cu_custom_inst,
	cu_system_inst
);
	assign cu_br_inst = (IR[`IR_opcode]==`OPCODE_Branch);
	assign cu_jal_inst = (IR[`IR_opcode]==`OPCODE_JAL);
	assign cu_jalr_inst = (IR[`IR_opcode]==`OPCODE_JALR);
	assign cu_alu_i_inst = (IR[`IR_opcode]==`OPCODE_Arith_I);
	assign cu_alu_r_inst = (IR[`IR_opcode]==`OPCODE_Arith_R);
	assign cu_load_inst = (IR[`IR_opcode]==`OPCODE_Load);
	assign cu_store_inst = (IR[`IR_opcode]==`OPCODE_Store);
	assign cu_lui_inst = (IR[`IR_opcode]==`OPCODE_LUI);
	assign cu_auipc_inst = (IR[`IR_opcode]==`OPCODE_AUIPC);
	assign cu_custom_inst = (IR[`IR_opcode]==`OPCODE_Custom);
	assign cu_system_inst = (IR[`IR_opcode]==`OPCODE_SYSTEM);
endmodule

module rv32PCUnit(
	input clk, rst,
	input hold,cyc,
	input s0, s1, s2, s3, s4, reliable, ld_epc,sel_epc,
	input compressed,
    input cu_rst_state,
    output [31:0] PC_w,
	output reg [31:0] PC,
	input[31:0] PC1, I1, alu_r,
	input[4:0] vec
);

	reg[31:0] ePC;

	wire[31:0] pc_adder, nPC;

	wire[31:0] int_vec = {25'd0,vec,2'd0};


	assign pc_adder = (s2? I1 : (compressed? 32'd2 : 32'd4)) + (s2? PC1 : PC);

	assign nPC = s1 ? alu_r : pc_adder;

    assign PC_w = cu_rst_state? 32'd0 : s4 & reliable ? ePC : (s0?  int_vec : nPC);

	always@(posedge clk or posedge rst)
		if(rst)
			PC <= 32'b0;
		else if(cyc)
				if(~hold)
					PC <= PC_w;

	always@(posedge clk or posedge rst)
		if(rst) ePC <= 32'b0;
			else if(ld_epc)
				ePC <= (sel_epc | ~reliable) ? nPC : PC; //if ctrl instruction, fetch nPC; if branch not taken (s3), then keep going

endmodule

/*
RV32i ALU
Performs aritmetic, Logic and Shift operations needed by the RV32i CPU.
Also, it performs some instruction decoding needed for the ALU operations
*/
module rv32i_alu(
	input [31:0]    a, b,
	input [4:0]     shamt,
	output [31:0]   r,
	output          cf, zf, vf, sf,
	input [4:0]     opcode,
	input [2:0]     func3,
	input [6:0]     func7
);

	// decoded Instr
	wire I = (opcode == `OPCODE_Arith_I);
	wire R = (opcode == `OPCODE_Arith_R);
	wire IorR =  I || R;
	wire instr_logic = ((IorR==1'b1) && ((func3==`F3_XOR) || (func3==`F3_AND) || (func3==`F3_OR)));
	wire instr_shift = ((IorR==1'b1) && ((func3==`F3_SLL) || (func3==`F3_SRL) ));
	wire instr_slt = ((IorR==1'b1) && (func3==`F3_SLT));
	wire instr_sltu = ((IorR==1'b1) && (func3==`F3_SLTU));
	wire instr_store = (opcode == `OPCODE_Store);
	wire instr_load = (opcode == `OPCODE_Load);
	wire instr_add = R & (func3 == `F3_ADD) & (~func7[5]);
	wire instr_sub = R & (func3 == `F3_ADD) & (func7[5]);
	wire instr_addi = I & (func3 == `F3_ADD);
	wire instr_lui = (opcode == `OPCODE_LUI);
	wire instr_auipc = (opcode == `OPCODE_AUIPC);
	wire instr_branch = (opcode == `OPCODE_Branch);

	// Arith
	wire [31:0] add_sub, op_b;
	wire sub = (instr_branch | instr_sub | instr_slt | instr_sltu);

	// check!
	assign op_b = ({32{sub}} ^ b) ;
	assign {cf, add_sub} = a + op_b + {31'b0,sub};

	// Logic Operations
	wire[31:0] and_or_xor;
	assign and_or_xor = (IorR & (func3==`F3_AND)) ? (a & b) :
					 ((IorR & (func3==`F3_OR))) ? (a | b) : (a ^ b);

	// shifter
	wire[31:0] shift;
	wire[4:0] sha = (opcode==`OPCODE_Arith_I) ? shamt : b[4:0];
	//somehow type casting a two times is the only thing that works as expected with iverilog : CHECK AT SYNTHESIS
	assign shift = func3[2]? (func7[5]? $signed($signed(a) >>> sha) : (a >> sha) ):
						  (a << sha);

	// SLT/SLTU
	wire[31:0] slt;
	assign slt = (instr_slt) ? {31'b0,(sf != vf)} : {31'b0,(~cf)} ;

	// Alu output
	assign r =  (instr_slt | instr_sltu) ? slt :
				(instr_logic) ?     and_or_xor :
				(instr_shift) ?          shift : add_sub;

	// Flags
	assign zf = (add_sub == 32'b0);
	assign sf = (add_sub[31]);
	// check!
	assign vf = (a[31] ^ op_b[31] ^ add_sub[31] ^ cf);

endmodule

/*
Branch Unit
Decides whether the branch is taken or not based on ALU flags.
*/

module rv32i_branch_unit (
	input cf, zf, vf, sf,
	input[2:0] func3,
	output reg taken
);
	always @ * begin
		taken = 1'b0;
		(* full_case *)
		(* parallel_case *)
		case(func3)
			`BR_BEQ: taken = zf;          // BEQ
			`BR_BNE: taken = ~zf;         // BNE
			`BR_BLT: taken = (sf != vf);  // BLT
			`BR_BGE: taken = (sf == vf);  // BGE
			`BR_BLTU: taken = (~cf);      // BLTU
			`BR_BGEU: taken = (cf);       // BGEU
			default: taken = 1'b0;
		endcase
	end
endmodule

/*
Immediate Generator
*/
module rv32i_imm_gen (
input [31:0] inst,
output reg [31:0] imm
);

always @(*) begin

	case (inst[`IR_opcode])
		`OPCODE_Arith_I   : 	imm = { {21{inst[31]}}, inst[30:25], inst[24:21], inst[20] };
		`OPCODE_Store     :     imm = { {21{inst[31]}}, inst[30:25], inst[11:8], inst[7] };
		`OPCODE_LUI       :     imm = { inst[31], inst[30:20], inst[19:12], 12'b0 };
		`OPCODE_AUIPC     :     imm = { inst[31], inst[30:20], inst[19:12], 12'b0 };
		`OPCODE_JAL       : 	imm = { {12{inst[31]}}, inst[19:12], inst[20], inst[30:25], inst[24:21], 1'b0 };
		`OPCODE_JALR      : 	imm = { {21{inst[31]}}, inst[30:25], inst[24:21], inst[20] };
		`OPCODE_Branch    : 	imm = { {20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
		default           : 	imm = { {21{inst[31]}}, inst[30:25], inst[24:21], inst[20] }; // IMM_I
	endcase // case (imm_type)
end

endmodule

/*
Memory data extension and SELECTION
*/
//selects the appropriate w/hw/b within the received word
//and extends if needed
module rv32i_extender (
`ifdef _AHBL_
	input [1:0] bsel,
`endif
	input [31:0] di,
	output reg [31:0] do,
	input [1:0] sz,
	input type
);

`ifdef _AHBL_
//AHBL requirement  - shift first
reg [31:0] disi;
always @ (*) begin
    (* full_case *)
        (* parallel_case *)
        case (bsel)
            2'b00: disi = di;
            2'b01: disi = di >> 8;
            2'b10: disi = di >> 16;
            2'b11: disi = di >> 24;
        endcase
end
`else
wire [31:0] disi = di;
`endif

always @ * begin
	if(type) // zero
		case(sz)
			2'b00: do = {{24{1'b0}},disi[7:0]};
			2'b01: do = {{16{1'b0}},disi[15:0]};
			default: do = disi;
		endcase
	else
		case(sz)
			2'b00: do = {{24{disi[7]}},disi[7:0]};
			2'b01: do = {{16{disi[15]}},disi[15:0]};
			default: do = disi;
		endcase
end
endmodule


module rv32CU(
	input clk, rst,
	input[31:0] IR,

	input cf, zf, sf, vf,
	input tov,
	input gie, tie, eie, IRQ,
	output reg [31:0] IR1, IR2,
`ifdef _EN_EXT_
	output cu_ext_hold,
	output reg cu_ext_start,
	input ext_done,
`endif
	output cu_wfi_hold,
	input cu_brdy,
	output cu_hold,
	output reg cyc,
	output cu_rf_wr,
	output cu_r1_ld,
	output cu_r2_ld,
	output cu_r1_src,
	output cu_r2_src,
    output cu_memrd,
    output reg cu_rst_state,
	output[4:0] cu_rf_rs1, cu_rf_rs2, cu_rf_rd_1, cu_rf_rd_2, //why?
	output cu_pc_s0, cu_pc_s1, cu_pc_s2, cu_pc_s3, cu_pc_s4, cu_pc_reliable,
	output cu_alu_a_src, cu_alu_b_src,
	output cu_resmux_s0, cu_resmux_s1, cu_resmux_s2,
	output cu_csr_rd_s0, 
	output [1:0] cu_csr_rd_s1, cu_csr_rd_s2,
	output cu_int_ecall, cu_int_ebreak,
	output cu_ld_cycle, cu_ld_time, cu_ld_uie,
	output cu_c_cycle, cu_c_time, cu_c_uie,
	output cu_ld_epc, cu_sel_epc,
	output reg TMRIF,
	output intf,
	output cu_mwr,
	output cu_r_s,
	output cu_ret 
);

reg VF, ZF, SF, CF;

reg ISRMode;



wire  cu_br_inst,
cu_jal_inst,
cu_jalr_inst,
cu_alu_i_inst,
cu_alu_r_inst,
cu_load_inst,
cu_store_inst,
cu_lui_inst,
cu_auipc_inst,
cu_custom,
cu_system_inst;

wire  cu_br_inst_1,
cu_jal_inst_1,
cu_jalr_inst_1,
cu_alu_i_inst_1,
cu_alu_r_inst_1,
cu_load_inst_1,
cu_store_inst_1,
cu_lui_inst_1,
cu_auipc_inst_1,
cu_custom_1,
cu_system_inst_1;

wire  cu_br_inst_2,
cu_jal_inst_2,
cu_jalr_inst_2,
cu_alu_i_inst_2,
cu_alu_r_inst_2,
cu_load_inst_2,
cu_store_inst_2,
cu_lui_inst_2,
cu_auipc_inst_2,
cu_custom_2,
cu_system_inst_2;


`ifdef _AHBL_
assign cu_mwr =  (~cyc & (cu_store_inst_1));
`else
assign cu_mwr =  (cyc & (cu_store_inst_1));
`endif


assign cu_r_s = cu_custom_1;

wire cu_br_taken;

wire[2:0] func3_1 = IR1[`IR_funct3];

assign intf = ~ISRMode & ( (cu_pc_reliable&(cu_int_ecall|cu_int_ebreak)) | (IRQ & eie) | (TMRIF & tie)) & gie;

assign cu_sel_epc = cu_int_ecall | cu_int_ebreak;

always @ (posedge clk or posedge rst)
	if(rst) TMRIF <= 1'b0;
	else if(tov) TMRIF <= 1'b1;
	else if(cu_ld_time & cyc) TMRIF <= 1'b0;

always @ (posedge clk or posedge rst)
	if(rst) ISRMode <= 0;
	else if(intf & cyc) ISRMode <= 1;
	else if(cu_pc_s4) ISRMode <= 0;

always @ (posedge clk or posedge rst)
	if(rst) 
`ifdef _AHBL_
        //to start with baddr <=  alu_r so that PC_w can have its address phase
        cyc <= 1'b1;
`else
        cyc <= 1'b0;
`endif
	else if (~cu_hold) 
		cyc <= ~ cyc;

rv32dec IDEC0(
	.IR(IR),
	.cu_br_inst(cu_br_inst),
	.cu_jal_inst(cu_jal_inst),
	.cu_jalr_inst(cu_jalr_inst),
	.cu_alu_i_inst(cu_alu_i_inst),
	.cu_alu_r_inst(cu_alu_r_inst),
	.cu_load_inst(cu_load_inst),
	.cu_store_inst(cu_store_inst),
	.cu_lui_inst(cu_lui_inst),
	.cu_auipc_inst(cu_auipc_inst),
	.cu_custom_inst(cu_custom),
	.cu_system_inst(cu_system_inst)
);
wire cu_wfi_1;
rv32dec IDEC1(
	.IR(IR1),
	.cu_br_inst(cu_br_inst_1),
	.cu_jal_inst(cu_jal_inst_1),
	.cu_jalr_inst(cu_jalr_inst_1),
	.cu_alu_i_inst(cu_alu_i_inst_1),
	.cu_alu_r_inst(cu_alu_r_inst_1),
	.cu_load_inst(cu_load_inst_1),
	.cu_store_inst(cu_store_inst_1),
	.cu_lui_inst(cu_lui_inst_1),
	.cu_auipc_inst(cu_auipc_inst_1),
	.cu_custom_inst(cu_custom_1),
	.cu_system_inst(cu_system_inst_1)
);

rv32dec IDEC2(
	.IR(IR2),
	.cu_br_inst(cu_br_inst_2),
	.cu_jal_inst(cu_jal_inst_2),
	.cu_jalr_inst(cu_jalr_inst_2),
	.cu_alu_i_inst(cu_alu_i_inst_2),
	.cu_alu_r_inst(cu_alu_r_inst_2),
	.cu_load_inst(cu_load_inst_2),
	.cu_store_inst(cu_store_inst_2),
	.cu_lui_inst(cu_lui_inst_2),
	.cu_auipc_inst(cu_auipc_inst_2),
	.cu_custom_inst(cu_custom_2),
	.cu_system_inst(cu_system_inst_2)
);

rv32i_branch_unit BR(
	.cf(CF), .zf(ZF), .vf(VF), .sf(SF),
	.func3(func3_1),
	.taken(cu_br_taken)
	);

wire cu_j_inst_1 = cu_jal_inst_1 | cu_jalr_inst_1;
wire cu_ctrl_inst_1 = cu_br_inst_1 | cu_j_inst_1;


wire cu_alu_inst = cu_alu_r_inst | cu_alu_i_inst;
wire cu_alu_inst_1 = cu_alu_r_inst_1 | cu_alu_i_inst_1;
wire cu_alu_inst_2 = cu_alu_r_inst_2 | cu_alu_i_inst_2;

//MULTICYCLE???
always @ (posedge clk or posedge rst)
	if(rst)
		IR1 <= `INST_NOP;
	else if(cyc) begin
		//interrupts!
		if(~cu_pc_reliable | intf) IR1 <= `INST_NOP;
		else if(~cu_hold) IR1 <= IR;
	end

always @ (posedge clk or posedge rst)
	if(rst)
		IR2 <= `INST_NOP;
	else
		if(cyc) IR2 <= IR1;



always @ (posedge clk)
	if(~cyc & (cu_alu_inst_1 | cu_br_inst_1)) begin
		CF <= cf;
		ZF <= zf;
		VF <= vf;
		SF <= sf;
	end
`ifdef _EN_EXT_
always @ (posedge clk or posedge rst)
	if(rst)
	   	cu_ext_start <= 0;
	else if(cu_custom_1)
		cu_ext_start <= 1;
	else
		cu_ext_start <= 0;

`endif

assign cu_rf_rd_1 = IR1[`IR_rd];
assign cu_rf_rd_2 = IR2[`IR_rd];
assign cu_rf_rs1 = IR[`IR_rs1];
assign cu_rf_rs2 = IR[`IR_rs2];

assign cu_pc_s0 = intf;
assign cu_pc_s1 = cu_jalr_inst_1;
assign cu_pc_s2 = (cu_br_inst_1 & cu_br_taken) | (cu_jal_inst_1) ;
assign cu_pc_s3 = (cu_br_inst_1 & ~cu_br_taken) ;
assign cu_pc_s4 = (IR==`INST_URET);
assign cu_pc_reliable = ~(cu_pc_s1 | cu_pc_s2);

assign cu_ret = (IR2 != `INST_NOP & ~cyc); 

//
`ifdef _EN_EXT_
assign cu_ext_hold = cyc & ~ext_done & cu_custom_1;
`endif

assign cu_wfi_hold = (~intf) & (cu_wfi_1);

`ifdef _FPGA_

	`ifdef _EN_EXT_
	assign cu_hold = cu_ext_hold | cu_wfi_hold | cu_int_ecall_1 | ~cu_brdy;
	`else
	assign cu_hold = cu_wfi_hold | cu_int_ecall_1 | ~cu_brdy;
	`endif

`else

	`ifdef _EN_EXT_
	assign cu_hold = cu_ext_hold | cu_wfi_hold | ~cu_brdy;
	`else
	assign cu_hold = cu_wfi_hold | ~cu_brdy;
	`endif
`endif

	`ifdef _EN_EXT_
assign cu_rf_wr = (~cyc) &
			   (cu_rf_rd_2 != 5'b0) &
			   (cu_alu_inst_2 | cu_jal_inst_2 | cu_jalr_inst_2 | cu_lui_inst_2 | cu_load_inst_2 | cu_auipc_inst_2 | (cu_custom_2 & ext_done) | cu_system_inst_2);
`else
assign cu_rf_wr = (~cyc) &
			   (cu_rf_rd_2 != 5'b0) &
			   (cu_alu_inst_2 | cu_jal_inst_2 | cu_jalr_inst_2 | cu_lui_inst_2 | cu_load_inst_2 | cu_auipc_inst_2  | cu_system_inst_2);
`endif

assign cu_r1_ld = cyc & (cu_alu_inst | cu_br_inst | cu_load_inst | cu_store_inst | cu_jalr_inst | cu_custom | cu_system_inst);

assign cu_r1_src = (cu_rf_rd_1==cu_rf_rs1) & (cu_alu_inst_1 | cu_load_inst_1 | cu_lui_inst_1 | cu_auipc_inst_1 | cu_custom_1 | cu_system_inst_1) & (cu_rf_rs1 != 5'b0); // 1: RESMux, 0: RS1
assign cu_r2_ld = cyc & (cu_alu_inst | cu_br_inst | cu_store_inst | cu_custom);

assign cu_r2_src = (cu_rf_rd_1 == cu_rf_rs2) & (cu_alu_inst_1 | cu_load_inst_1 | cu_lui_inst_1 | cu_auipc_inst_1 | cu_custom_1 | cu_system_inst_1) & (cu_rf_rs2 != 5'b0);
assign cu_alu_a_src = cu_auipc_inst_1;
assign cu_alu_b_src = (cu_alu_i_inst_1 | cu_load_inst_1 | cu_store_inst_1 | cu_jalr_inst_1 | cu_auipc_inst_1 | cu_lui_inst_1);

//to request io (reads) correctly
//cu_memrd is the "request" signal; request data only when the addr is ready in the reg
assign cu_memrd = cu_load_inst_1 | cu_store_inst_1;



always@(posedge clk or posedge rst)
	if(rst)
		cu_rst_state <= 1'b1;
    else
        cu_rst_state <= 1'b0;


assign cu_resmux_s0 = cu_load_inst_1;
assign cu_resmux_s1 = cu_lui_inst_1;
assign cu_resmux_s2 = cu_j_inst_1;


assign cu_csr_rd_s0 = cu_system_inst_1;
assign cu_csr_rd_s1 = IR1[21:20]; //for time,instret,cycle
assign cu_csr_rd_s2 = {IR1[26], IR1[22]};

//optimize
assign cu_int_ecall = (IR==`INST_ECALL);
`ifdef _FPGA_
assign cu_int_ecall_1 = (IR1==`INST_ECALL); //for fpga
`endif
assign cu_int_ebreak = (IR==`INST_EBREAK);

assign cu_wfi_1 = (IR1==`INST_WFI);

assign cu_ld_cycle = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRW) & (IR1[`IR_csr]==`CSR_cycle);
assign cu_c_cycle = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRCI) & (IR1[`IR_csr]==`CSR_cycle);

assign cu_ld_time = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRW) & (IR1[`IR_csr]==`CSR_time);
assign cu_c_time = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRCI) & (IR1[`IR_csr]==`CSR_time);

assign cu_ld_uie = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRW) & (IR1[`IR_csr]==`CSR_uie);
assign cu_c_uie = cu_system_inst_1 & (IR1[`IR_funct3]==`SYS_CSRRCI) & (IR1[`IR_csr]==`CSR_uie);

assign cu_ld_epc = (intf & cyc & ~cu_hold);




endmodule


/*
The CPU
*/
module rv32_CPU_v2 (
	clk, rst,
	bdi, bdo, baddr, bsz, bwr,
	rfwr, rfrd, rfrs1, rfrs2, rfD, rfRS1, rfRS2,


	brdy,

	IRQ, IRQnum, IRQen
);
input clk, rst;
output[31:0] bdi, baddr;
output bwr;
output[1:0] bsz;
input[31:0] bdo;

output[4:0] rfrd, rfrs1, rfrs2;
output rfwr;
output[31:0] rfD;
input[31:0] rfRS1, rfRS2;


input brdy;

input IRQ;
input[3:0] IRQnum;
output[15:0] IRQen;

// only for simulation

wire cyc;


wire[31:0] ext_bdo;


wire cu_csr_rd_s0;
wire[1:0] cu_csr_rd_s1, cu_csr_rd_s2;
wire cu_int_ecall, cu_int_ebreak;
wire cu_ld_cycle, cu_ld_time, cu_ld_uie, cu_ret; 
wire cu_c_cycle, cu_c_time, cu_c_uie;

//Registers
reg[31:0] IR, R1, R2, PC1, I1; 
reg[31:0] R, RES;
wire[31:0] IR1, IR2;

// RF
wire[4:0] rf_rs1, rf_rs2;
wire[4:0] rf_rd;
wire[31:0] IMM;
wire[4:0] rf_rd_2;
//
wire[31:0] RS1, RS2;
wire rf_wr;
assign RS1 = (rf_rs1==5'b0) ? 32'b0 : rfRS1;
assign RS2 = (rf_rs2==5'b0) ? 32'b0 : rfRS2;
assign rfwr = rf_wr;
assign rfrs1 = rf_rs1;
assign rfrs2 = rf_rs2;
assign rfrd = rf_rd_2;
assign rfD = RES;


// PC
wire cu_pc_s0, cu_pc_s1, cu_pc_s2, cu_pc_s3, cu_pc_s4, cu_pc_reliable;
wire cu_ld_epc, cu_sel_epc;
wire[31:0] PC, PC_w;

// counters/Int Logic
wire[31:0] Cycle, Timer, Instret, UIE;
wire [3:0] UCause; 
wire tov;
wire gie, tie, eie;
wire intf, TMRIF;
wire[4:0] vec = IRQ ? {1'b1,IRQnum} : TMRIF ? 5'd12 : cu_int_ebreak ? 5'd8 : 5'd4;
wire [31:0]  cntr = cu_csr_rd_s1[1]? (cu_csr_rd_s2[1]? {28'd0, UCause} : Instret ): (cu_csr_rd_s2[0]? UIE : (cu_csr_rd_s1[0]? Timer : Cycle)); 
assign IRQen = UIE[18:3];

wire[4:0] rf_rs_1;
rv32Counters CNTR (
	.clk(clk),
	.cyc(cyc),
	.rst(rst),
	.Cycle(Cycle),
	.Timer(Timer),
	.Instret(Instret),
	.UIE(UIE),
	.UCause(UCause),
	.wdata(R1),
	.uimm(rf_rs_1),
	.IRQnum(IRQnum),
	.ld_cycle(cu_ld_cycle), .ld_timer(cu_ld_time), .ld_uie(cu_ld_uie), .inc_ret(cu_ret), 
	.c_cycle(cu_c_cycle), .c_timer(cu_c_time), .c_uie(cu_c_uie),
	.gie(gie), .tie(tie), .eie(eie),
	.tif(tov)
	);


// +---------+
// | Stage 0 |
// +---------+

assign  rf_rs1 = IR[`IR_rs1];
assign  rf_rs2 = IR[`IR_rs2];
assign  rf_rd = IR[`IR_rd];
//wire[31:0] IMM;

rv32i_imm_gen IMMGen(
 	.inst(IR),
	.imm(IMM)
	);


wire [31:0] d16ic_32;
wire compressed;
D16Inst d16ic (.Inst(bdo[15:0]), .Instout(d16ic_32), .Is16inst(compressed));

wire hold;
always @ (posedge clk or posedge rst)
	if(rst)
		IR <= `INST_NOP;
	else
		if(~cyc)
            IR <= hold? `INST_NOP : (compressed? d16ic_32 : bdo);

always @ (posedge clk or posedge rst)
	if (rst)
		I1 <= 32'b0;
	else if(cyc) 
		if(~hold) I1 <= IMM;

always @ (posedge clk or posedge rst)
	if(rst)
	   	PC1 <= 32'b0;
	else if(cyc & ~hold)
            PC1 <= PC;

wire cu_r1_ld, cu_r2_ld;
wire cu_r1_src, cu_r2_src;

wire[31:0] RESMux;
always @ (posedge clk or posedge rst)
	if (rst)
		R1 <= 32'b0;
	else if(cu_r1_ld & ~hold)
		if(cu_r1_src)
			R1 <= RESMux;
		else
			R1 <= RS1;

always @ (posedge clk or posedge rst)
	if (rst)
		R2 <= 32'b0;
	else if(cu_r2_ld & ~hold)
		if(cu_r2_src)
			R2 <= RESMux;
		else
			R2 <= RS2;

// +---------+
// | Stage 1 |
// +---------+
wire[31:0] alu_r, alu_a, alu_b;
wire alu_cf, alu_zf, alu_vf, alu_sf;
wire[4:0] rf_rd_1 = IR1[`IR_rd];
assign rf_rs_1 = IR1[`IR_rs1];


wire cu_alu_a_src, cu_alu_b_src;

assign alu_a = (cu_alu_a_src) ? PC1 : R1 ; // to support auipc
assign alu_b = (cu_alu_b_src) ? I1 : R2;

//ALU
rv32i_alu ALU (
	.a(alu_a), .b(alu_b),
	.shamt(IR1[`IR_shamt]),
	.r(alu_r),
	.cf(alu_cf), .zf(alu_zf), .vf(alu_vf), .sf(alu_sf),
	.opcode(IR1[`IR_opcode]),
	.func3(IR1[`IR_funct3]),
	.func7(IR1[`IR_funct7])
	);

// extensions
`ifdef _EN_EXT_
	wire[31:0] ext_out;
	wire ext_hold;
	wire ext_start;
	wire ext_done;

	wire cu_r_s;

	assign extA = R1;
	assign extB = R2;
	assign extFunc3 = IR1[`IR_funct3];
	assign ext_out = extR;
	assign extStart = ext_start;
	assign ext_done = extDone;

	always @ (posedge clk or posedge rst)
		if(rst)
			R <= 32'b0;
		else if(~cyc)
/*
			if(cu_r_s)
				R <= ext_out;
			else
*/
				R <= alu_r;   // Is it really needed?
	// The ALU inputs are stable
	// till the end of the cycle
`else
	always @ (posedge clk or posedge rst)
		if(rst)
			R <= 32'b0;
		else if(~cyc)
			R <= alu_r;
`endif

wire cu_resmux_s0, cu_resmux_s1, cu_resmux_s2;

//wire[1:0] res_sel = cu_resmux_s0 ? 2'd0 : cu_resmux_s1 ? 2'd1 : cu_resmux_s2 ? 2'd2 : 2'd3;
assign  RESMux =  /*(res_sel == 2'd0) ? ext_bdo :
				   (res_sel == 2'd1) ? I1 :
				   (res_sel == 2'd2) ? PC : R;
										 */
				   (cu_resmux_s0) ? ext_bdo :
				   (cu_resmux_s1) ? I1 :
				   (cu_resmux_s2) ? PC :
				   (cu_csr_rd_s0) ? cntr : R;
//                   		   (cu_r_s)       ? ext_out : R; 


always @ (posedge clk or posedge rst)
	if(rst)
		RES <= 32'b0;
	else begin
		if(cyc) RES <= RESMux;
	end

wire[2:0] func3_1 = IR1[`IR_funct3];


// memory
wire cu_mwr, cu_memrd;
assign bwr = cu_mwr;
//ADDR_SELNONE: special number that selects none of the devices


`ifdef _AHBL_

wire compressed_n = IR[0]&IR[1];
assign baddr =  cyc? PC_w : (cu_memrd? alu_r : `ADDR_SELNONE);
assign bsz = (cyc) ? 2'b10 : func3_1[1:0];

//issues that need to be addressed
`ifdef _XSPRAM_
wire [1:0] bsel = baddr[1:0];
`else
wire [1:0] bsel = R[1:0];
`endif

assign bdi = (bsel == 2'b01)? {R2[23:0],  8'd0}:
			 (bsel == 2'b10)? {R2[15:0], 16'd0}:			  	
			 (bsel == 2'b11)? {R2[7:0],  24'd0}: R2;			  	
`else

wire compressed_n = IR1[0]&IR1[1];
assign baddr =  cyc ? (cu_memrd? R : `ADDR_SELNONE) : PC;
assign bsz = (cyc) ? func3_1[1:0] : 2'b10;
assign bdi = R2;

`endif

//assign bdi = R2;




//R contains the address at this point
rv32i_extender EXT (
`ifdef _AHBL_
	.bsel(R[1:0]),
`endif
	.di(bdo), .do(ext_bdo), .sz(func3_1[1:0]), .type(func3_1[2]) );

// +---------+
// | Stage 2 |
// +---------+
assign rf_rd_2 = IR2[`IR_rd];

// Control Unit
wire wfi_hold;
wire cu_rst_state;

rv32PCUnit PCU(
	.clk(clk), .rst(rst),
	.hold(hold),.cyc(cyc),
	.s0(cu_pc_s0), .s1(cu_pc_s1), .s2(cu_pc_s2), .s3(cu_pc_s3), .s4(cu_pc_s4), .reliable(cu_pc_reliable),
	.PC(PC),
    .PC_w(PC_w),
	.compressed(~(IR[0]&IR[1])),
    .cu_rst_state(cu_rst_state),
	.PC1(PC1), .I1(I1), .alu_r(alu_r),
	.vec(vec),
	.ld_epc(cu_ld_epc),
	.sel_epc(cu_sel_epc)
);


wire cu_r_s;
	rv32CU CTRL(
		.clk(clk), .rst(rst),
		.IR(IR),
`ifdef EN_EXT
		.ext_done(ext_done),
		.cu_ext_hold(ext_hold),
		.cu_ext_start(ext_start),
`endif

		.cf(alu_cf), .zf(alu_zf), .sf(alu_sf), .vf(alu_vf),
		.tov(tov),
		.gie(gie), .tie(tie), .eie(eie), .IRQ(IRQ),
		.IR1(IR1), .IR2(IR2),

		.cu_wfi_hold(wfi_hold),
		.cu_brdy(brdy),
		.cu_hold(hold),
		.cyc(cyc),
		.cu_rf_wr(rf_wr),
		.cu_r1_ld(cu_r1_ld),
		.cu_r2_ld(cu_r2_ld),
		.cu_r1_src(cu_r1_src),
		.cu_r2_src(cu_r2_src),

		//to externally CS chips correctly
		.cu_memrd(cu_memrd),

        .cu_rst_state(cu_rst_state),
		
		.cu_pc_s0(cu_pc_s0),.cu_pc_s1(cu_pc_s1), .cu_pc_s2(cu_pc_s2), .cu_pc_s3(cu_pc_s3),.cu_pc_s4(cu_pc_s4),.cu_pc_reliable(cu_pc_reliable),
		.cu_alu_a_src(cu_alu_a_src), .cu_alu_b_src(cu_alu_b_src),
		.cu_resmux_s0(cu_resmux_s0), .cu_resmux_s1(cu_resmux_s1), .cu_resmux_s2(cu_resmux_s2),
		.cu_csr_rd_s0(cu_csr_rd_s0), .cu_csr_rd_s1(cu_csr_rd_s1), .cu_csr_rd_s2(cu_csr_rd_s2),
		.cu_int_ecall(cu_int_ecall), .cu_int_ebreak(cu_int_ebreak),
		.cu_ld_cycle(cu_ld_cycle), .cu_ld_time(cu_ld_time), .cu_ld_uie(cu_ld_uie),
		.cu_c_cycle(cu_c_cycle), .cu_c_time(cu_c_time), .cu_c_uie(cu_c_uie),
		.cu_ld_epc(cu_ld_epc), .cu_sel_epc(cu_sel_epc),
		.TMRIF(TMRIF),
		.intf(intf),
		.cu_mwr(cu_mwr),
		.cu_r_s(cu_r_s),
		.cu_ret(cu_ret) 
	);

endmodule



module D16Inst(Inst,Instout, Is16inst);
input[15:0] Inst;                           //the least significatn 16 bit of the 32-bit instruction;
output reg[31:0] Instout;                   // an encoded normal RV32 instruction ready for decoding;
output Is16inst;                            //if true: PC + 2 and parse the Instout to the RV32 decoder, else PC + 4 and use the fetched instruction; 

//deciding whether the fetched instruction is compressed or not
assign Is16inst = !Inst[1] | !Inst[0];      


//signals used for decoding the 16bit instruction: case and if statements
wire [1:0] op = Inst[1:0];
wire [2:0] fun3 = Inst[15:13];
wire [1:0] fun2 = Inst[11:10];
wire [1:0] fun = Inst[6:5];
wire [4:0] Brs1 = Inst[11:7];
wire [4:0] Brs2 = Inst[6:2];

//Decoding and encoding process
always @(Inst) begin
    Instout = 32'b0;
    case(op)
        2'b00:begin                 //C0
            case(fun3)
                3'b000:begin             //C.ADDI4SPN
                   //addi rd0, x2, nzuimm[9:2].
                    Instout = {2'b00,Inst[12:11],Inst[10:7],Inst[5],Inst[6],2'b00,5'b00010,3'b000,2'b01,Inst[4:2],7'b0010001};
                end
                
                3'b010:begin             //C.LW
                   //lw rd',offset[6:2](rs1').
                    Instout = {5'd0,Inst[5],Inst[12:10],Inst[6],2'b00,2'b01,Inst[9:7],3'b010,2'b01,Inst[4:2],7'b0000001};
                end
                
                3'b110:begin         //C.SW
                //sw rs2',offset[6:2](rs1').
                    Instout = {5'd0,Inst[5],Inst[12],2'b01,Inst[4:2],2'b01,Inst[9:7],3'b010,Inst[11:10],Inst[6],2'b00,7'b0100001};
                end
                
                	default:
	Instout = 32'b0;
            endcase
        end
        
        2'b01:begin                 //C1
            case(fun3)
            
                3'b000:begin            //C.ADDI
                //addi rd, rd, nzimm[5:0].
                    Instout = {{6{Inst[12]}},Inst[12],Inst[6:2],Inst[11:7],3'b000,Inst[11:7],7'b0010001};
                end
                
                3'b001:begin         //C.JAL
                //jal x1, offset[11:1].
                    Instout = {Inst[12],Inst[8],Inst[10:9],Inst[6],Inst[7],Inst[2],Inst[11],Inst[5:3],Inst[12],{8{Inst[12]}},5'b00001,7'b1101101};
                end
                
                
                3'b010:begin            //C.LI
                //addi rd, x0, imm[5:0].
                    Instout = {{6{Inst[12]}},Inst[12],Inst[6:2],5'b00000,3'b000,Inst[11:7],7'b0010001};
                end
                
                3'b011:begin            //C.LUI,C.ADDI16SP
                    case(Brs1)
                    5'b00010: begin     //C.ADDI16SP
                    //addi x2, x2, nzimm[9:4].
                        Instout = {{3{Inst[12]}},Inst[12],Inst[6],Inst[5],Inst[4:3],Inst[2],3'd0,Brs1,3'b000,Brs1,7'b0010001};
                    end
                    default: begin      //C.LUI
                    //lui rd, nzuimm[17:12].
                        Instout = {{14{Inst[12]}},Inst[12],Inst[6:2],Brs1,7'b0110101};
                    end
                    endcase
                end
                
                
                3'b100:begin         //C.SRLI, C.SRAI, C.ANDI
                    case(fun2)
                    2'b00:begin     //C.SRLI
                    //srli rd', rd', shamt[5:0]
                        Instout = {7'b0000000,Inst[6:2],2'b01,Inst[9:7],3'b101,2'b01,Inst[9:7],7'b0010001};
                    end  
                    2'b01:begin     //C.SRAI
                    //srai rd', rd', shamt[5:0],
                        Instout = {7'b0100000,Inst[6:2],2'b01,Inst[9:7],3'b101,2'b01,Inst[9:7],7'b0010001};
                    end
                    2'b10:begin     //C.ANDI
                    //andi rd', rd', imm[5:0].
                        Instout = {{6{Inst[12]}},Inst[12],Inst[6:2],2'b01,Inst[9:7],3'b111,2'b01,Inst[9:7],7'b0010001};
                    end
                    2'b11:
                        if(!Inst[12])begin
                            case(fun)
                                2'b00: begin    //C.AND
                                //and rd', rd', rs2'.
                                    Instout = {7'b0000000,2'b01, Inst[4:2],2'b01,Inst[9:7],3'b111,2'b01,Inst[9:7],7'b0110001};
                                end
                                2'b01: begin    //C.OR
                                //or rd', rd', rs2'.
                                    Instout = {7'b0000000,2'b01, Inst[4:2],2'b01,Inst[9:7],3'b110,2'b01,Inst[9:7],7'b0110001};
                                end
                                2'b10: begin    //C.XOR
                                //xor rd', rd', rs2'.
                                    Instout = {7'b0000000,2'b01, Inst[4:2],2'b01,Inst[9:7],3'b100,2'b01,Inst[9:7],7'b0110001};
                                end
                                2'b11: begin    //C.SUB
                                //sub rd', rd', rs2'.
                                    Instout = {7'b0100000,2'b01, Inst[4:2],2'b01,Inst[9:7],3'b000,2'b01,Inst[9:7],7'b0110001};
                                end
                           
                            endcase
                        end
                    endcase
                end
                
                
                3'b101:begin         //C.J
                //jal x0,offset[11:1].
                    Instout = {Inst[12],Inst[8],Inst[10:9],Inst[6],Inst[7],Inst[2],Inst[11],Inst[5:3],Inst[12],{8{Inst[12]}},5'b00000,7'b1101101};
                end
                
                3'b110:begin         //C.BEQZ
                //beq rs1', x0, offset[8:1].
                    Instout = {Inst[12],{2{Inst[12]}},Inst[12],Inst[6:5],Inst[2],5'b00000,2'b01,Inst[9:7],3'b000,Inst[11:10],Inst[4:3],Inst[12],7'b1100001};
                end
                
                3'b111:begin         //C.BNEZ
                //bne rs1', x0, offset[8:1].
                    Instout = {Inst[12],{2{Inst[12]}},Inst[12],Inst[6:5],Inst[2],5'b00000,2'b01,Inst[9:7],3'b001,Inst[11:10],Inst[4:3],Inst[12],7'b1100001};
                end
            endcase
        end
        
        2'b10:begin                 //C2
            case(fun3)
                 
                3'b000:begin            //C.SLLI
                //slli rd, rd, shamt[5:0],.
                    Instout = {7'b0000000,Inst[6:2],Inst[11:7],3'b001,Inst[11:7],7'b0010001};
                end
            
                
                
                3'b010:begin            //C.LWSP
                //lw rd,offset[7:2](x2).
                    Instout = {4'd0,Inst[3:2],Inst[12],Inst[6:4],2'b00,5'b00010,3'b010,Inst[11:7],7'b0000001};
                end
            
                3'b100:begin            //C.JR, C.JALR, C.MV, C.ADD, C.EBREAK
                    case(Inst[12])
                        1'b0: begin
                            if(!Brs2) begin             //C.JR
                            //jalr x0, rs1, 0.
                                Instout = {12'd0,Brs1,3'b000,5'b00000,7'b1100101};
                            end
                            else begin                  //C.MV    
                            //add rd, x0, rs2.
                                Instout = {7'b0000000,Brs2,5'b00000,3'b000,Brs1,7'b0110001};
                            end
                        end
                        1'b1: begin
                            if(!Brs2&&!Brs1) begin      //C.EBREAK
                                //EBREAK
                                Instout = {12'd1,5'd0,3'b000,5'd0,7'b1110001};
                            end
                            else if(!Brs2) begin        //C.JALR    
                            //jalr x1, rs1, 0.
                                Instout = {12'd0,Brs1,3'b000,5'b00001,7'b1100101};
                            end
                            else begin                  //C.ADD   
                            //add rd, rd, rs2.
                                Instout = {7'b0000000,Brs2,Brs1,3'b000,Brs1,7'b0110001};
                            end
                            
                        end
                    endcase
                end
                
                3'b110:begin         //C.SWSP
                //sw rs2,offset[7:2](x2).
                    Instout = {4'd0,Inst[8:7],Inst[12],Inst[6:2],5'b00010,3'b010,Inst[11:9],2'b00,7'b0100001};
                end
	default:
	Instout = 32'b0;
            endcase
        end
	default:
	Instout = 32'b0;
    endcase
end
endmodule
