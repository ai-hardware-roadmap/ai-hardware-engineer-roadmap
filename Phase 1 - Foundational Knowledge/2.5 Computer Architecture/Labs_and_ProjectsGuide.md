# Computer Architecture Labs - Practical Implementation Guides

Detailed hand-on exercises to reinforce architecture concepts through simulation and analysis.

## Lab 1: Single-Cycle CPU Design in Verilog

### Objective
Understand the basic datapath and control logic needed to execute a simple instruction set.

### Background
A single-cycle CPU completes one instruction per clock cycle. All operations (fetch, decode, execute, memory, write-back) occur within one cycle. This limits clock frequency but simplifies logic.

### ISA Definition (Simplified RISC)

```
4 instruction types (32-bit fixed format):

1. Register-Register (R-format):
   Bits: [31:27] Opcode | [26:22] Rd | [21:17] Rs1 | [16:12] Rs2 | [11:0] unused
   Examples: ADD, SUB, AND, OR, SLT (set less than)

2. Register-Immediate (I-format):
   Bits: [31:27] Opcode | [26:22] Rd | [21:17] Rs1 | [16:0] Immediate (sign-extended)
   Examples: ADDI, SUBI, LDI (load immediate)

3. Load/Store (LS-format):
   Bits: [31:27] Opcode | [26:22] Rd | [21:17] Rs1 | [16:0] Offset (sign-extended)
   Examples: LDR (load), STR (store)

4. Branch (B-format):
   Bits: [31:27] Opcode | [26:0] Target offset (sign-extended, word-aligned)
   Examples: BEQ, BNE, B (unconditional)

Instruction Set (16 instructions minimum):
  Opcode 00000 (0):  ADD   // R[Rd] = R[Rs1] + R[Rs2]
  Opcode 00001 (1):  SUB   // R[Rd] = R[Rs1] - R[Rs2]
  Opcode 00010 (2):  AND   // R[Rd] = R[Rs1] & R[Rs2]
  Opcode 00011 (3):  OR    // R[Rd] = R[Rs1] | R[Rs2]
  Opcode 00100 (4):  SLT   // R[Rd] = (R[Rs1] < R[Rs2]) ? 1 : 0
  Opcode 00101 (5):  ADDI  // R[Rd] = R[Rs1] + Imm
  Opcode 00110 (6):  LDI   // R[Rd] = Imm (immediate load)
  Opcode 00111 (7):  LDR   // R[Rd] = Mem[R[Rs1] + Offset]
  Opcode 01000 (8):  STR   // Mem[R[Rs1] + Offset] = R[Rd]
  Opcode 01001 (9):  BEQ   // if (R[Rs1] == R[Rs2]) PC = Target
  Opcode 01010 (10): BNE   // if (R[Rs1] != R[Rs2]) PC = Target
  Opcode 01011 (11): B     // PC = Target (unconditional)

Registers: 32x 32-bit registers (R0-R31)
Memory: 4KB instruction + 4KB data (dual-port for fetch + load/store)
```

### Datapath Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Instruction Fetch                        │
│  Program Counter (PC) → Instruction Memory → Instruction    │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│                     Control Unit (Decoder)                   │
│  Instruction bits → Opcode, Rd, Rs1, Rs2, Immediate, ...   │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│                      Register File                           │
│  Rs1 address → Register value 1                              │
│  Rs2 address → Register value 2                              │
│  Rd address + data → Write-back                              │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│                    ALU (Arithmetic Logic)                   │
│  Inputs: Value1, Value2, OpCode                             │
│  Output: Result (ALU executes ADD, SUB, AND, OR, SLT)       │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│                      Data Memory                             │
│  For LDR/STR operations                                      │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│              Write-Back (Result Mux)                         │
│  Choose: ALU result, memory data, or immediate              │
│  Write to register file (Rd)                                │
└─────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│            Program Counter Update                            │
│  PC_next = PC + 4 (sequential) or branch target              │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Outline

