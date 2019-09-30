#include <iostream>
#include <fstream>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>
#include <ctime>
#include <climits>
#include <cmath>
#include <algorithm>
using namespace std;

vector <string> program;
vector <int> brIndex;
vector <vector<string>> blocks;
const int funcBlock = 30;
//the following probabilities should add to 100, otherwise the program will terminate
const int Iprob = 30;
const int Rprob = 30;
const int Jprob = 10;
const int SLprob = 25;
const int Uprob = 5;

// instCnt is the number of instructions for a block
// regCnt is the number of registers
//string SB(int instCnt, int regCnt);

#define w_aligned(addr) (addr%4==0)
#define hw_aligned(addr) (w_aligned(addr)||addr%4==2)
#define b_aligned(addr) (1)
#define random_signed(size) (rand()%(1LL<<(size))-(1LL<<(size-1)))
#define random_unsigned(size) (rand()%(1LL<<(size)))

string genLoad(int rs1, int rs2, int off, int addr, int u);
string genStore(int rs1, int rs2, int off, int addr);
string genLI(int rd, int imm); //imm: 32 bit value (pseudo instruction)

void emitError(string error_message);


//memsize in bytes, number of memory locations selcted, count of instructions
int getDataAddress(int memsize, int memory_addrs_size, int cnt);
void initMem(vector<int> &memory_addrs, int memsize, int rcnt);
void testMem(vector<int> &memory_addrs, int memsize, int rcnt);

void initREGS(int rcnt) {
	int i;
	for (i = 1; i<rcnt; i++) {
		printf("li\tx%d, %d\n", i, rand() % i);
	}
}
bool findInV(int v, vector<int> V);

string R(int rd, int rs1, int rs2, int regCnt, vector<int>noUse);
string I(int rd, int rs1, int imm, int regCnt, vector<int>noUse);
string SB(int rs1, int rs2, int regCnt, int i);
string jump(int i);
string funcgen(int regCnt, int k, vector<int>& memory_addrs, int memsize);
string CR(int rd, int rs, int regCnt, vector<int>noUse);
string CI(int rd, int imm, int regCnt, vector<int>noUse);
string CJ(int i);
string CB(int rs, int regCnt, int i);
string U(int rd, int imm, int regCnt, vector<int>noUse);

string geninst(int rd, int rs1, int rs2, int imm, int regCnt, int& brJi, vector<int>noUse, int k, vector<int>&memory_addrs, int memsize, bool Proh);

void insertLabels(int);


int main(int argc, char *argv[]) {
	if (argc<3) {
		printf("missing arguments\nuse: randreg <no_of_inst> <memory_size> [no_of_regs]\n");
		return 0;
	}
	
	if ((Rprob + Iprob + Jprob + SLprob + Uprob) != 100) {
		printf("Invalid Instruction Probabilities, they don't add up to 100");
		return 0;
	}

	srand(time(NULL));
	int cnt = atoi(argv[1]); 	//not including initialization instructions
	int memsize = atoi(argv[2]);
	int rcnt = (argc == 4) ? atoi(argv[3]) : 32;


	//memory instructions
	vector<int> memory_addrs;
	int min_meminsts_num = 1;
	int max_meminsts_num = cnt / 7;
	//select some random memory locations for testing
	memory_addrs.resize(min_meminsts_num + rand() % max_meminsts_num);
	for (int i = 0; i < memory_addrs.size(); i++)
		memory_addrs[i] = getDataAddress(memsize, memory_addrs.size(), cnt);


	//program start
	initMem(memory_addrs, memsize, rcnt); //init and test memory
	testMem(memory_addrs, memsize, rcnt);
	initREGS(rcnt);

	int k = 0;
	int brCnt = 0;
	for (;k < cnt; k++)
	{
		vector<int>n;
		n.push_back(33);
		string inst = geninst(33, 33, 33, INT_MAX, 32, brCnt, n, k, memory_addrs, memsize,false);
		program.push_back(inst);
		//cout << inst;

		//cout << geninst(33, 33, 33, INT_MAX, n);
	}

	//program.resize(program.size()+10);
	insertLabels(cnt);
	for (int i = 0; i < program.size(); i++) cout << program[i];


	// exit
	printf("li\ta7, 10\necall\n");

	for (int i = 0; i < blocks.size(); i++)
		for (int j = 0; j < blocks[i].size(); j++)
			cout << blocks[i][j];

	return 0;
}

