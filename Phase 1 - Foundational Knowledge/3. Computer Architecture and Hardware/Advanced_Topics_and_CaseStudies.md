# Computer Architecture - Supplementary Materials

Advanced deep-dives, real-world case studies, and extension topics.

---

## Part 1: ISA Deep Dives

### ARM64 (ARMv8/ARMv9) Architecture Deep Dive

#### Registers

```
General-Purpose Registers (31 total):
  X0-X28:     Variable purpose
  X29 (FP):   Frame pointer (convention)
  X30 (LR):   Link register (return address for CALL/RET)
  X31 (SP/ZR):Stack pointer (when used as stack ptr) or zero register (when read)

  Naming: X0-X31 are 64-bit; W0-W31 are 32-bit views (upper 32 bits zeroed on 32-bit write)

Example:
  MOV X0, #42      // X0 = 42
  MOV W0, #42      // W0 = 42 (only lower 32 bits), X0 = 0x00000000_0000002A
  MOV X0, W1       // X0 = zero_extend(W1)

Floating-Point / SIMD Registers:
  V0-V31:  128-bit SIMD registers (also FP64 views)
  Naming:
    D0-D31:   64-bit FP double-precision (uses lower 64 bits of V0-V31)
    S0-S31:   32-bit FP single-precision (uses lower 32 bits of V0-V31)

Condition Codes (NZCV):
  N (Negative):     Result was negative
  Z (Zero):         Result was zero
  C (Carry):        Unsigned overflow / borrow
  V (Overflow):     Signed overflow

Special Registers:
  PC:   Program counter (read-only for RET, BL, etc.)
  SP:   Stack pointer (X31 when used as stack)
  LR:   Link register (X30, used for function returns)
```

#### Instruction Encoding

**A64 Instruction Formats (Fixed 32-bit):**

```
Register-to-Register (R-format):
  [31:30] sf  | [29:24] opcode | [23:22] shift | [21:16] Rm | [15:10] opc | [9:5] Rn | [4:0] Rd
  sf=0 (32-bit) or sf=1 (64-bit)

  Example: ADD X0, X1, X2
  sf=1, opcode=01000, Rm=X2, Rn=X1, Rd=X0

  Common opcodes:
    01000 (MOV):      Logical move
    01100 (ADD/SUB):  Arithmetic with shift
    01101 (MUL):      Multiply

Immediate (I-format):
  [31:24] opcode | [23:22] shift | [21:10] imm12 | [9:5] Rn | [4:0] Rd

  Example: ADD X0, X1, #256
  Immediate can be 0-4095 (12-bit), with optional shift (0, 16, 32, 48 bits)

Load/Store (LS-format):
  [31:30] size | [29:27] class | [26:0] offset

  size: 0=8-bit, 1=16-bit, 2=32-bit, 3=64-bit

  Example: LDR X0, [X1]  (load 64-bit from address X1)
  LDR X0, [X1, #8]       (load from [X1 + 8])
  LDR X0, [X1, X2]       (load from [X1 + X2])
  LDR X0, [X1], #8       (post-index: load from X1, then X1 += 8)
  LDR X0, [X1, #8]!      (pre-index: X1 += 8, then load from X1)

Branch (B-format):
  [31:26] opcode | [25:0] offset (signed)

  BL label      // Branch & Link (CALL)
  B label       // Unconditional branch
  B.EQ label    // Branch if Equal (Z flag set)
  B.NE label    // Branch if Not Equal (Z flag == 0)
```

#### ARMv8 vs. ARMv9 Extensions

**ARMv8 Base (AArch64):**
- 64-bit ISA, 31 GPRs, floating-point, SIMD (NEON 128-bit).
- Atomic operations (LDADD, LDXR, etc.).

**ARMv8.1:**
- Atomic compare-and-swap (CASBP).
- Multi-core improvements.

**ARMv8.3:**
- Pointer authentication (PAC) for return-oriented programming (ROP) defense.
- Cryptography extensions (SHA-512, SHA-3).
- Memory tagging (top-byte-ignore).