**File: cpu_single_cycle.v**

```verilog
module CPU (
    input clk, reset,
    output [31:0] PC  // For debugging
);

// ===== Instruction Fetch =====
reg [31:0] pc;
wire [31:0] instr;
InstructionMemory imem(pc, instr);

// ===== Instruction Decode =====
wire [4:0] opcode = instr[31:27];
wire [4:0] rd = instr[26:22];
wire [4:0] rs1 = instr[21:17];
wire [4:0] rs2 = instr[16:12];
wire [16:0] imm_raw = instr[16:0];
wire [31:0] imm = {{15{imm_raw[16]}}, imm_raw};  // Sign-extend

// Control unit: decode opcode to control signals
wire [3:0] alu_op;
wire mem_read, mem_write, reg_write;
wire [1:0] result_mux;  // Choose write-back source
wire branch_en;
ControlUnit ctrl(opcode, alu_op, mem_read, mem_write, reg_write, result_mux, branch_en);

// ===== Register File =====
wire [31:0] reg_data1, reg_data2;
RegisterFile rf(rs1, rs2, rd, alu_result, reg_write, clk, reg_data1, reg_data2);

// ===== ALU =====
wire [31:0] alu_input2 = (opcode[0]) ? imm : reg_data2;  // Immediate vs register
wire [31:0] alu_result;
ALU alu(reg_data1, alu_input2, alu_op, alu_result);
wire zero_flag = (alu_result == 0);

// ===== Data Memory =====
wire [31:0] mem_data;
DataMemory dmem(.addr(alu_result), .read_data(mem_data), .write_data(reg_data2),
               .clk(clk), .read_en(mem_read), .write_en(mem_write));

// ===== Write-Back Mux =====
reg [31:0] write_data;
always @(*) begin
    case (result_mux)
        2'b00: write_data = alu_result;  // ALU result
        2'b01: write_data = mem_data;    // Memory data
        2'b10: write_data = imm;         // Immediate
        default: write_data = 32'b0;
    endcase
end

// ===== Branch / PC Update =====
wire [31:0] branch_target = pc + (imm << 2);  // Word-aligned
wire should_branch = branch_en & (
    (opcode == 5'b01001) ? (reg_data1 == reg_data2) :  // BEQ
    (opcode == 5'b01010) ? (reg_data1 != reg_data2) :  // BNE
    (opcode == 5'b01011)                               // B (unconditional)
);
wire [31:0] pc_next = should_branch ? branch_target : (pc + 4);

// ===== Sequential Logic =====
always @(posedge clk) begin
    if (reset)
        pc <= 32'b0;
    else
        pc <= pc_next;
end

assign PC = pc;  // Debug output

endmodule

// ===== ALU =====
module ALU (
    input [31:0] a, b,
    input [3:0] op,
    output reg [31:0] result
);

always @(*) begin
    case (op)
        4'b0000: result = a + b;       // ADD
        4'b0001: result = a - b;       // SUB
        4'b0010: result = a & b;       // AND
        4'b0011: result = a | b;       // OR
        4'b0100: result = (a < b) ? 1 : 0;  // SLT
        default: result = 32'b0;
    endcase
end

endmodule

// ===== Control Unit =====
module ControlUnit (
    input [4:0] opcode,
    output reg [3:0] alu_op,
    output reg mem_read, mem_write, reg_write,
    output reg [1:0] result_mux,
    output reg branch_en
);

always @(*) begin
    case (opcode)
        5'b00000: begin  // ADD
            alu_op = 4'b0000; reg_write = 1; mem_read = 0; mem_write = 0; result_mux = 2'b00; branch_en = 0;
        end
        5'b00001: begin  // SUB
            alu_op = 4'b0001; reg_write = 1; mem_read = 0; mem_write = 0; result_mux = 2'b00; branch_en = 0;
        end
        // ... (continue for all opcodes)
        5'b00111: begin  // LDR
            alu_op = 4'b0000; reg_write = 1; mem_read = 1; mem_write = 0; result_mux = 2'b01; branch_en = 0;
        end
        5'b01000: begin  // STR
            alu_op = 4'b0000; reg_write = 0; mem_read = 0; mem_write = 1; result_mux = 2'b00; branch_en = 0;
        end
        // ... (continue for branch instructions)
        default: begin
            alu_op = 4'b0000; reg_write = 0; mem_read = 0; mem_write = 0; result_mux = 2'b00; branch_en = 0;
        end
    endcase
end

endmodule

// ===== Register File =====
module RegisterFile (
    input [4:0] rs1, rs2, rd,
    input [31:0] write_data,
    input write_en, clk,
    output [31:0] read_data1, read_data2
);

reg [31:0] regs [0:31];

assign read_data1 = regs[rs1];
assign read_data2 = regs[rs2];

always @(posedge clk) begin
    if (write_en && rd != 0)  // R0 is always 0
        regs[rd] <= write_data;
end

endmodule

// ===== Memories (simplified) =====
module InstructionMemory (
    input [31:0] addr,
    output [31:0] instr
);
// Return example instructions based on address
// (In practice, load from file or hardcoded)
endmodule

module DataMemory (
    input [31:0] addr, write_data,
    input clk, read_en, write_en,
    output [31:0] read_data
);
reg [31:0] mem [0:1023];  // 4KB

assign read_data = read_en ? mem[addr[11:2]] : 32'b0;
always @(posedge clk) begin
    if (write_en)
        mem[addr[11:2]] <= write_data;
end
endmodule
```