////// vital for jumps --> make sure that label is not too far (c jumps)
void insertLabels(int instCnt) {
	int i = 1;
	for (int j = 0; j < brIndex.size(); j++) {
		vector<string>::iterator it = program.begin();
		string label = "label" + to_string(i) + ":\n";
		i++;
		int offset = (rand() % (instCnt / 10)) + 1;

		int br_last = brIndex[j] + offset;
		//	cout << "size: " << program.size() << "   branch: " << brIndex[j] << "   label: " << brIndex[j] + offset - 1 << endl;

		if (br_last + 1 >= program.size()) program.push_back(label);
		else program.insert(it + br_last + 1, label);

		for (int k = j; k < brIndex.size(); k++)
			if (brIndex[k] > br_last)
				brIndex[k]++;

	}
}

string geninst(int rd, int rs1, int rs2, int imm, int regCnt, int& brJi, vector<int>noUse, int k, vector<int>& memory_addrs, int memsize, bool Proh)
{
	int addr = 0;
	int offset = 0;
	int u = rand() % 2;
	string generated;
	//int c = 0;
#ifdef C_EXT
	int c = rand() % 2;
#else
	int c = 0;
#endif
	
	float type = static_cast <float> (rand()) / static_cast <float> (RAND_MAX);
	if (Proh)
	{
		while (type >(Rprob + Iprob + Uprob + SLprob) / 100.0)
			type = rand() % 1;
	}

	int inType;

	if (type <= Rprob / 100.0)
		return (c? CR(rd, rs1, regCnt, noUse) :R(rd, rs1, rs2, regCnt, noUse));
	else if (type <= (Rprob + Iprob) / 100.0)
		return (c? CI(rd, imm, regCnt, noUse) : I(rd, rs1, imm, regCnt, noUse));
	else if (type <= (Rprob + Iprob + Uprob) / 100.0)
		return U(rd, imm, regCnt, noUse);
	else if (type <= (Rprob + Iprob + Uprob + SLprob) / 100.0)
	{
		inType = rand() % 2;
		switch (inType)
		{
		case 0:
			addr = memory_addrs[rand() % memory_addrs.size()];
			//offset = (rand() % 2 ? -1 : 1) * random_unsigned(11) % (min(memsize - addr, addr));
			offset = 0;
			rs1 = rand() % (regCnt - 2) + 2, rs2 = rand() % (regCnt - 1) + 1;
			generated = genLI(rs1, addr - offset);
			generated += genStore(rs1, rs2, offset, addr);
			return generated;
		case 1:
			addr = memory_addrs[rand() % memory_addrs.size()];
			//offset = (rand() % 2 ? -1 : 1) * random_unsigned(11) % (min(memsize - addr, addr));
			offset = 0;
			rs1 = rand() % (regCnt - 2) + 2, rs2 = rand() % (regCnt - 2) + 2;
			generated = genLI(rs1, addr - offset);
			generated += genLoad(rs1, rs2, offset, addr, u);
			return generated;
		}
	}
	else
	{

		inType = rand() % 3;
		switch (inType)
		{
		case 0:
			brJi++;
			brIndex.push_back(k);
			return (c? CB (rs1, regCnt, brJi) : SB(rs1, rs2, regCnt, brJi));
		case 1:
			brJi++;
			brIndex.push_back(k);
			return (c ? CJ(brJi) : jump(brJi));
		case 2:
			return funcgen(regCnt, k, memory_addrs, memsize );
		}
	}
}

string U(int rd, int imm, int regCnt, vector<int>noUse)
{
	if (rd == 33)
	{
		do {
			rd = rand() % regCnt;
		} while (findInV(rd, noUse));
	}

	int sign = (rand() % 2) ? 1 : -1;
	if (imm == INT_MAX)
		imm = (rand() % (1 << 20));
	string arrU[2] = { "lui","auipc" };
	string instName = arrU[rand() % 2];
	return (instName + "\tx" + to_string(rd) + ", " + to_string(imm) + "\n");
}