**ARMv9:**
- Branch Target Identification (BTI) for control-flow integrity.
- Scalable Vector Extension (SVE) for 128-2048 bit vectors.
- Security improvements (MTE, BTI, PAC).

#### Instruction Set Examples

```arm64
; Arithmetic
ADD X0, X1, X2          ; X0 = X1 + X2
ADDS X0, X1, #5         ; X0 = X1 + 5; update CC
ADD X0, X1, X2, LSL #3  ; X0 = X1 + (X2 << 3)  [shift operand]
SUB X0, X1, X2          ; X0 = X1 - X2
MUL X0, X1, X2          ; X0 = X1 * X2 (64-bit multiply, 128-bit result in X1:X0)

; Logical
AND X0, X1, X2          ; Bitwise AND
ORR X0, X1, X2          ; Bitwise OR
EOR X0, X1, X2          ; Bitwise XOR
MVN X0, X1              ; X0 = ~X1

; Shifts & Rotates
LSL X0, X1, X2          ; Logical shift left
LSR X0, X1, X2          ; Logical shift right
ASR X0, X1, X2          ; Arithmetic shift right
ROR X0, X1, X2          ; Rotate right

; Memory
LDR X0, [X1]            ; Load 64-bit from [X1]
STR X0, [X1]            ; Store X0 to [X1]
LDR W0, [X1, #4]        ; Load 32-bit from [X1+4] (zero-extend to X0)
STR W0, [X1]            ; Store 32-bit W0 to [X1]
LDP X0, X1, [X2]        ; Load pair: X0=[X2], X1=[X2+8]
STP X0, X1, [X2]        ; Store pair

; Branch
B label                 ; Unconditional
BL func                 ; Branch and link (CALL)
RET                     ; Return (implicit: from LR)
B.EQ label              ; Branch if Equal (Z==1)
B.LT label              ; Branch if Less Than (N!=V)
CBNZ X0, label          ; Compare and Branch if Not Zero
TBZ X0, #3, label       ; Test Bit Zero and Branch

; SIMD/NEON
VADD.I32 V0, V1, V2     ; Vector add (4x 32-bit ints)
FMUL S0, S1, S2         ; FP single-precision multiply
FCVT D0, S0             ; Convert single to double precision

; Atomics
LDADD X0, X1, [X2]      ; Atomic: add X0 to [X2], result in X1
LDAR X0, [X1]           ; Load with acquire semantics
STLR X0, [X1]           ; Store with release semantics

; Compare and Set Condition
CMP X0, X1              ; Set CC based on X0 - X1 (no result stored)
TST X0, X1              ; Set CC based on X0 & X1
```

#### ARM64 Calling Convention (System V ARM ABI)

```
Argument passing:
  X0-X7:    First 8 integer arguments
  V0-V7:    First 8 floating-point arguments

Return values:
  X0-X1:    Integer return (X0 for single, X0:X1 for 128-bit)
  V0-V1:    FP return (V0 for single, V0:V1 for 128-bit or larger)

Caller-saved (caller must save if needed):
  X0-X18, V0-V7

Callee-saved (must save if used):
  X19-X29, V8-V15

Special:
  X29 (FP):   Frame pointer
  X30 (LR):   Link register (return address)
  X31 (SP):   Stack pointer (must stay aligned to 16 bytes)

Stack frame (at function entry):
  SP -> [return address (in LR)]
        [caller's X29 (FP)]
        [caller's callee-saved regs]
        [local variables]
```

**Example ARM64 Function:**

```arm64
; int factorial(int n)  // n in W0
factorial:
    CMP W0, #1                  ; if (n <= 1)
    B.LE .factorial_base        ;   goto base case

    SUB W0, W0, #1              ; n = n - 1
    STR LR, [SP, #-16]!         ; Save LR and allocate 16 bytes on stack
    BL factorial                ; X0 = factorial(n-1)

    LDR LR, [SP], #16           ; Restore LR and deallocate
    MUL W0, W0, W1              ; result = X0 * original_n
    RET

.factorial_base:
    MOV W0, #1                  ; return 1
    RET
```

