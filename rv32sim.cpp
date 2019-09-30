#include <iostream>
#include <iomanip>
#include <fstream>
#include <string>
#include <cstdlib>

using namespace std;

#define MMAP_PRINT 0x80000000
#define C_EXT


const int regCount = 32;
int regs[regCount] = {0};
unsigned int pc = 0x0;
const unsigned int RAM = 64 * 1024; // only 8KB of memory located at address 0
char memory[RAM];
bool terminated = false;

unsigned int decompress(unsigned int, bool&);


void emitError(string);


unsigned int readInstruction();


void printPrefix(unsigned int, unsigned int);

unsigned int immediateI(unsigned int);
unsigned int immediateS(unsigned int);
unsigned int immediateB(unsigned int);
unsigned int immediateU(unsigned int);
unsigned int immediateJ(unsigned int);

void setZero();

void instDecExec(unsigned int, bool);


void printInstU(string, unsigned int, unsigned int);
void LUI(unsigned int, unsigned int);
void AUIPC(unsigned int, unsigned int);

void printInstUJ(string, unsigned int, unsigned int);
void JAL(unsigned int, unsigned int, unsigned int);

void printInstB(string, unsigned int, unsigned int, unsigned int);
void JALR(unsigned int, unsigned int, unsigned int);
void B_Inst(unsigned int, unsigned int, unsigned int, unsigned int, unsigned int);
void BEQ(unsigned int, unsigned int, unsigned int);
void BNE(unsigned int, unsigned int, unsigned int);
void BLT(unsigned int, unsigned int, unsigned int);
void BGE(unsigned int, unsigned int, unsigned int);
void BLTU(unsigned int, unsigned int, unsigned int);
void BGEU(unsigned int, unsigned int, unsigned int);

void printInstL_S(string, unsigned int, unsigned int, unsigned int);
void L_Inst(unsigned int, unsigned int, unsigned int, unsigned int);
void LB(unsigned int, unsigned int, unsigned int, unsigned int);
void LH(unsigned int, unsigned int, unsigned int, unsigned int);
void LW(unsigned int, unsigned int, unsigned int, unsigned int);
void LBU(unsigned int, unsigned int, unsigned int, unsigned int);
void LHU(unsigned int, unsigned int, unsigned int, unsigned int);
void S_Inst(unsigned int, unsigned int, unsigned int, unsigned int);
void SB(unsigned int, unsigned int, unsigned int, unsigned int);
void SH(unsigned int, unsigned int, unsigned int, unsigned int);
void SW(unsigned int, unsigned int, unsigned int, unsigned int);

void printInstI(string, unsigned int, unsigned int, unsigned int);
void I_Inst(unsigned int, unsigned int, unsigned int, unsigned int);
void ADDI(unsigned int, unsigned int, unsigned int);
void SLLI(unsigned int, unsigned int, unsigned int);
void SLTI(unsigned int, unsigned int, unsigned int);
void SLTIU(unsigned int, unsigned int, unsigned int);
void XORI(unsigned int, unsigned int, unsigned int);
void ORI(unsigned int, unsigned int, unsigned int);
void ANDI(unsigned int, unsigned int, unsigned int);
void SRLI(unsigned int, unsigned int, unsigned int);
void SRAI(unsigned int, unsigned int, unsigned int);

void printInstR(string, unsigned int, unsigned int, unsigned int);
void R_Inst(unsigned int, unsigned int, unsigned int, unsigned int, unsigned int);
void ADD(unsigned int, unsigned int, unsigned int);
void SUB(unsigned int, unsigned int, unsigned int);
void SLL(unsigned int, unsigned int, unsigned int);
void SLT(unsigned int, unsigned int, unsigned int);
void SLTU(unsigned int, unsigned int, unsigned int);
void XOR(unsigned int, unsigned int, unsigned int);
void SRL(unsigned int, unsigned int, unsigned int);
void SRA(unsigned int, unsigned int, unsigned int);
void OR(unsigned int, unsigned int, unsigned int);
void AND(unsigned int, unsigned int, unsigned int);

void Ext_Inst(unsigned int, unsigned int, unsigned int, unsigned int);
void MUL(unsigned int, unsigned int, unsigned int);

void printInstE();
void ECALL();
void printInteger();
void printString();
void readInteger();
void terminateExecution();