string I(int rd, int rs1, int imm, int regCnt, vector<int>noUse)
{
	if (rd == 33)
	{
		do {
			rd = rand() % regCnt;
		} while (findInV(rd, noUse));
	}

	if (rs1 == 33)
		rs1 = rand() % regCnt;

	bool isShift = false;

	string arrI[10] = { "addi" ,"slli" ,"srli","srai","andi","ori","xori","slti","sltiu" };

	string instName = arrI[rand() % 9];

	isShift = (instName == "slli") || (instName == "srli") || (instName == "srai");
	int sign = (rand() % 2) ? 1 : -1;
	if (imm == INT_MAX)
		if (isShift)
			imm = rand() % regCnt;
		else
			imm = (rand() % (1 << 10)) * sign;

	return(instName + "\tx" + to_string(rd) + ", x" + to_string(rs1) + ", " + to_string(imm) + "\n");
}

string R(int rd, int rs1, int rs2, int regCnt, vector<int>noUse)
{
	if (rd == 33)
	{
		do {
			rd = rand() % regCnt;
		} while (findInV(rd, noUse));
	}

	if (rs1 == 33)
		rs1 = rand() % regCnt;

	if (rs2 == 33)
		rs2 = rand() % regCnt;

	string arrR[10] = { "add" ,"sub","sll" ,"srl","sra","and","or","xor","slt","sltu" };

	string instName = arrR[rand() % 10];

	return(instName + "\tx" + to_string(rd) + ", x" + to_string(rs1) + ", x" + to_string(rs2) + "\n");

}

string SB(int rs1, int rs2, int regCnt, int i) {

	string branch[6] = { "beq", "bne", "bge", "blt", "bltu", "bgeu" };
	if (rs1 == 33) rs1 = rand() % regCnt;
	if (rs2 == 33) rs2 = rand() % regCnt;
	int br = rand() % 6;
	string inst = branch[br] + "\tx" + to_string(rs1) + ", x" + to_string(rs2) + ", label" + to_string(i) + "\n";
	return inst;
}

string jump(int i) {
	string inst = "j\tlabel" + to_string(i) + "\n";
	return inst;
}


// c.swsp rs2, 6-bit imm
// c.lw rd', 6-bit imm (rs1')
// c.lwsp rd != 0, 6-bit imm
// c.sw rs2', 5-bit imm (rs1')

// c.jal 11-bit
// c.jr --> not supported for now




string CR(int rd, int rs, int regCnt, vector<int>noUse) {
	// c.mv rd != 0, rs2 != 0
	// c.add rd != 0, rs2 != 0
	// c.and rd', rs2'
	// c.or rd', rs2'
	// c.xor rd', rs2'
	// c.sub rd', rs2'
	string inst[6] = { "c.add", "c.mv", "c.sub", "c.xor", "c.and", "c.or" };
	int gen = rand() % 6;
	string instruction = inst[gen];
	if (gen < 2) {
		if (rd == 33) {
			do {
				rd = rand() % regCnt;
			} while (rd == 0 || findInV(rd, noUse));
		}
		if (rs == 33) {
			do {
				rs = rand() % regCnt;
			} while (rs == 0 );
		}
		instruction += "\tx" + to_string(rd) + ", x" + to_string(rs) + "\n";
	}
	else {
		if (rd == 33) {
			do {
				rd = 8 + (rand() % 8);
			} while (findInV(rd, noUse));
		}
		if (rs == 33) {
			rs = 8 + (rand() % 8);
		}
		instruction += "\tx" + to_string(rd) + ", x" + to_string(rs) + "\n";
	}
	return instruction;
}