### Test Bench

Write a test bench that:
1. Loads a simple program (e.g., 3 ADD instructions, one branch).
2. Steps through cycles.
3. Prints PC, instruction, register changes, memory access.

**Deliverables:**
- Verilog implementation (cpu_single_cycle.v, with all modules).
- Test bench showing execution trace.
- Summary: CPI = 1.0 (by design); demonstrate 3-4 instruction execution sequence.

---

## Lab 2: 5-Stage Pipeline with Forwarding

### Objective
Add pipelining to improve throughput; implement forwarding to reduce stalls.

### Pipeline Stages

```
Stage 1 - Instruction Fetch (IF):
  Read instruction from memory
  Update PC
  Time: 1 cycle

Stage 2 - Instruction Decode & Register Fetch (RF):
  Decode instruction
  Read register values (Rs1, Rs2)
  Compute immediate
  Time: 1 cycle

Stage 3 - Execute (EX):
  ALU operation
  Compute branch target
  Resolve branch condition
  Time: 1 cycle

Stage 4 - Memory (MEM):
  Load/Store operation
  Time: 1 cycle

Stage 5 - Write-Back (WB):
  Write result to register file
  Time: 1 cycle
```

### Hazards & Solutions

**Data Hazard Example:**
```
Cycle:  1    2    3    4    5    6
ADD:    IF  RF  EX  MEM  WB        (takes 5 cycles total)
SUB:        IF  RF  EX  MEM  WB

Hazard: SUB needs R1 in RF stage (cycle 3), but ADD only writes in WB (cycle 5).
Without fix: Stall SUB until ADD completes (2-3 extra cycles).
With forwarding: Forward EX/MEM result of ADD directly to SUB's ALU.
```

### Forwarding Implementation

```verilog
// In EX stage:
wire use_forwarding_rs1 = (rs1 == ex_mem.rd) && ex_mem.reg_write;
wire use_forwarding_rs2 = (rs2 == ex_mem.rd) && ex_mem.reg_write;

wire [31:0] alu_input1 = use_forwarding_rs1 ? ex_mem.result : reg_data1;
wire [31:0] alu_input2 = use_forwarding_rs2 ? ex_mem.result : reg_data2;
```

### Implementation Outline