---

### x86-64 Deep Dive

#### Registers

```
General-Purpose (64-bit names):
  RAX, RBX, RCX, RDX   ; 32-bit: EAX, EBX, ECX, EDX
  RSI, RDI             ; Index registers
  RSP, RBP             ; Stack/Base pointers
  R8-R15               ; Additional 64-bit registers

Special purposes (by convention):
  RAX:    Accumulator (return value)
  RBX:    Base (callee-saved)
  RCX:    Counter (function arg 4)
  RDX:    Data (function arg 3)
  RSI:    Source index (function arg 2)
  RDI:    Destination index (function arg 1)
  RBP:    Base pointer (frame pointer, callee-saved)
  RSP:    Stack pointer (must stay aligned to 16 bytes)

Floating-Point (MMX/SSE/AVX):
  XMM0-XMM15:  128-bit registers (4x 32-bit FP or 2x 64-bit)
  YMM0-YMM15:  256-bit registers (8x 32-bit or 4x 64-bit) [AVX]
  ZMM0-ZMM31:  512-bit registers (16x 32-bit or 8x 64-bit) [AVX-512]

Condition Code Register (Flags):
  CF (Carry):       Unsigned overflow
  PF (Parity):      Even number of set bits
  AF (Aux):         Half-byte carry
  ZF (Zero):        Result was zero
  SF (Sign):        Result was negative
  OF (Overflow):    Signed overflow
```

#### Instruction Encoding (Variable-Length)

```
x86-64 instructions: 1-15 bytes

REX Prefix (1 byte) [Optional]:
  40-4F hex
  4[W][R][X][B]
  W=0: 32-bit operation (zero-extends to 64-bit)
  W=1: 64-bit operation
  R=1: Extension of ModRM.reg field (for R8-R15)
  X=1: Extension of SIB.index field
  B=1: Extension of ModRM.rm or SIB.base field

Opcode(1-3 bytes) + ModRM(1 byte) + SIB(1 byte) + Displacement(0-8 bytes) + Immediate(0-8 bytes)

Example: ADD RAX, RBX
  48 01 D8
  48 = REX.W (64-bit)
  01 = ADD opcode (add reg to reg)
  D8 = ModRM: [11 011 000] (reg=RAX, r/m=RBX)

Example: MOV RAX, [RBX + 8]
  48 8B 43 08
  48 = REX.W
  8B = MOV opcode (reg from reg/mem)
  43 = ModRM: [01 000 011] (reg=RAX, r/m=RBX, displacement=8)
  08 = Displacement byte
```

#### Instruction Set Examples

```asm
; Arithmetic
ADD RAX, RBX       ; RAX = RAX + RBX
ADD RAX, 10        ; RAX = RAX + 10 (immediate)
ADD [RAX], RBX     ; [RAX] = [RAX] + RBX (memory operand!)
ADCX RAX, RBX      ; RAX = RAX + RBX + CF (with carry)
SUB RAX, RBX       ; RAX = RAX - RBX
IMUL RAX, RBX      ; RAX = RAX * RBX (signed)
IMUL RAX, RBX, 10  ; RAX = RBX * 10
IDIV RBX           ; RAX = RDX:RAX / RBX; RDX = remainder

; Logical
AND RAX, RBX       ; Bitwise AND
OR RAX, RBX        ; Bitwise OR
XOR RAX, RBX       ; Bitwise XOR
NOT RAX            ; Bitwise NOT

; Shifts
SHL RAX, 1         ; Shift left (equivalent to *2)
SHL RAX, CL        ; Shift left by CL bits
ASR RAX, CL        ; Arithmetic shift right

; Data Movement
MOV RAX, RBX       ; RAX = RBX
MOV RAX, [RBX]     ; RAX = *RBX (load)
MOV [RAX], RBX     ; *RAX = RBX (store)
MOV RAX, 0x1000    ; RAX = 0x1000 (immediate, 64-bit mov with REX)
LEA RAX, [RBX+8]   ; RAX = address of [RBX+8] (no load)
XCHG RAX, RBX      ; Swap RAX and RBX

; Stack
PUSH RAX           ; [RSP] = RAX; RSP -= 8
POP RAX            ; RAX = [RSP]; RSP += 8
CALL func          ; Push RIP, PC = func
RET                ; PC = [RSP]; RSP += 8

; Branch
JMP label          ; PC = label
JE label           ; Jump if Equal (ZF==1)
JL label           ; Jump if Less (SF != OF)
JZ label           ; Jump if Zero (ZF==1)

; Compare and Test
CMP RAX, RBX       ; Set flags based on RAX - RBX
TEST RAX, RAX      ; Set flags based on RAX & RAX
CMPXCHG RAX, RBX   ; Atomic compare-and-exchange

; SSE/AVX
MOVAPS XMM0, XMM1  ; XMM0 = XMM1 (4x 32-bit FP, aligned)
ADDPS XMM0, XMM1   ; Parallel add single-precision
MULPD XMM0, XMM1   ; Parallel multiply double-precision
```