int main(int argc, char* argv[]) {
	unsigned int instWord = 0;
	ifstream inFile;
	bool is16 = false;
	if(argc < 1){
		emitError("Use: rv32i_sim <machine_code_file_name>");
	}

	inFile.open(argv[1], ios::in | ios::binary | ios::ate);

	if(inFile.is_open()) {
		long long fsize = inFile.tellg();
		inFile.seekg (0, inFile.beg);

		if(!inFile.read((char *)memory, fsize)){
			emitError("Cannot read from input file");
		}

		while(!terminated) {
			instWord = readInstruction();  // read next instruction
#ifdef C_EXT
			instWord = decompress(instWord, is16);
			if (is16)
				pc += 2;
			else
				pc += 4;    // increment pc by 4
			instDecExec(instWord, is16);
#else
			pc += 4;    // increment pc by 4
			instDecExec(instWord, false);
#endif
			regs[0] = 0;
		}

		// check if terminated correcctly
		if(!terminated){
			cerr << "Illegal memory access" << endl;
		}

		// dump the registers
		for(int i = 0; i < regCount; i++) {
			cout << "x" << dec << i << ": \t";
			cout << "0x" << hex << std::setfill('0') << std::setw(regCount / 4) << regs[i] << '\t' << dec << regs[i] << endl;
		}

		exit(0);

	} else {
		emitError("Cannot access input file");
	}
}

// dump the registers
void dumpRegs(){
	for(int i = 0; i < regCount; i++) {
		cout << "x" << dec << i << ": \t";
		cout << "0x" << hex << std::setfill('0') << std::setw(regCount / 4) << regs[i] << '\t' << dec << regs[i] << endl;
	}
}

void emitError(string error_message)
{
	cerr << error_message << endl;;
	exit(0);
}


unsigned int readInstruction()
{
	return (  (unsigned char)memory[pc]           |
			(((unsigned char)memory[pc+1]) << 8)  |
			(((unsigned char)memory[pc+2]) << 16) |
			(((unsigned char)memory[pc+3]) << 24) );
}

void printPrefix(unsigned int instA, unsigned int instW)
{
	cout << "0x" << hex << std::setfill('0') << std::setw(8) << instA << "\t";
	cout << "0x" << std::setw(8) << instW;
}

unsigned int immediateI(unsigned int instWord)
{
	return ( ( (instWord >> 20) & 0x7FF ) | ( (instWord >> 31) ? 0xFFFFF800 : 0x0 ) );
}
unsigned int immediateB(unsigned int instWord)
{
	unsigned int imm = 0;
	unsigned int a, b, c, sign;

	a = (instWord >> 7) & 0x1;
	a = a << 11;

	b = (instWord >> 25) & 0x3F;
	b = b << 5;

	c = (instWord >> 8) & 0xF;
	c = c << 1;

	sign = instWord >> 31;

	imm = imm | a | b | c | (sign ? 0xFFFFF000 : 0x0) ;

	return (imm);

}
unsigned int immediateJ(unsigned int instWord)
{
	unsigned int imm = 0;
	unsigned int a, b, c, d, sign;

	a = (instWord >> 12) & 0x000000FF;
	a = a << 12;

	b = (instWord >> 20) & 0x00000001;
	b = b << 11;

	c = (instWord >> 21) & 0x000003FF;
	c = c << 1;

	d = (instWord >> 31) & 0x00000001;
	d = d << 20;

	sign = instWord >> 31;

	imm = a | b | c | d | (sign ? 0xFFF00000 : 0x0) ;

	return (imm);

}
unsigned int immediateS(unsigned int instWord)
{
	return ( ((instWord >> 7) & 0x1F) | ((instWord >> 20) & 0xFE0) | (((instWord >> 31) ? 0xFFFFF800 : 0x0)) );
}
unsigned int immediateU(unsigned int instWord)
{
	return (instWord & 0xFFFFF000);
}

void setZero()
{
	regs[0] = 0;
}