Key difference from single-cycle:
1. Create pipeline registers (IF_RF, RF_EX, EX_MEM, MEM_WB) to hold state.
2. Each stage operates on its pipeline register; writes to next stage's register.
3. Implement forwarding logic in EX stage.
4. Implement stall logic for unresolvable hazards (e.g., load-use).

```verilog
module CPU_Pipeline (
    input clk, reset,
    output [31:0] PC
);

// ===== Pipeline Registers =====
reg [31:0] if_instr, if_pc;
reg [31:0] rf_reg1, rf_reg2, rf_imm;
reg [4:0] rf_rd, rf_rs1, rf_rs2;
reg [3:0] rf_alu_op;
// ... (EX and MEM pipeline registers similarly)

// ===== Stage 1: Instruction Fetch =====
wire [31:0] pc_next;
reg [31:0] pc;
always @(posedge clk) begin
    if (reset)
        pc <= 0;
    else
        pc <= pc_next;
end

InstructionMemory imem(pc, if_instr);

// ===== Stage 2: Decode & Register Fetch =====
wire [4:0] opcode = if_instr[31:27];
// ... (decode & register read)

// ===== Stage 3: Execute =====
// Forwarding logic:
wire [31:0] alu_input1_forwarded = use_forward_ex_rs1 ? ex_mem.result : rf_reg1;
wire [31:0] alu_input2_forwarded = use_forward_ex_rs2 ? ex_mem.result : rf_reg2;

ALU alu(alu_input1_forwarded, alu_input2_forwarded, rf_alu_op, ex_result);

// Load-use hazard detection:
wire stall = (rf_prev_op == LDR) && ((rs1 == prev_rd) || (rs2 == prev_rd));

// ===== Stage 4: Memory =====
DataMemory dmem(...);

// ===== Stage 5: Write-Back =====
// Write to register file from WB stage

// ===== Pipeline Advance =====
always @(posedge clk) begin
    if (reset) begin
        // Clear all pipeline registers
    end else if (stall) begin
        // Freeze stage 3, 4, 5; but advance stages 1, 2
    end else begin
        rf_reg1 <= ...;
        // ... (update all pipeline registers)
    end
end

endmodule
```

### Performance Comparison

Without pipeline:
- 3 ADD instructions: 5 + 5 + 5 = 15 cycles.

With pipeline (no hazards):
- 3 ADD instructions: 5 + 1 + 1 = 7 cycles (throughput = 1 instr/cycle).

With pipeline + data hazards (without forwarding):
- ADD, SUB dependent: 5 + 3 (stall) + 1 = 9 cycles.

With pipeline + forwarding:
- ADD, SUB dependent: 5 + 1 + 1 = 7 cycles (no penalty!).

**Deliverables:**
- Pipeline Verilog (with forwarding).
- Test bench showing IPC ≈ 1.0 for code without load-use hazards.
- Comparison table: single-cycle vs. pipeline CPI.

---

## Lab 3: Branch Prediction Simulator

### Objective
Implement and simulate branch predictor; measure accuracy vs. real benchmarks.

### Predictor Implementation (C++ / Python)

```cpp
#include <map>
#include <vector>

struct BranchPredictor {
    // 2-level predictor: history → prediction table
    std::map<int, int> history;  // Address → history bits
    std::map<int, int> predictions;  // Address + history → prediction (0/1)

    std::vector<int> mispredictions;
    int total_branches = 0;

    BranchPredictor() {}

    bool predict(int pc, int actual_outcome) {
        total_branches++;

        int hist = history[pc] & 0x3;  // 2-bit history
        int pred = predictions[pc * 4 + hist];  // Indexed lookup

        bool correct = (pred == actual_outcome);
        if (!correct) mispredictions.push_back(pc);

        // Update history & prediction
        history[pc] = ((hist << 1) | actual_outcome) & 0x3;
        predictions[pc * 4 + hist] = actual_outcome;

        return correct;
    }

    double accuracy() {
        return (total_branches - mispredictions.size()) * 100.0 / total_branches;
    }
};
```

### Benchmark Trace Format