#### x86-64 Calling Convention (System V AMD64 ABI)

```
Argument passing (integer):
  RDI, RSI, RDX, RCX, R8, R9  ; 1st through 6th arguments
  Stack (right-to-left)        ; 7th and beyond

Argument passing (floating-point):
  XMM0-XMM7                    ; FP arguments

Return values:
  RAX (int), or RDX:RAX (128-bit)
  XMM0 (FP), or XMM1:XMM0 (128-bit FP)

Caller-saved (caller must save):
  RAX, RCX, RDX, RSI, RDI, R8-R11, XMM0-XMM15

Callee-saved (must preserve):
  RBX, RSP, RBP, R12-R15

Stack alignment:
  When entering function, RSP % 16 == 0 (16-byte aligned)
  After CALL, RSP % 16 == 8 (return address pushed)

Stack frame (at function entry):
  RSP -> [return address] (pushed by CALL)
         [callee-saved registers] (if using)
         [local variables]
```

**Example x86-64 Function:**

```asm
; int factorial(int n)  // n in RDI
factorial:
    CMP RDI, 1              ; if (n <= 1)
    JLE .factorial_base     ;   goto base case

    SUB RDI, 1              ; n = n - 1
    PUSH RBX                ; Save RBX
    MOV RBX, RDI            ; RBX = n-1 (for later)
    CALL factorial          ; RAX = factorial(RDI)

    IMUL RAX, RBX           ; RAX = result * (original n)
    POP RBX                 ; Restore RBX
    RET

.factorial_base:
    MOV RAX, 1              ; return 1
    RET
```

---

### RISC-V Deep Dive

#### Registers

```
x0-x31:   32 general-purpose registers (RV32/RV64)

Naming convention (by use):
  x0 (zero):    Hardwired to 0
  x1 (ra):      Return address
  x2 (sp):      Stack pointer
  x3 (gp):      Global pointer
  x4 (tp):      Thread pointer
  x5-x7 (t0-t2): Temporary (caller-saved)
  x8 (s0/fp):   Saved register / Frame pointer
  x9 (s1):      Saved register
  x10-x11 (a0-a1): Function arguments 0-1 / Return values
  x12-x17 (a2-a7): Function arguments 2-7
  x18-x27 (s2-s11): Saved registers
  x28-x31 (t3-t6): Temporary registers

Floating-Point (F extension):
  f0-f31:   32 floating-point registers (32-bit or 64-bit depending on extension)
  f0-f7 (ft0-ft7):  Temporary
  f8-f9 (fs0-fs1):  Saved FP registers
  f10-f17 (fa0-fa7): FP arguments / Return values
  f18-f27 (fs2-fs11): Saved FP registers
```

#### Instruction Formats (Fixed 32-bit RISC-V)