void instDecExec(unsigned int instWord, bool is16)
{
	unsigned int rd, rs1, rs2, funct3, funct7, opcode;
	unsigned int I_imm, B_imm, J_imm, S_imm, U_imm;

	unsigned int instPC = pc - (is16? 2: 4);

	opcode = instWord & 0x0000007F;

	rd = (instWord >> 7) & 0x0000001F;
	rs1 = (instWord >> 15) & 0x0000001F;
	rs2 = (instWord >> 20) & 0x0000001F;

	funct3 = (instWord >> 12) & 0x00000007;
	funct7 = (instWord >> 25) & 0x0000007F;

	I_imm = immediateI(instWord);
	B_imm = immediateB(instWord);
	J_imm = immediateJ(instWord);
	S_imm = immediateS(instWord);
	U_imm = immediateU(instWord);

	printPrefix(instPC, instWord);

	switch(opcode)
	{
		case 0x47:
			Ext_Inst(rd, rs1, rs2, funct3);
			break;
		case 0x37:  // Load Upper Immediate
			LUI(rd, U_imm);
			break;
		case 0x17:  // Add Unsigned Immediate Program Counter
			AUIPC(rd, U_imm);
			break;
		case 0x6F:  // Jump And Link
		JAL(rd, J_imm, instPC);
			break;
		case 0x67:  // Jump And Link Return
			JALR(rd, rs1, I_imm);
			//if((instWord&0xffff)==0x00008067) dumpRegs();
			break;
		case 0x63:  // Branch Instructions
		B_Inst(rs1, rs2, B_imm, funct3, instPC);
			break;
		case 0x03:  // Load Instructions
			L_Inst(rd, rs1, I_imm, funct3);
			break;
		case 0x23:  // Store Insturctions
			S_Inst(rs2, rs1, S_imm, funct3);
			break;
		case 0x13:  // Immediate Instructions
			I_Inst(rd, rs1, I_imm, funct3);
			break;
		case 0x33:  // Register Instructions
			R_Inst(rd, rs1, rs2, funct3, funct7);
			break;
		case 0x73:  // Enviroment Calls
			ECALL();
			break;
		default:
			cout << "\tUnknown Instruction Type" << endl;;
	}
	if (rd && opcode != 0x73 && opcode != 0x23 && opcode != 0x63)
		cout << "RF[" << rd << "]=" << hex << setw(8) << regs[rd] << dec << endl;
	//cout << "RF[" << rd << "]=" << hex << setw(8) << regs[rd] << dec << endl;

	setZero();
}


void printInstU(string inst, unsigned int rd, unsigned int imm)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << rd << ", ";
	cout << int(imm) << endl;
}
void LUI(unsigned int rd, unsigned int U_imm)
{
	printInstU("LUI", rd, (U_imm >> 12) & 0xFFFFF);

	regs[rd] =  U_imm;
}
void AUIPC(unsigned int rd, unsigned int U_imm)
{
	printInstU("AUIPC", rd, (U_imm >> 12) & 0xFFFFF);

	regs[rd] = (pc - 4) + U_imm;

	cout << "x" << rd << ": " << regs[rd] << "\n";
}

void printInstUJ(string inst, unsigned int rd, unsigned int target_address)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << rd << ", ";
	cout << "0x" << hex << std::setfill('0') << std::setw(8) << target_address << endl;
}
void JAL(unsigned int rd, unsigned int J_imm, unsigned instPC)
{
	unsigned address = J_imm + instPC;

	printInstUJ("JAL", rd, address);

	regs[rd] = pc;
	pc =  address;
}

void printInstB(string inst, unsigned int rs1, unsigned int rs2, unsigned int target_address)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << rs1 << ", x" << rs2 << ", ";
	cout << "0x" << hex << std::setfill('0') << std::setw(8) << target_address << endl;
}
void JALR(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	unsigned int address = (I_imm + regs[rs1]) & 0xFFFFFFFE;

	printInstB("JALR", rd, rs1, I_imm);

	regs[rd] = pc;
	pc = address;

	//dumpRegs();
	//cout << "PC=" << pc << endl;
}
void B_Inst(unsigned int rs1, unsigned int rs2, unsigned int B_imm, unsigned int funct3, unsigned int instPC)
{
	unsigned int address = B_imm + instPC;
	switch(funct3)
	{
		case 0x0:
			BEQ(rs1, rs2, address);
			break;
		case 0x1:
			BNE(rs1, rs2, address);
			break;
		case 0x4:
			BLT(rs1, rs2, address);
			break;
		case 0x5:
			BGE(rs1, rs2, address);
			break;
		case 0x6:
			BLTU(rs1, rs2, address);
			break;
		case 0x7:
			BGEU(rs1, rs2, address);
			break;
		default:
			cout << "\tInvalid Branch Instruction" << endl;
	}
}
void BEQ(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BEQ", rs1, rs2, address);

	if (regs[rs1] == regs[rs2])
		pc = address;
}
void BNE(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BNE", rs1, rs2, address);

	if (regs[rs1] != regs[rs2])
		pc = address;
}
void BLT(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BLT", rs1, rs2, address);

	if (regs[rs1] < regs[rs2])
		pc = address;
}
void BGE(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BGE", rs1, rs2, address);

	if (regs[rs1] >= regs[rs2])
		pc = address;
}
void BLTU(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BLTU", rs1, rs2, address);

	if ((unsigned int)(regs[rs1]) < (unsigned int)(regs[rs2]))
		pc = address;
}
void BGEU(unsigned int rs1, unsigned int rs2, unsigned int address)
{
	printInstB("BGEU", rs1, rs2, address);

	if ((unsigned int)regs[rs1] >= (unsigned int)regs[rs2])
		pc = address;
}