```
PC   | Outcome (T=taken, N=not taken)
-----|-----
0x1000  T
0x1004  N
0x1000  T
0x1008  T
...
```

Parse real branch traces from:
- SPEC CPU benchmarks (Intel PIN tool traces).
- RISC-V simulation (Gem5).

### Metrics

```
Accuracy = (Correct Predictions) / Total Branches * 100%
  Good: >94%
  Excellent: >97%

Misprediction Rate = 100% - Accuracy

Cost of Misprediction = (Mispredictions * Pipeline_Depth)
  Example: 100 mispredictions * 10 cycle penalty = 1000 wasted cycles
```

**Deliverables:**
- Predictor C++ implementation.
- Test on 2-3 benchmark traces.
- Report: Accuracy per branch type, most-mispredicted branches, sensitivity to history bits.

---

## Lab 4: Cache Simulator & Analysis

### Objective
Measure cache behavior; optimize for hit rate.

### Cache Simulator (Python / C++)

```python
class Cache:
    def __init__(self, size_kb, line_size, associativity):
        self.size_kb = size_kb
        self.line_size = line_size
        self.associativity = associativity
        self.num_lines = (size_kb * 1024) // line_size
        self.num_sets = self.num_lines // associativity

        self.cache = {}  # set_id → list of (tag, valid, lru_counter)
        self.hits = 0
        self.misses = 0
        self.lru_counter = 0

    def access(self, addr):
        # Extract tag, set index, offset
        offset_bits = (self.line_size - 1).bit_length()
        index_bits = (self.num_sets - 1).bit_length()

        set_id = (addr >> offset_bits) & (self.num_sets - 1)
        tag = addr >> (offset_bits + index_bits)

        if set_id not in self.cache:
            self.cache[set_id] = []

        # Check for hit
        for i, (cached_tag, valid, lru_time) in enumerate(self.cache[set_id]):
            if cached_tag == tag and valid:
                self.hits += 1
                # Update LRU
                self.cache[set_id][i] = (tag, True, self.lru_counter)
                self.lru_counter += 1
                return True

        # Miss: replace LRU entry
        self.misses += 1
        if len(self.cache[set_id]) < self.associativity:
            self.cache[set_id].append((tag, True, self.lru_counter))
        else:
            # Replace LRU
            lru_idx = min(range(len(self.cache[set_id])),
                         key=lambda i: self.cache[set_id][i][2])
            self.cache[set_id][lru_idx] = (tag, True, self.lru_counter)

        self.lru_counter += 1
        return False

    def hit_rate(self):
        total = self.hits + self.misses
        return self.hits * 100.0 / total if total > 0 else 0

# Example usage
cache = Cache(size_kb=32, line_size=64, associativity=8)
with open("memory_trace.txt") as f:
    for line in f:
        addr = int(line.strip(), 16)
        cache.access(addr)

print(f"Hit rate: {cache.hit_rate():.2f}%")
```

### Memory Trace Formats

**Simple format:**
```
0x10001000
0x10001040
0x10001080
...
```

**Real benchmarks:**
```
# Intel PIN output:
T 0x10001000  # Type=trace, Address
M 0x12000100  # Type=memory load
W 0x12000104  # Type=memory write
```

### Analysis Tasks

1. **Vary size:** Test 8KB, 16KB, 32KB, 64KB; measure hit rate.
2. **Vary associativity:** Test direct-mapped, 2-way, 4-way, 8-way.
3. **Vary line size:** Test 32B, 64B, 128B.
4. **Identify misses:** Count compulsory, capacity, and conflict misses (via simulation).

**Deliverables:**
- Functional cache simulator.
- Hit rate curves vs. cache configurations.
- Report on trade-offs (size vs. hit rate, associativity impact).

---

## Lab 5: Multi-Core Coherence Protocol Simulator

### Objective
Implement MESI cache coherence; measure coherence traffic, miss rates.

### MESI Protocol State Machine