```
R-format (Register-Register):
  [31:25] funct7 | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode
  Example: ADD rd, rs1, rs2
  funct7=0, funct3=0, opcode=51

I-format (Register-Immediate):
  [31:20] imm | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode
  Example: ADDI rd, rs1, imm
  imm is 12-bit sign-extended

S-format (Store):
  [31:25] imm[11:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] imm[4:0] | [6:0] opcode
  Example: SW rs2, offset(rs1)

B-format (Branch):
  [31] imm[12] | [30:25] imm[10:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:8] imm[4:1] | [7] imm[11] | [6:0] opcode
  Example: BEQ rs1, rs2, offset

J-format (Jump):
  [31:20] imm[19:0] | [19:15] rd | [6:0] opcode
  Example: JAL rd, offset
  imm is 20-bit sign-extended

U-format (Upper Immediate):
  [31:12] imm | [11:7] rd | [6:0] opcode
  Example: LUI rd, imm
  Loads 20-bit imm into bits [31:12] of rd

Immediate Encoding:
  All immediates are sign-extended to 32/64 bits
  ADDI rd, rs1, imm12 where imm12 ∈ [-2048, 2047]
  LUI/AUIPC load upper 20 bits, leaving lower 12 bits as 0
```

#### Instruction Set Examples (RV64I Base)

```risc-v
; 64-bit integer arithmetic
ADD x1, x2, x3          ; x1 = x2 + x3
ADDI x1, x2, 10         ; x1 = x2 + 10
SUB x1, x2, x3          ; x1 = x2 - x3
AND x1, x2, x3          ; x1 = x2 & x3
OR x1, x2, x3           ; x1 = x2 | x3
XOR x1, x2, x3          ; x1 = x2 ^ x3
SLL x1, x2, x3          ; x1 = x2 << x3
SRL x1, x2, x3          ; Logical shift right
SRA x1, x2, x3          ; Arithmetic shift right

; 32-bit arithmetic (sign-extends result to 64 bits)
ADDW x1, x2, x3         ; x1 = (int32_t)x2 + (int32_t)x3
SUBW x1, x2, x3
ADDIW x1, x2, 10

; Load/Store (M extension required for actual memory)
LD x1, 8(x2)            ; x1 = *((int64_t*)(x2 + 8))
SD x1, 8(x2)            ; *((int64_t*)(x2 + 8)) = x1
LW x1, 4(x2)            ; x1 = *((int32_t*)(x2 + 4)) (sign-extended)
SW x1, 4(x2)            ; *((int32_t*)(x2 + 4)) = x1
LWU x1, 4(x2)           ; zero-extend 32-bit load

; Branch
BEQ x1, x2, label       ; if (x1 == x2) jump to label
BNE x1, x2, label       ; if (x1 != x2) jump
BLT x1, x2, label       ; if (x1 < x2) jump [signed]
BGE x1, x2, label       ; if (x1 >= x2) jump [signed]
BLTU x1, x2, label      ; if (x1 < x2) jump [unsigned]
BGEU x1, x2, label      ; if (x1 >= x2) jump [unsigned]

; Jump
JAL x1, label           ; x1 = PC+4; jump to label
JALR x1, 0(x2)          ; x1 = PC+4; jump to x2

; Data Movement
LUI x1, 0x12345         ; x1 = 0x12345_00000000
AUIPC x1, 0x12345       ; x1 = PC + (0x12345 << 12)

; Multiply (M extension)
MUL x1, x2, x3          ; x1 = x2 * x3 (lower 64 bits)
DIV x1, x2, x3          ; x1 = x2 / x3 (signed)
REM x1, x2, x3          ; x1 = x2 % x3 (remainder)

; Floating-Point (F extension, single-precision on RV64F)
FADD.S f1, f2, f3       ; f1 = f2 + f3
FMUL.S f1, f2, f3       ; f1 = f2 * f3
FLD f1, 8(x2)           ; Load double-precision FP
FSD f1, 8(x2)           ; Store double-precision FP

; Atomic (A extension)
AMOSWAP.D x1, x2, (x3)  ; Atomic swap: x1 = [x3]; [x3] = x2
AMOADD.D x1, x2, (x3)   ; Atomic add: x1 = [x3]; [x3] += x2
```

#### RISC-V Calling Convention (ABI)

