# Todas las operaciones de la ALU (tipo R e I) con casos borde: signo en
# slt/sra, sltu, desplazamientos de 0 y 31 bits, desborde y x0 como destino.
        addi x1, x0, -8         # x1 = 0xFFFFFFF8
        addi x2, x0, 3
        lui  x3, 0x80000        # x3 = 0x80000000 (el negativo mas chico)
        addi x4, x0, 31
        add  x5, x1, x2         # -5
        sub  x6, x2, x1         # 3 - (-8) = 11
        sll  x7, x2, x4         # 3 << 31 = 0x80000000
        srl  x8, x1, x4         # 0xFFFFFFF8 >> 31 = 1
        sra  x9, x1, x4         # -8 >>> 31 = -1
        sra  x10, x3, x2        # 0x80000000 >>> 3 = 0xF0000000
        srl  x11, x3, x2        # 0x10000000
        sll  x12, x1, x0        # desplazamiento 0
        slt  x13, x1, x2        # -8 < 3 (con signo)  -> 1
        sltu x14, x1, x2        # 0xFFFFFFF8 < 3      -> 0
        slt  x15, x2, x1        # 0
        sltu x16, x2, x1        # 1
        xor  x17, x1, x2        # 0xFFFFFFFB
        or   x18, x1, x2        # 0xFFFFFFFB
        and  x19, x1, x2        # 0
        addi x20, x1, 2047      # 2039 (inmediato maximo)
        andi x21, x1, -16       # 0xFFFFFFF0
        ori  x22, x2, -2048     # 0xFFFFF803 (inmediato minimo, con signo)
        xori x23, x1, -1        # ~x1 = 7
        slti x24, x1, -7        # -8 < -7 -> 1
        sltiu x25, x2, -1       # 3 < 0xFFFFFFFF -> 1
        slli x26, x2, 31        # 0x80000000
        srli x27, x3, 31        # 1
        srai x28, x3, 31        # 0xFFFFFFFF
        srai x29, x1, 0         # desplazamiento 0: 0xFFFFFFF8
        slli x30, x0, 5         # 0
        sub  x31, x3, x2        # 0x80000000 - 3 = 0x7FFFFFFD (desborde, sin excepcion)
        add  x0, x1, x2         # x0 como destino: sigue en 0
        halt
# Ciclos: 32 instrucciones + 4 = 36.
# ESPERADO: x0 = 0, x1 = 0xFFFFFFF8, x2 = 3, x3 = 0x80000000, x4 = 31
# ESPERADO: x5 = 0xFFFFFFFB, x6 = 11, x7 = 0x80000000, x8 = 1, x9 = 0xFFFFFFFF
# ESPERADO: x10 = 0xF0000000, x11 = 0x10000000, x12 = 0xFFFFFFF8, x13 = 1, x14 = 0
# ESPERADO: x15 = 0, x16 = 1, x17 = 0xFFFFFFFB, x18 = 0xFFFFFFFB, x19 = 0
# ESPERADO: x20 = 2039, x21 = 0xFFFFFFF0, x22 = 0xFFFFF803, x23 = 7, x24 = 1
# ESPERADO: x25 = 1, x26 = 0x80000000, x27 = 1, x28 = 0xFFFFFFFF
# ESPERADO: x29 = 0xFFFFFFF8, x30 = 0, x31 = 0x7FFFFFFD
# ESPERADO: estado = 0x01, ciclos = 36, pc = 0x84