```
States: M (Modified), E (Exclusive), S (Shared), I (Invalid)

State Transition Table (per cache line):
┌──────┬──────────┬─────────┬──────────┬──────────┐
│State │ Read Miss│Write Miss│Write Hit │Read Hit  │
├──────┼──────────┼─────────┼──────────┼──────────┤
│  I   │ E or S→E │    M    │   N/A    │   N/A    │
│  E   │    E     │    M    │    M     │    E     │
│  S   │    S     │  Inv+M  │  Inv+M   │    S     │
│  M   │  Shared  │    M    │    M     │    M     │
└──────┴──────────┴─────────┴──────────┴──────────┘

Inv = Issue invalidation to all other cores
```

### Implementation (Python)

```python
class CacheLineMESI:
    INVALID, EXCLUSIVE, SHARED, MODIFIED = 0, 1, 2, 3
    state_names = ["I", "E", "S", "M"]

    def __init__(self):
        self.state = self.INVALID
        self.data = 0

class CORETMESICohere:
    def __init__(self, num_cores=4):
        self.caches = [{} for _ in range(num_cores)]
        self.coherence_traffic = 0
        self.misses = [0] * num_cores

    def access(self, core_id, addr, is_write):
        """Simulate memory access with MESI coherence."""

        if addr not in self.caches[core_id]:
            self.caches[core_id][addr] = CacheLineMESI()

        line = self.caches[core_id][addr]

        if is_write:
            if line.state == CacheLineMESI.MODIFIED:
                # Already own it; just write
                pass
            elif line.state == CacheLineMESI.EXCLUSIVE:
                # Transition to M (move to M)
                line.state = CacheLineMESI.MODIFIED
            elif line.state == CacheLineMESI.SHARED:
                # Invalidate other caches
                for other_id in range(len(self.caches)):
                    if other_id != core_id and addr in self.caches[other_id]:
                        self.caches[other_id][addr].state = CacheLineMESI.INVALID
                        self.coherence_traffic += 1
                line.state = CacheLineMESI.MODIFIED
            else:  # INVALID
                # Fetch and invalidate others
                self.misses[core_id] += 1
                line.state = CacheLineMESI.MODIFIED
        else:  # Read
            if line.state != CacheLineMESI.INVALID:
                # Hit
                pass
            else:
                # Miss; check other cores
                found_shared = False
                for other_id in range(len(self.caches)):
                    if addr in self.caches[other_id]:
                        other_state = self.caches[other_id][addr].state
                        if other_state == CacheLineMESI.MODIFIED or other_state == CacheLineMESI.EXCLUSIVE:
                            line.state = CacheLineMESI.SHARED
                            found_shared = True
                            self.coherence_traffic += 1
                            break

                if not found_shared:
                    line.state = CacheLineMESI.EXCLUSIVE

                self.misses[core_id] += 1
```

**Deliverables:**
- MESI simulator.
- Test on multi-threaded workload (matrix multiply, shared-memory access pattern).
- Report: Coherence traffic, miss rates per core, bottlenecks.

---

## Lab 6: ISA Comparison Project

### Objective
Compare x86-64, ARM64, and RISC-V on same benchmark.

### Benchmark Code (in C)

```c
// matrix_multiply.c
#define N 64

void matmul(int a[N][N], int b[N][N], int c[N][N]) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            c[i][j] = 0;
            for (int k = 0; k < N; k++) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
}

void sort(int* arr, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (arr[j] > arr[j+1]) {
                int tmp = arr[j];
                arr[j] = arr[j+1];
                arr[j+1] = tmp;
            }
        }
    }
}

int fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n-1) + fibonacci(n-2);
}

int main() {
    // Benchmark each function
    matmul(...);
    sort(...);
    fibonacci(30);
    return 0;
}
```

### Compilation & Analysis