void printInstL_S(string inst, unsigned int first, unsigned int second, unsigned int offset)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << first << ", " << int(offset) << "(x" << second << ")" << " (addr = " << int(offset+regs[second]) << ")" << endl;
	//if(inst[0]=='L') cout << "RF[" << first << "]=" << regs[first] << endl;
}
void L_Inst(unsigned int rd, unsigned int rs1, unsigned int I_imm, unsigned int funct3)
{
	unsigned int address = regs[rs1] + I_imm;
	unsigned int offset = I_imm;

	switch (funct3)
	{
		case 0:
			LB(rd, rs1, offset, address);
			break;
		case 1:
			LH(rd, rs1, offset, address);
			break;
		case 2:
			LW(rd, rs1, offset, address);
			break;
		case 4:
			LBU(rd, rs1, offset, address);
			break;
		case 5:
			LHU(rd, rs1, offset, address);
			break;
		default:
			cout << "\tInvalid Load Instruction" << endl;
	}
}
void LB(unsigned int rd, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("LB", rd, rs1, offset);

	regs[rd] = memory[address];
}
void LH(unsigned int rd, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("LH", rd, rs1, offset);

	regs[rd] = memory[address+1];
	regs[rd] = regs[rd] << 8;
	regs[rd] = regs[rd] | (unsigned char)memory[address];
}
void LW(unsigned int rd, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("LW", rd, rs1, offset);
	if(address%4) cout << "Memory address not divisible by 4 -- " << address << endl;


	regs[rd] = (unsigned char)memory[address+3];
	regs[rd] = regs[rd] << 8;
	regs[rd] = regs[rd] | (unsigned char)memory[address+2];
	regs[rd] = regs[rd] << 8;
	regs[rd] = regs[rd] | (unsigned char)memory[address+1];
	regs[rd] = regs[rd] << 8;
	regs[rd] = regs[rd] | (unsigned char)memory[address];

	//cout << "reading from: " << address << " " << regs[rd] << endl;
}
void LBU(unsigned int rd, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("LBU", rd, rs1, offset);

	regs[rd] = (unsigned char)memory[address];
}
void LHU(unsigned int rd, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("LHU", rd, rs1, offset);

	regs[rd] = (unsigned char)memory[address+1];
	regs[rd] = regs[rd] << 8;
	regs[rd] = regs[rd] | (unsigned char)memory[address];
}
void S_Inst(unsigned int rs2, unsigned int rs1, unsigned int S_imm, unsigned int funct3)
{
	unsigned int address = regs[rs1] + S_imm;
	unsigned int offset = S_imm & 0xFFF;

	switch (funct3)
	{
		case 0:
			SB(rs2, rs1, offset, address);
			break;
		case 1:
			SH(rs2, rs1, offset, address);
			break;
		case 2:
			SW(rs2, rs1, offset, address);
			break;
		default:
			cout << "\tInvalid Store Instruction" << endl;
	}
}
void SB(unsigned int rs2, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("SB", rs2, rs1, offset);

	memory[address] = regs[rs2] & 0xFF;

	cout << "MEM[" << address<< "] = " << hex << setw(8) <<( regs[rs2] <<(8*(address%4)) ) << dec << endl;
}
void SH(unsigned int rs2, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("SH", rs2, rs1, offset);

	memory[address] = regs[rs2] & 0xFF;
	memory[address + 1] = (regs[rs2] >> 8) & 0xFF;

	cout << "MEM[" << address<< "] = " << hex << setw(8) <<( regs[rs2] <<8*(address%4) )  << dec << endl;
}
void SW(unsigned int rs2, unsigned int rs1, unsigned int offset, unsigned int address)
{
	printInstL_S("SW", rs2, rs1, offset);

	if(address%4) cout << "Memory address not divisible by 4 -- " << address << endl;
	//if (address == MMAP_PRINT)
	//	cout << regs[rs2];
	//else{
	//cout << "writing to: " << address << " " << regs[rs2] << endl;
	memory[address] = regs[rs2] & 0xFF;
	memory[address + 1] = (regs[rs2] >> 8) & 0xFF;
	memory[address + 2] = (regs[rs2] >> 16) & 0xFF;
	memory[address + 3] = (regs[rs2] >> 24) & 0xFF;

	cout << "MEM[" << address<< "] = " << hex << setw(8) <<( regs[rs2] ) << dec << endl;
	// }
}