```
Argument passing (integer):
  x10-x17 (a0-a7)     ; First 8 arguments

Argument passing (floating-point):
  f10-f17 (fa0-fa7)   ; First 8 FP arguments

Return values:
  x10-x11 (a0-a1)     ; Integer return
  f10-f11 (fa0-fa1)   ; FP return

Caller-saved:
  x5-x7, x10-x17 (t0-t2, a0-a7)
  f0-f7, f10-f17 (ft0-ft7, fa0-fa7)

Callee-saved:
  x8, x9, x18-x27 (s0, s1, s2-s11)
  f8-f9, f18-f27 (fs0-fs1, fs2-fs11)

Stack alignment:
  SP % 16 == 0 (16-byte aligned)

Stack frame:
  SP -> [return address] (from JAL)
        [saved registers]
        [local variables]
```

**Example RISC-V Function:**

```risc-v
# int factorial(int n)  # n in a0 (x10)
factorial:
    ADDI sp, sp, -16        # Allocate stack space
    SD ra, 8(sp)            # Save return address
    SD s0, 0(sp)            # Save s0

    ADDI t0, zero, 1        # t0 = 1
    BLE a0, t0, .L1         # if (n <= 1) goto .L1

    MV s0, a0               # s0 = n (save n)
    ADDI a0, a0, -1         # a0 = n - 1
    JAL ra, factorial       # Call factorial(n-1)

    MUL a0, a0, s0          # a0 = result * original_n
    J .L2                   # goto cleanup

.L1:
    ADDI a0, zero, 1        # return 1

.L2:
    LD s0, 0(sp)            # Restore s0
    LD ra, 8(sp)            # Restore return address
    ADDI sp, sp, 16         # Deallocate stack
    JR ra                   # Return
```

---

## Part 2: Real-World Case Studies

### Case Study 1: Apple M4 Architecture

**Public Information (from iFixit teardowns, benchmarks):**

**Core Configuration:**
```
Performance Cores (P-cores): 4x Lion Cove
  - Out-of-order, ~6-wide superscalar
  - Private L1: 192 KB (64 KB I$, 128 KB D$)
  - Shared L2: 12 MB per 2 cores

Efficiency Cores (E-cores): 4x Skymont
  - In-order, 2-wide
  - Private L1: 128 KB (32 KB I$, 96 KB D$)
  - Shared L2: 4 MB per 2 cores

System Cache (L3):
  - 20 MB shared by all cores
  - 192 GB/s bandwidth
```

**Memory Subsystem:**
```
LPDDR5x unified memory:
  - 16, 24, or 32 GB options (M4 base)
  - Up to 120 GB/s bandwidth
  - UltraFusion interconnect (for Ultra variants)

Manufacturing:
  - TSMC N3E (3 nm equivalent, 2023)
  - ~20B transistors
  - 120 mm² die
```

**Performance Characteristics:**
```
Geekbench 6 Single-core: ~2500 (M4 base)
Geekbench 6 Multi-core: ~10,000 (4P + 4E)

Clock Frequencies:
  - P-core: up to ~3.5 GHz sustained
  - E-core: up to ~2.6 GHz

Power Budget:
  - Single-core power: ~5-8W (P-core)
  - Multi-thread power (all cores): ~20-30W sustained
  - Idle: <1W
```

**Strengths:**
- Excellent single-thread performance (custom cores, aggressive OoO).
- Unified memory (no GPU data copying).
- Very efficient (low power, high performance).
- Strong cache hierarchy (private L1/L2, shared L3).

**Limitations:**
- Proprietary (not available for third-party use).
- Limited to macOS/iOS ecosystem.
- Cannot upgrade or customize.

---

### Case Study 2: AMD Ryzen 9 9950X (Zen 5)

**Architecture:**

```
cores:
  16x Zen 5 cores (out-of-order, 4-wide superscalar)
  CCX (Core Complex): 2x 8-core modules

Cache:
  L1: 32 KB per core (I$ & D$ each)
  L2: 1 MB per core
  L3: 16 MB per CCX (32 MB total)

Manufacturing:
  - TSMC N4 (5nm equivalent, 2025)
  - Socket AM5 (LGA1718)

Memory:
  - Dual-channel DDR5-5600
  - Up to 192 GB
```