```bash
# Compile for each ISA
gcc -O2 -march=native -S matrix_multiply.c  # x86-64
arm-linux-gnueabihf-gcc -O2 -march=armv8-a -S matrix_multiply.c  # ARM
riscv64-unknown-linux-gnu-gcc -O2 -march=rv64imad -S matrix_multiply.c  # RISC-V

# Analyze with objdump / readelf
objdump -d matrix_multiply | wc -l  # Instruction count
objdump -d matrix_multiply | grep -E "^[0-9a-f]+.*:" | wc -l  # Unique instructions
size matrix_multiply  # Binary size
```

### Comparison Metrics

```
1. Code Size (bytes):
   x86-64:  ?
   ARM64:   ?
   RISC-V:  ?

2. Instruction Count:
   x86-64:  ?
   ARM64:   ?
   RISC-V:  ?

3. Register Usage:
   x86-64:  ?
   ARM64:   ?
   RISC-V:  ?

4. Memory References:
   x86-64:  ?
   ARM64:   ?
   RISC-V:  ?

5. Execution Time (on real hardware or simulator):
   x86-64:  ?
   ARM64:   ?
   RISC-V:  ?
```

**Deliverables:**
- Assembly listings for all three ISAs.
- Comparative analysis document.
- Conclusions on code density, instruction selection, memory reference patterns.

---

## Lab 7: CPU Microarchitecture Reverse Engineering

### Objective
Deduce microarchitecture of a real CPU (e.g., M4 Pro, Ryzen 9000) using benchmarking.

### Tools & Techniques

**1. Geekbench 6**
```
Run on target CPU; correlate results to known CPUs.
```

**2. Cachegrind (memory profiler)**
```
valgrind --tool=cachegrind ./program
Outputs: L1/L2/L3 misses, branch mispredictions.
```

**3. PAPI (Performance API)**
```
papi_avail  # List available counters
perf stat -e cache-references,cache-misses ./program
```

**4. Microbenchmarks**
```c
// Example: Measure L1 cache line size
#include <time.h>

int main() {
    int size = 512 * 1024;  // 512 KB array
    char* arr = malloc(size);

    for (int stride = 1; stride <= 256; stride *= 2) {
        // Access array with given stride; measure time
        clock_t start = clock();
        for (int i = 0; i < size; i += stride) {
            arr[i]++;
        }
        clock_t end = clock();
        printf("Stride %d: %ld cycles\n", stride, end - start);
        // Stride = cache line size will show drop in performance
    }
    free(arr);
    return 0;
}
```

### Reverse Engineering Ques

1. **Cache Hierarchy:**
   - Vary array size; measure miss rates.
   - Deduce L1, L2, L3 sizes from miss curves.

2. **Cache Line Size:**
   - Stride through memory at different granularities.
   - Smallest stride with no penalty = line size (typically 64-128 bytes).

3. **TLB:**
   - Create working set that just exceeds TLB capacity.
   - Observe latency jump (TLB miss penalty: 50-500 cycles).

4. **Branch Predictor:**
   - Highly predictable branches (e.g., if i%2) should be ~100% accurate.
   - Irregular branches (hash-based) should show ~50% misprediction.

5. **Pipeline Depth:**
   - Measure misprediction penalty (cycles lost).
   - Each cycle of extra latency = one pipeline stage.

**Deliverables:**
- Benchmarking code (microbenchmarks).
- Measurement results (graphs of cache behavior, TLB, branch prediction).
- Inferred microarchitecture model.
- Validation against published specs.

---

## Lab 8: Capstone - OoO CPU Simulator

### Objective
Build a functional out-of-order CPU simulator; measure IPC and compare to in-order.

### Simulator Architecture (C++)