void printInstI(string inst, unsigned int rd, unsigned int rs1, unsigned int imm)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << rd << ", x" << rs1 << ", " << int(imm) << endl;
	//cout <<"RF["<<rd<<"]="<< regs[rd] << endl;
}
void I_Inst(unsigned int rd, unsigned int rs1, unsigned int I_imm, unsigned int funct3)
{
	unsigned int shamt = I_imm & 0x1F;
	unsigned int funct7 = (I_imm >> 5) & 0x7F;

	switch(funct3){
		case 0x0:
			ADDI(rd, rs1, I_imm);
			break;
		case 0x1:
			SLLI(rd, rs1, shamt);
			break;
		case 0x2:
			SLTI(rd, rs1, I_imm);
			break;
		case 0x3:
			SLTIU(rd, rs1, I_imm);
			break;
		case 0x4:
			XORI(rd, rs1, I_imm);
			break;
		case 0x5:
			switch(funct7){
				case 0x0:
					SRLI(rd, rs1, shamt);
					break;
				case 0x20:
					SRAI(rd, rs1, shamt);
					break;
				default:
					cout << "\tInvalid I Instruction" << endl;
			}
			break;
		case 0x6:
			ORI(rd, rs1, I_imm);
			break;
		case 0x7:
			ANDI(rd, rs1, I_imm);
			break;
		default:
			cout << "\tInvalid I Instruction" << endl;
	}
}
void ADDI(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("ADDI", rd, rs1, I_imm);

	regs[rd] = regs[rs1] + (int)I_imm;
}
void SLLI(unsigned int rd, unsigned int rs1, unsigned int shamt)
{
	printInstI("SLLI", rd, rs1, shamt);

	regs[rd] = regs[rs1] << shamt;
}
void SLTI(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("SLTI", rd, rs1, I_imm);

	regs[rd] = regs[rs1] < int(I_imm);
}
void SLTIU(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("SLTIU", rd, rs1, I_imm);

	regs[rd] = (unsigned int)(regs[rs1]) < I_imm;
}
void XORI(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("XORI", rd, rs1, I_imm);

	regs[rd] = regs[rs1] ^ int(I_imm);
}
void SRLI(unsigned int rd, unsigned int rs1, unsigned int shamt)
{
	printInstI("SRLI", rd, rs1, shamt);

	regs[rd] = (unsigned int)(regs[rs1]) >> shamt;
}
void SRAI(unsigned int rd, unsigned int rs1, unsigned int shamt)
{
	printInstI("SRAI", rd, rs1, shamt);

	regs[rd] = regs[rs1] >> shamt;
}
void ORI(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("ORI", rd, rs1, I_imm);

	regs[rd] = regs[rs1] | int(I_imm);
}
void ANDI(unsigned int rd, unsigned int rs1, unsigned int I_imm)
{
	printInstI("ANDI", rd, rs1, I_imm);

	regs[rd] = regs[rs1] & int(I_imm);
}


void printInstR(string inst, unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	cout << dec;
	cout << '\t' << inst << "\tx" << rd << ", x" << rs1 << ", x" << rs2 << endl;
	//cout <<"RF["<<rd<<"]="<< regs[rd] << endl;
}