**Performance:**
```
Geekbench 6 Single-core: ~2700
Geekbench 6 Multi-core: ~21,000 (16 cores)

Clock:
  - Base: 3.7 GHz
  - Boost: up to 5.7 GHz (all-core)
  - Each core can boost independently

Power:
  - TDP: 170W
  - PBO (Precision Boost Overdrive): up to 230W
```

**Strengths:**
- Excellent multi-core performance (16 cores).
- Strong per-core IPC (improved over Zen 4).
- Flexible (DDR5, PCIe 5, upgradeable socket).
- Good thermal design (105mm cooler enough for base).

**Limitations:**
- Higher power draw than Apple M4.
- Zen 5 IPC improvement ~8% over Zen 4 (incremental).

---

### Case Study 3: Qualcomm Snapdragon X Elite (ARM-based PC)

**Architecture:**

```
Cores:
  12x Oryon cores (custom ARM, OoO, wide superscalar)
  Nuvia-derived (acquired 2024)

Cache:
  L1: 64 KB per core (I$ & D$ each)
  L2: 1 MB per core
  L3: 12 MB shared

Manufacturing:
  - TSMC N4 (5nm equivalent, 2024)
  - System-on-Chip (SoC)

GPU:
  - Adreno X1 (custom GPU)
  - ~3.8 TFLOPS FP32

NPU (Neural Processing Unit):
  - Hexagon processor
  - 45 TOPS INT8 (for AI acceleration)

Memory:
  - LPDDR5x-8448 (up to 64 GB)
```

**Performance:**
```
Geekbench 6 Single-core: ~2400
Geekbench 6 Multi-core: ~9500 (12 cores)

Clock:
  - Up to ~3.8 GHz dual-core boost
  - 4.3 GHz for quick burst

Power:
  - TDP: 12W base
  - Up to 30W sustained
  - Excellent for mobile

Battery life:
  - 20-28 hours claimed (light workload)
```

**Strengths:**
- Excellent battery life (mobile-optimized).
- Integrated NPU (AI acceleration, on-device ChatGPT).
- Fanless designs (very quiet).
- Windows ARM compatibility (Prism emulation for x86 apps).

**Limitations:**
- ARM64-only (some software still x86 only, but emulation helps).
- NPU 45 TOPS < discrete RTX 4050 (100+ TFLOPS).
- Newer ecosystem (software support still maturing).

---

## Part 3: Advanced Topics

### Speculative Execution Security

**Spectre & Meltdown (2017):**

Speculative execution allows CPUs to fetch instructions before branch resolves. If prediction wrong, results discarded. However, **cache state leaked via timing**:

```
Attacker code (attacker-controlled):
  if (secret_value == 5) {
    access_dummy_array[0]  // Millions of times to bring into cache
  }

Victim code:
  access_dummy_array[idx]

Timing attack:
  If array[0] is in cache, victim code is FAST (~4 cycles)
  If array[0] is NOT in cache, victim code is SLOW (~100+ cycles)

Attacker measures timing → deduces secret_value!
```

**Mitigations:**

1. **LFENCE (Load Fence):**
   ```asm
   ; CPU waits for all previous memory operations before executing next
   cmp rax, secret
   jne .skip
   lfence                  ; Don't speculatively execute next
   mov rcx, [array + rbx]
   .skip:
   ```

2. **RSB (Return Stack Buffer) Stuffing:**
   - Return stack can be exploited for branch prediction attacks
   - Fill with dummy returns to prevent speculation

3. **Hardware mitigations:**
   - **IBPB (Indirect Branch Predictor Barrier):** Flush predictor between privilege levels
   - **STIPB (Single Thread Indirect Branch Predictor):** Context-switch predictor
   - **MDS (Microarchitectural Data Sampling) mitigations:** Prevent leaking data from internal buffers