```cpp
#include <deque>
#include <queue>
#include <set>

struct Instruction {
    uint32_t pc;
    uint32_t opcode;
    int rd, rs1, rs2;
    uint32_t imm;
    uint64_t issue_cycle;
    uint64_t execute_cycle;
    uint64_t commit_cycle;
};

class OoOCPU {
private:
    // Pipeline stages
    std::deque<Instruction> fetch_queue;
    std::deque<Instruction> decode_queue;
    std::vector<Instruction> reservation_station;  // 32-entry RS
    std::vector<Instruction> opaque_buffer;  // Rob (reorder buffer):
    std::deque<Instruction> execute_queue;

    // Execution units
    int alu_free_cycle[2];  // 2 ALUs, each tracks when free
    int mul_free_cycle;
    int lsu_free_cycle;

    int cycle = 0;

public:
    void step() {
        // Stage 1: Fetch (up to 4 instructions/cycle)
        for (int i = 0; i < 4 && !fetch_queue.empty(); i++) {
            auto instr = fetch_queue.front();
            instr.fetch_cycle = cycle;
            decode_queue.push_back(instr);
            fetch_queue.pop_front();
        }

        // Stage 2: Decode & Rename
        for (int i = 0; i < 4 && !decode_queue.empty(); i++) {
            auto instr = decode_queue.front();
            // Rename registers (use physical registers)
            // Add to ROB
            opaque_buffer.push_back(instr);
            // Add to RS if operands not ready
            if (!operands_ready(instr)) {
                reservation_station.push_back(instr);
            } else {
                execute_queue.push_back(instr);
            }
            decode_queue.pop_front();
        }

        // Stage 3: Execute
        for (auto it = execute_queue.begin(); it != execute_queue.end(); ) {
            auto& instr = *it;

            if (can_execute(instr)) {
                int latency = operation_latency(instr.opcode);
                instr.execute_cycle = cycle + latency;
                mark_execution_unit_busy(instr.opcode, cycle + latency);
                it = execute_queue.erase(it);
            } else {
                ++it;
            }
        }

        // Stage 4: Writeback (forward results via CDB)
        for (auto& instr : opaque_buffer) {
            if (instr.execute_cycle == cycle) {
                // Broadcast result on CDB
                // Update physical registers
                // Wake up dependent instructions
            }
        }

        // Stage 5: Commit (in-order from ROB)
        for (auto it = opaque_buffer.begin(); it != opaque_buffer.end(); ) {
            auto& instr = *it;
            if (instr.execute_cycle >= 0 && instr.execute_cycle <= cycle) {
                // Instruction complete; commit
                instr.commit_cycle = cycle;
                // Update architectural state
                it = opaque_buffer.erase(it);
            } else {
                ++it;
            }
        }

        cycle++;
    }

    double ipc() {
        // Instructions committed / total cycles
        // Compute from all retired instructions
    }
};
```

**Deliverables:**
- Functional OoO simulator (~1000 lines C++).
- Test on benchmark (matrix multiply, sort, Fibonacci).
- Compare IPC: in-order vs. OoO vs. superscalar width.
- Output: IPC curves, execution trace, bottleneck analysis.

---

## Summary & Progression

These labs build understanding from single-cycle (foundational) → pipeline → advanced features (OoO, coherence).

**Recommended timeline:**
- Lab 1: Weeks 1-2
- Lab 2: Weeks 3-4
- Lab 3: Weeks 5-6
- Lab 4: Weeks 7-8
- Lab 5: Weeks 9-10
- Lab 6 & 7: Parallel (Weeks 11-12)
- Lab 8 (Capstone): Ongoing (12+ weeks)

**Success Criteria:**
✓ Lab 1: Single-cycle CPU executes 5+ instructions correctly; CPI = 1.0
✓ Lab 2: Pipeline achieves ~1 IPC for code without hazards; forwarding reduces stalls
✓ Lab 3: Predictor achieves >94% accuracy on real benchmarks
✓ Lab 4: Cache simulator matches published numbers for real CPUs
✓ Lab 5: MESI simulator correctly enforces coherence
✓ Lab 6: ISA analysis demonstrates code density & register efficiency
✓ Lab 7: Reverse-engineered microarchitecture matches published specs
✓ Lab 8: OoO simulator achieves 2-4x IPC over in-order baseline