void R_Inst(unsigned int rd, unsigned int rs1, unsigned int rs2, unsigned int funct3, unsigned int funct7)
{
	switch(funct3){
		case 0x0:
			switch(funct7){
				case 0x0:
					ADD(rd, rs1, rs2);
					break;
				case 0x20:
					SUB(rd, rs1, rs2);
					break;
				default:
					cout << "\tInvalid R Instruction \n";
			}
			break;
		case 0x1:
			SLL(rd, rs1, rs2);
			break;
		case 0x2:
			SLT(rd, rs1, rs2);
			break;
		case 0x3:
			SLTU(rd, rs1, rs2);
			break;
		case 0x4:
			XOR(rd, rs1, rs2);
			break;
		case 0x5:
			switch(funct7){
				case 0x0:
					SRL(rd, rs1, rs2);
					break;
				case 0x20:
					SRA(rd, rs1, rs2);
					break;
				default:
					cout << "\tInvalid R Instruction \n";
			}
			break;
		case 0x6:
			OR(rd, rs1, rs2);
			break;
		case 0x7:
			AND(rd, rs1, rs2);
			break;
		default:
			cout << "\tInvalid R Instruction" << endl;
	}
}
void ADD(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("ADD", rd, rs1, rs2);

	regs[rd] = regs[rs1] + regs[rs2];
}
void SUB(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SUB", rd, rs1, rs2);

	regs[rd] = regs[rs1] - regs[rs2];
}
void SLL(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SLL", rd, rs1, rs2);

	regs[rd] = regs[rs1] <<  regs[rs2];
}
void SLT(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SLT", rd, rs1, rs2);

	regs[rd] = regs[rs1] <  regs[rs2];
}
void SLTU(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SLTU", rd, rs1, rs2);

	regs[rd] = (unsigned int)(regs[rs1]) < (unsigned int)(regs[rs2]);
}
void XOR(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("XOR", rd, rs1, rs2);

	regs[rd] = regs[rs1] ^ regs[rs2];
}
void SRL(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SRL", rd, rs1, rs2);

	regs[rd] = (unsigned int)(regs[rs1]) >> (unsigned int)(regs[rs2]);
	//cout << "SRL x" << rd << " gets " << regs[rd] << " - " <<  regs[rs1] << " - " << <<\n";
}
void SRA(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("SRA", rd, rs1, rs2);

	regs[rd] = regs[rs1] >> (unsigned int)(regs[rs2]);
}
void OR(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("OR", rd, rs1, rs2);

	regs[rd] = regs[rs1] | regs[rs2];
}
void AND(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("AND", rd, rs1, rs2);

	regs[rd] = regs[rs1] & regs[rs2];
}

void Ext_Inst(unsigned int rd, unsigned int rs1, unsigned int rs2, unsigned int funct3)
{
	switch(funct3){
		case 0x0: //mul
			MUL(rd, rs1, rs2);
			break;
		default:
			cout << "\tUnsupported Extension Instruction \n";
	}
}

void MUL(unsigned int rd, unsigned int rs1, unsigned int rs2)
{
	printInstR("EXT_MUL", rd, rs1, rs2);

	regs[rd] = regs[rs1] * regs[rs2];
}

void printInstE()
{
	cout << "\tECALL" << endl;
}
void ECALL()
{
	printInstE();

	switch(regs[17]){
		case 1:
			printInteger();
			break;
		case 4:
			printString();
			break;
		case 5:
			readInteger();
			break;
		case 10:
			terminateExecution();
			break;
		default:
			cout << "\tUnknown Enviroment Instruction" << endl;
	}
}
void printInteger()
{
	cout << dec << regs[10] << endl;
}
void printString()
{
	unsigned int address = (unsigned int)regs[10];

	while(address < RAM && memory[address] != '\0'){
		cout.put(memory[address++]);
	}
}
void readInteger()
{
	cin >> regs[10];
}
void terminateExecution()
{
	terminated = true;
}