string CI(int rd, int imm, int regCnt, vector<int>noUse) {
	// c.slli rd != 0, 5-bit non-zero 
	// c.srli rd', 5-bit non-zero
	// c.lui rd != 0 & != 2, 6-bit & != 0 pos
	// c.li rd != 0, 6-bit 
	// c.addi rd != 0, 6-bit non-zero 
	// c.addi16sp rd == 2, 6-bit non-zero sig
	// c.andi rd', 6-bit signed 
	// c.srai rd', 5-bit non-zero
	// c.addi4spn rd', 8-bit non-zero pos

	string inst[9] = { "c.li", "c.lui", "c.addi", "c.addi16sp", "c.addi4spn", "c.slli", "c.srli", "c.srai", "c.andi" };
	int gen = rand() % 9;
	string instruction = inst[gen];

	if (instruction == "c.slli" || instruction == "c.srli" || instruction == "c.srai") {

		if (imm == INT_MAX) {
			do {
				imm = rand() % (1 << 5);
			} while (imm == 0);
		}


		if (instruction == "c.slli") {
			if (rd == 33)
			{
				do {
					rd = rand() % regCnt;
				} while (rd == 0 || findInV(rd, noUse));
			}
		}
		else {
			if (rd == 33)
			{
				do {
					rd = 8 + rand() % 8;
				} while (findInV(rd, noUse));
			}
		}


	}

	else if (instruction == "c.lui") {
		/////remove for now
		return "";
		if (imm == INT_MAX) {
			do {
				imm = rand() % (1 << 6);
			} while (imm == 0);
		}
		if (rd == 33)
		{
			do {
				rd = rand() % regCnt;
			} while (rd == 0 || rd == 2 || findInV(rd, noUse));
		}
	}

	else if (instruction == "c.addi4spn") {
		if (rd == 33)
		{
			do {
				rd = 8 + rand() % 8;
			} while (findInV(rd, noUse));
		}

		if (imm == INT_MAX) {
			do {
				imm = ((rand() % (1 << 8))>>2)<<2;
			} while (imm == 0);
		}
	}

	else {
		int sign = (rand() % 2) ? 1 : -1;
		if (imm == INT_MAX) {
			do {
				imm = random_signed(6);
			} while ((instruction != "c.andi" || instruction != "c.li") && imm == 0);
		}


		if (instruction == "c.andi") {
			if (rd == 33)
			{
				do {
					rd = 8 + rand() % 8;
				} while (findInV(rd, noUse));
			}
		}

		else if (instruction == "c.addi16sp"){
			imm = (imm >> 4)<<4;
			if (imm == 0)
				imm = 16;
		   	rd = 2;
		}

		else {

			if (rd == 33)
			{
				do {
					rd = rand() % regCnt;
				} while (rd == 0 || findInV(rd, noUse));
			}

		}
	}
	bool sp = false;
	if (instruction == "c.addi4spn")
		sp = true;



	return (instruction + "\tx" + to_string(rd) + (sp? ", sp, " : ", " ) + to_string(imm) + "\n");
}

string CJ(int i) {
	string inst = "c.j\tlabel" + to_string(i) + "\n";
	return inst;
}

string CB(int rs, int regCnt, int i) {
	// c.beqz rs1', 8-bit
	// c.bnez rs1', 8-bit

	string inst[2] = {"c.beqz", "c.bnez"};
	int gen = rand() % 2;
	string instruction = inst[gen];
	if (rs == 33) rs = 8 + rand() % 8;
	instruction += "\tx" + to_string(rs) + ", " + "label" + to_string(i) + "\n";
	return instruction;
}







bool findInV(int v, vector<int> V)
{
	for (int i = 0; i < V.size(); i++)
		if (V[i] == v) return true;

	return false;
}

/*string SB(int instCnt, int regCnt) {

string branch [6] = {"beq", "bne", "bge", "blt", "bltu", "bgeu"};

// get a random register s
// generate a random block of code that doesn't use s
// play with s
// branch

int s = rand() % 32 + 1;		// Don't use register zero for s

vector <int> restricted_use;


// generate some instruction for s
printf("%s", geninst(s, 33, 33, INT_MAX, restricted_use));
instCnt--;


restricted_use.push_back(s);

// to be changed to have multiple target labels
printf("target: \n");

// generate instCnt instructions
while (instCnt > 2) {
printf("%s", geninst(33, 33, 33, INT_MAX, restricted_use));
instCnt--;
}

restricted_use.pop_back();
//change s
// should I stick to ++, --, +=2 ...?
printf("%s", geninst(s, 33, 33, INT_MAX, restricted_use));


//branch instruction
// instead of zero, should be one of the rd regs in the block

int br = rand() % 6;
printf("%s\t x%d, x%d, %s\n", branch[br], s, 0, "target");
}*/