4. **Side-channel resistant algorithms:**
   - Avoid data-dependent branches in cryptography
   - Use constant-time operations

---

### Virtual Memory & TLB Optimization

**TLB (Translation Lookaside Buffer):**
```
Virtual Address:
  [Virtual Page Number (VPN)] [Offset within page]
  Example: 12 bits for 4 KB page offset

TLB lookup:
  VPN → check TLB → if HIT: Physical Page Number (PPN)
  → PPN + Offset = Physical Address

TLB MISS:
  Walk page tables in memory (50-500 cycles!)
  Load TLB entry
```

**Optimization Techniques:**

1. **Large Pages (Huge Pages):**
   ```
   4 KB pages: 1M+ TLB entries needed for 4 GB working set
   2 MB pages: only 2K+ TLB entries needed

   Use: Linux hugepages, THP (Transparent Huge Pages)
   ```

2. **Multi-level TLB:**
   ```
   L1 TLB: Small (64 entries), fast (1 cycle)
   L2 TLB: Larger (512 entries), slower (2-3 cycles)
   ```

3. **Page Table Prefetching:**
   - Prefetch page table entries before miss
   - Reduce miss latency

4. **ASID (Address Space IDentifier):**
   - Tag TLB entries with process ID
   - Avoid flushing TLB on context switch

---

### Memory Bandwidth & Optimization

**Memory Bandwidth Hierarchy:**

```
L1 Cache:       ~250 GB/s (custom path, 64 bytes/cycle at 4 GHz)
L2 Cache:       ~150 GB/s (wide path)
L3 Cache:       ~100 GB/s (shared by all cores)
Main Memory:    ~50-100 GB/s (DDR5-5600 dual-channel: 89 GB/s; quad-channel: 178 GB/s)
```

**Optimization Patterns:**

1. **Spatial Locality:**
   ```c
   // BAD: non-sequential access
   for (int i = 0; i < N; i++) {
       arr[i*stride] += arr[i*stride+1];  // Large stride → cache misses
   }

   // GOOD: sequential access
   for (int i = 0; i < N; i++) {
       arr[i] += arr[i+1];  // Small stride → cache hits
   }
   ```

2. **Temporal Locality:**
   ```c
   // BAD: data accessed once
   for (int i = 0; i < N; i++) {
       process(large_array[i]);
   }

   // GOOD: tile/block to keep data in cache
   for (int b = 0; b < N/TILE; b++) {
       for (int i = b*TILE; i < (b+1)*TILE; i++) {
           for (int j = 0; j < M; j++) {
               process(large_array[i], other[j]);  // reuse large_array[i] M times
           }
       }
   }
   ```

3. **Prefetching:**
   ```c
   // Explicit prefetch
   #include <xmmintrin.h>
   for (int i = 0; i < N; i++) {
       _mm_prefetch(&arr[i+8], _MM_HINT_T0);  // Prefetch arr[i+8] to L1
       process(arr[i]);
   }
   ```

---

## Further Reading & Resources

### Academic Papers

* **"Computer Architecture: A Quantitative Approach" (Hennessy & Patterson)**
  - Classic; covers all discussed topics in depth.

* **"Spectre Attacks: Exploiting Speculative Execution" (Kocher et al., 2018)**
  - First public analysis of Spectre vulnerability.

* **"Microarchitectural Memory Ordering and Determinism" (Lustig et al.)**
  - Memory consistency models and implications for concurrency.

### Open Resources

* **WikiChip / Fuse:** Community CPU database with detailed microarchitectures.
* **TechInsights / AnandTech:** Real CPU teardowns and analysis.
* **Chips & Cheese:** Microarchitecture reverse-engineering blog.
* **The ManyCore Blog:** Memory hierarchy and performance analysis.

### Tools & Simulators

* **Gem5:** Full-system CPU simulator (complex, but industry-standard).
* **SimpleScalar:** Simpler alternative for educational use.
* **Cachegrind:** Memory profiler (part of Valgrind).
* **PAPI (Performance API):** Hardware counter abstraction.
* **likwid:** Low-level performance tool for Linux.