unsigned int decompress(unsigned int inst, bool &is16)
{
	unsigned oldInst = inst;
	inst = inst & 0x0000FFFF;
	int op = inst & 3;
	int fun3 = (inst & (7 << 13)) >> 13;
	int fun2 = (inst & (3 << 10)) >> 10;
	int fun = (inst & (3 << 5)) >> 5;
	int Brs1 = (inst & (31 << 7)) >> 7;
	int Brs2 = (inst & (31 << 2)) >> 2;
	is16 = true;

	switch (op)
	{
	case 0:				//C0
		switch (fun3)
		{
		case 0:		//C.ADDI4SPN
					//addi rd0, x2, nzuimm[9:2].
			inst = (0 | (((inst & (15 << 7)) >> 7) << 26) | (((inst & (3 << 11)) >> 11) << 24) | (((inst & (1 << 5)) >> 5) << 23) | (((inst & (1 << 6)) >> 6) << 22) | (0b00 << 20) | (0b00010 << 15) | (0b000 << 12) | (0b01 << 10) | ((Brs2 & 0b111) << 7) | 0b0010011);
			break;
		case 2:		//C.LW
					//lw rd',offset[6:2](rs1').
			inst = (0 | (((inst & (1 << 5)) >> 5) << 26) | (((inst & (7 << 10)) >> 10) << 23) | (((inst & (1 << 6)) >> 6) << 22) | (0b00 << 20) | (0b01 << 18) | (((inst & (7 << 7)) >> 7) << 15) | (0b010 << 12) | (0b01 << 10) | ((Brs2 & 0b111) << 7) | 0b0000011);
			break;
		case 6:		//C.SW
					//sw rs2',offset[6:2](rs1').
			inst = (0 | (((inst & (1 << 5)) >> 5) << 26) | (((inst & (1 << 12)) >> 12) << 25) | (0b01 << 23) | ((Brs2 & 0b111) << 20) | (0b01 << 18) | (((inst & (7 << 7)) >> 7) << 15) | (0b010 << 12) | (((inst & (3 << 10)) >> 10) << 10) | (((inst & (1 << 6)) >> 6) << 9) | (0b00 << 7) | 0b0100011);
		}
		break;
	case 1:				//C1
		switch (fun3)
		{
		case 0:			//C.ADDI
						//addi rd, rd, nzimm[5:0].
			inst = (((((inst & (1 << 12)) >> 12) * 0x7f) << 25) | (((inst & (31 << 2)) >> 2) << 20) | (((inst & (31 << 7)) >> 7) << 15) | (0b000 << 12) | (((inst & (31 << 7)) >> 7) << 7) | 0b0010011);
			break;

		case 1:			//C.JAL
						//jal x1, offset[11:1].
			inst = ((((inst & (1 << 12)) >> 12) << 31) | (((inst & (1 << 8)) >> 8) << 30) | (((inst & (3 << 9)) >> 9) << 28) | (((inst & (1 << 6)) >> 6) << 27) | (((inst & (1 << 7)) >> 7) << 26) | (((inst & (1 << 2)) >> 2) << 25) | (((inst & (1 << 11)) >> 11) << 24) | (((inst &(7 << 3)) >> 3) << 21) | ((((inst & (1 << 12)) >> 12) * 0x1ff) << 12) | (0b00001 << 7) | 0b1101111);
			break;

		case 2:			//C.LI
						//addi rd, x0, imm[5:0].
			inst = (((((inst & (1 << 12)) >> 12) * 0x7f) << 25) | (((inst & (31 << 2)) >> 2) << 20) | (0b00000 << 15) | (0b000 << 12) | (((inst & (31 << 7)) >> 7) << 7) | 0b0010011);
			break;

		case 3:			//C.LUI,C.ADDI16SP
			switch (Brs1)
			{
			case 2:     //C.ADDI16SP
						//addi x2, x2, nzimm[9:4].
				inst = (((((inst & (1 << 12)) >> 12) * 0xf) << 29) | (((inst & (3 << 3)) >> 3) << 27) | (((inst & (1 << 5)) >> 5) << 26) | (((inst & (1 << 2)) >> 2) << 25) | (((inst & (1 << 6)) >> 6) << 24) | (0b0000 << 20) | (Brs1 << 15) | (0b000 << 12) | (Brs1 << 7) | 0b0010011);
				break;

			default:	//C.LUI
						//lui rd, nzuimm[17:12].
				inst = (((((inst & (1 << 12)) >> 12) * 0x7fff) << 17) | (((inst & (31 << 2)) >> 2) << 12) | (Brs1 << 7) | 0b0110111);
			}
			break;

		case 4:			//C.SRLI, C.SRAI, C.ANDI
			switch (fun2)
			{

			case 0:		//C.SRLI
				//srli rd', rd', shamt[5:0]
				inst = (0 | (((inst & (31 << 2)) >> 2) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b101 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0010011);
				break;
			case 1:		//C.SRAI
				//srai rd', rd', shamt[5:0],
				inst = (0 | (1<<30) | (((inst & (31 << 2)) >> 2) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b101 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0010011);
				break;
			case 2:		//C.ANDI
						//andi rd', rd', imm[5:0].
				inst = (((((inst & (1 << 12)) >> 12) * 0x7f) << 25) | (((inst & (31 << 2)) >> 2) << 20) | (0b01 << 18) | (((inst & (7 << 7)) >> 7) << 15) | (0b111 << 12) | (0b01 << 10) | (((inst & (7 << 7)) >> 7) << 7) | 0b0010011);
				break;
			case 3:
				if (!(inst & (1 << 12)))
				{
					switch (fun)
					{
					case 0:		//C.SUB
								//sub rd', rd', rs2'.
						inst = ((0b0100000 << 25) | (0b01 << 23) | ((Brs2 & 0b111) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b000 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0110011);
						break;
					case 1:		//C.XOR
								//xor rd', rd', rs2'.
						inst = (0 | (0b01 << 23) | ((Brs2 & 0b111) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b100 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0110011);
						break;
					case 2:		//C.OR
								//or rd', rd', rs2'.
						inst = (0 | (0b01 << 23) | ((Brs2 & 0b111) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b110 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0110011);
						break;
					case 3:		//C.AND
								//and rd', rd', rs2'.
						inst = (0 | (0b01 << 23) | ((Brs2 & 0b111) << 20) | (0b01 << 18) | ((Brs1 & 0b111) << 15) | (0b111 << 12) | (0b01 << 10) | ((Brs1 & 0b111) << 7) | 0b0110011);
						break;

					}
				}
			}
			break;

		case 5:		//C.J
					//jal x0,offset[11:1].
			inst = ((((inst & (1 << 12)) >> 12) << 31) | (((inst & (1 << 8)) >> 8) << 30) | (((inst & (3 << 9)) >> 9) << 28) | (((inst & (1 << 6)) >> 6) << 27) | (((inst & (1 << 7)) >> 7) << 26) | (((inst & (1 << 2)) >> 2) << 25) | (((inst & (1 << 11)) >> 11) << 24) | (((inst & (7 << 3)) >> 3) << 21) | ((((inst & (1 << 12)) >> 12) * 0x1ff) << 12) | (0b00000 << 7) | 0b1101111);
			break;

		case 6:		//C.BEQZ
					//beq rs1', x0, offset[8:1].
			inst = (((((inst & (1 << 12)) >> 12) * 0xf) << 28) | (((inst & (3 << 5)) >> 5) << 26) | (((inst & (1 << 2)) >> 2) << 25) | (0b00000 << 20) | (0b01 << 18) | (((inst & (7 << 7)) >> 7) << 15) | (0b000 << 12) | (((inst & (3 << 10)) >> 10) << 10) | (((inst & (3 << 3)) >> 3) << 8) | (((inst & (1 << 12)) >> 12) << 7) | 0b1100011);
			break;

		case 7:		//C.BNEZ
					//bne rs1', x0, offset[8:1].
			inst = (((((inst & (1 << 12)) >> 12) * 0xf) << 28) | (((inst & (3 << 5)) >> 5) << 26) | (((inst & (1 << 2)) >> 2) << 25) | (0b00000 << 20) | (0b01 << 18) | (((inst & (7 << 7)) >> 7) << 15) | (0b001 << 12) | (((inst & (3 << 10)) >> 10) << 10) | (((inst & (3 << 3)) >> 3) << 8) | (((inst & (1 << 12)) >> 12) << 7) | 0b1100011);
		}
		break;
	case 2:
		switch (fun3)
		{
		case 0:		//C.SLLI
					//slli rd, rd, shamt[5:0],.
			inst = (0 | (Brs2 << 20) | (Brs1 << 15) | (0b001 << 12) | (Brs1 << 7) | 0b0010011);
			break;
		case 2:		//C.LWSP
					//lw rd,offset[7:2](x2).
			inst = (0 | (((inst & (3 << 2)) >> 2) << 26) | (((inst & (1 << 12)) >> 12) << 25) | (((inst &  (7 << 4)) >> 4) << 22) | (0b00 << 20) | (0b00010 << 15) | (0b010 << 12) | (Brs1 << 7) | 0b0000011);
			break;
		case 4:
			if ((inst & (1 << 12)) >> 12)
			{
				if (!Brs2&&!Brs1)      //C.EBREAK
									   //EBREAK
					inst = (0 | (1 << 20) | 0b1110011);
				else if (!Brs2)			//C.JALR    
										//jalr x1, rs1, 0.
					inst = (0 | (Brs1 << 15) | (0b000 << 12) | (0b00001 << 7) | 0b1100111);
				else				  //C.ADD   
									  //add rd, rd, rs2.
					inst = (0 | (Brs2 << 20) | (Brs1 << 15) | (0b000 << 12) | (Brs1 << 7) | 0b0110011);
			}
			else
			{
				if (!Brs2)		//C.JR
								//jalr x0, rs1, 0.
				{
					inst = (0 | (Brs1 << 15) | (0b000 << 12) | (0b00000 << 7) | 0b1100111);
				}
				else			//C.MV
								//add rd, x0, rs2.
					inst = (0 | (Brs2 << 20) | (0b00000 << 15) | (0b000 << 12) | (Brs1 << 7) | 0b0110011);
			}
			break;
		case 6:		//C.SWSP
					//sw rs2,offset[7:2](x2).
			inst = (0 | (((inst & (3 << 7)) >> 7) << 26) | (((inst & (1 << 12)) >> 12) << 25) | (Brs2 << 20) | (0b00010 << 15) | (0b010 << 12) | (((inst & (7 << 9)) >> 9) << 9) | (0b00 << 7) | 0b0100011);
		}
		break;
	case 3:
		is16 = false;
		inst = oldInst;
	}
	return inst;
}