void emitError(string error_message) {
	fprintf(stderr, "%s\n", error_message.c_str());
	exit(0);
}
string genLI(int rd, int imm) {
	return "li\tx" + to_string(rd) + ", " + to_string(imm) + "\n";
}

string genStore(int rs1, int rs2, int off, int addr) {
	//allignment constraint
	string gened;
	if (w_aligned(addr))
		gened = "sw";
	else if (hw_aligned(addr))
		gened = "sh";
	else
		gened = "sb";

	gened += "\tx" + to_string(rs2) + ", " + to_string(off) + "(x" + to_string(rs1) + ")\n";
	return gened;
}

string genLoad(int rs1, int rs2, int off, int addr, int u) {
	//allignment constraint
	if (rs1 == 33)
		rs1 = rand() % 32;

	string gened;
	if (w_aligned(addr))
		gened = "lw";
	else {
		if (hw_aligned(addr))
			gened = "lh";
		else
			gened = "lb";
		if (u)
			gened += "u";
	}
	//gened += ("\tx%d, %d(x%d)\n", rs2, off, rs1);
	gened += "\tx" + to_string(rs2) + ", " + to_string(off) + "(x" + to_string(rs1) + ")\n";
	return gened;
}


//memsize in bytes, number of memory locations selcted, count of instructions
int getDataAddress(int memsize, int memory_addrs_size, int cnt) {
	int start = 32 + cnt + 4 * memory_addrs_size + 16 + 1024;
	start *= 4;
	// init regs + cnt + init mem + 16 IRQs + offset

	if (start > memsize - 1) //error
		emitError("Insufficient memory size");

	int rem = memsize - start - 1;
	return start + (rand() % rem);
}

void initMem(vector<int> &memory_addrs, int memsize, int rcnt) {
	printf("#INITIALIZING MEMORY\n");
	int rs1 = rand() % (rcnt - 1) + 1, rs2 = rand() % (rcnt - 1) + 1;
	while (rs1 == rs2 || rs1 == 0) rs1 = (rs1 + 1) % rcnt;
	for (int i = 0; i < memory_addrs.size(); i++) {
		//value to store
		//int RS2 = random_signed(32); 
		int RS2 = random_signed(12);
		cout << genLI(rs2, RS2);

		//memory address reg & offset
		int addr = memory_addrs[i];
		int offset = (rand() % 2 ? -1 : 1) * random_unsigned(11) % (min(memsize - addr, addr));
		cout << genLI(rs1, addr - offset);
		cout << genStore(rs1, rs2, offset, addr);
	}
}

void testMem(vector<int> &memory_addrs, int memsize, int rcnt) {
	printf("#TESTING MEMORY\n");
	for (int i = 0; i < memory_addrs.size(); i++) {
		int rs1 = rand() % (rcnt - 1) + 1, rs2 = rand() % (rcnt - 1) + 1;

		//memory address reg & offset
		int addr = memory_addrs[i];
		int offset = (rand() % 2 ? -1 : 1) * random_unsigned(11) % (min(memsize - addr, addr));
		cout << genLI(rs1, addr - offset);

		cout << genLoad(rs1, rs2, offset, addr, rand() % 2);
	}
}


string funcgen(int regCnt, int k, vector<int>& memory_addrs, int memsize)
{
	string inst = "jal\tfunc" + to_string(blocks.size()) + "\n";

	int numInst = rand() % funcBlock;
	//instN -= numInst;
	int x = 0;
	vector<int> noUse;
	noUse.push_back(1);
	vector <string> newBlock;
	newBlock.push_back("func" + to_string(blocks.size()) + ":\n");
	while (numInst-- >= 1)
		newBlock.push_back(geninst(33, 33, 33, INT_MAX, regCnt, x, noUse, x, memory_addrs,  memsize, true));

	newBlock.push_back("jr\tx1\n");
	blocks.push_back(newBlock);
	return inst;
}
