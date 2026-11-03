# Programa de cobertura IF/ID. Las salidas documentadas corresponden al top sin EX/MEM/WB.
# Una instruccion de 32 bits por linea; desactivar instrucciones comprimidas y relajacion.
.option norvc
.option norelax
.text
.globl _start
_start:
paso_01: # PC=0, mem[0], 0x04000093
    addi x1, x0, 64
paso_02: # PC=4, mem[1], 0x00300113
    addi x2, x0, 3
paso_03: # PC=8, mem[2], 0x002081B3
    add x3, x1, x2
paso_04: # PC=12, mem[3], 0x402081B3
    sub x3, x1, x2
paso_05: # PC=16, mem[4], 0x0020F1B3
    and x3, x1, x2
paso_06: # PC=20, mem[5], 0x0020E1B3
    or x3, x1, x2
paso_07: # PC=24, mem[6], 0x0020C1B3
    xor x3, x1, x2
paso_08: # PC=28, mem[7], 0x002091B3
    sll x3, x1, x2
paso_09: # PC=32, mem[8], 0x0020D1B3
    srl x3, x1, x2
paso_10: # PC=36, mem[9], 0x4020D1B3
    sra x3, x1, x2
paso_11: # PC=40, mem[10], 0x0020A1B3
    slt x3, x1, x2
paso_12: # PC=44, mem[11], 0x0020B1B3
    sltu x3, x1, x2
paso_13: # PC=48, mem[12], 0x00508193
    addi x3, x1, 5
paso_14: # PC=52, mem[13], 0x00F0F193
    andi x3, x1, 15
paso_15: # PC=56, mem[14], 0x0010E193
    ori x3, x1, 1
paso_16: # PC=60, mem[15], 0x0010C193
    xori x3, x1, 1
paso_17: # PC=64, mem[16], 0x00209193
    slli x3, x1, 2
paso_18: # PC=68, mem[17], 0x0020D193
    srli x3, x1, 2
paso_19: # PC=72, mem[18], 0x4020D193
    srai x3, x1, 2
paso_20: # PC=76, mem[19], 0x00A0A193
    slti x3, x1, 10
paso_21: # PC=80, mem[20], 0x00A0B193
    sltiu x3, x1, 10
paso_22: # PC=84, mem[21], 0x00308223
    sb x3, 4(x1)
paso_23: # PC=88, mem[22], 0x00309223
    sh x3, 4(x1)
paso_24: # PC=92, mem[23], 0x0030A223
    sw x3, 4(x1)
paso_25: # PC=96, mem[24], 0x00408183
    lb x3, 4(x1)
paso_26: # PC=100, mem[25], 0x0040C183
    lbu x3, 4(x1)
paso_27: # PC=104, mem[26], 0x00409183
    lh x3, 4(x1)
paso_28: # PC=108, mem[27], 0x0040D183
    lhu x3, 4(x1)
paso_29: # PC=112, mem[28], 0x0040A183
    lw x3, 4(x1)
paso_30: # PC=116, mem[29], 0x00208263
    beq x1, x2, paso_31
paso_31: # PC=120, mem[30], 0x00209263
    bne x1, x2, paso_32
paso_32: # PC=124, mem[31], 0x004002EF
    jal x5, paso_33
paso_33: # PC=128, mem[32], 0x08800213
    addi x4, x0, 136
paso_34: # PC=132, mem[33], 0x00020067
    jalr x0, 0(x4)
paso_35: # PC=136, mem[34], 0x123451B7
    lui x3, 0x12345
paso_36: # PC=140, mem[35], 0xFFB08193
    addi x3, x1, -5
paso_37: # PC=144, mem[36], 0x00000013
    addi x0, x0, 0
paso_38: # PC=148, mem[37], 0x00000000
    .word 0x00000000 # HALT propio
guarda_final:
    addi x0, x0, 0 # NOP observada en IF mientras HALT esta en ID
