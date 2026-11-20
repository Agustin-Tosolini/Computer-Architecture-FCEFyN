# Stores de byte y media palabra seguidos de loads, con y sin signo.
# Memoria little-endian: el byte 0 de una palabra es el menos significativo.
        addi x1, x0, -1         # x1 = 0xFFFFFFFF
        sw   x1, 0(x0)          # mem[0] = 0xFFFFFFFF   (dato por forwarding)
        addi x2, x0, 0x7A
        sb   x2, 1(x0)          # mem[0] = 0xFFFF7AFF
        addi x3, x0, 0x123
        sh   x3, 2(x0)          # mem[0] = 0x01237AFF
        lui  x4, 0x89ABC
        addi x4, x4, 0x7EF      # x4 = 0x89ABC7EF
        sw   x4, 4(x0)          # mem[1] = 0x89ABC7EF
        sw   x0, 8(x0)          # inicializa mem[2] y mem[3]: la memoria de datos NO
        sw   x0, 12(x0)         # se borra con el reset (tendria datos viejos)
        sb   x4, 8(x0)          # mem[2] = 0x000000EF
        sb   x4, 11(x0)         # mem[2] = 0xEF0000EF
        sh   x4, 14(x0)         # mem[3] = 0xC7EF0000
        lb   x5, 4(x0)          # 0xEF con signo   -> 0xFFFFFFEF
        lbu  x6, 4(x0)          # 0xEF sin signo   -> 0x000000EF
        lb   x7, 1(x0)          # 0x7A (positivo)  -> 0x0000007A
        lh   x8, 6(x0)          # 0x89AB con signo -> 0xFFFF89AB
        lhu  x9, 6(x0)          # 0x89AB sin signo -> 0x000089AB
        lh   x10, 2(x0)         # 0x0123           -> 0x00000123
        lw   x11, 12(x0)        # 0xC7EF0000
        lb   x12, 11(x0)        # 0xEF             -> 0xFFFFFFEF
        add  x13, x12, x11      # load-use (stall): 0xC7EEFFEF
        sw   x13, 124(x0)       # ultima palabra: mem[31] = 0xC7EEFFEF
        lw   x14, 124(x0)
        sw   x14, 16(x0)        # load -> dato del store (stall): mem[4]
        lbu  x15, 3(x0)         # byte 3 de mem[0] = 0x01
        lhu  x16, 14(x0)        # 0xC7EF
        halt
# Ciclos: 28 instrucciones + 2 stalls + 4 = 34.
# ESPERADO: x1 = 0xFFFFFFFF, x2 = 0x7A, x3 = 0x123, x4 = 0x89ABC7EF
# ESPERADO: x5 = 0xFFFFFFEF, x6 = 0xEF, x7 = 0x7A, x8 = 0xFFFF89AB, x9 = 0x89AB
# ESPERADO: x10 = 0x123, x11 = 0xC7EF0000, x12 = 0xFFFFFFEF, x13 = 0xC7EEFFEF
# ESPERADO: x14 = 0xC7EEFFEF, x15 = 1, x16 = 0xC7EF
# ESPERADO: mem[0] = 0x01237AFF, mem[1] = 0x89ABC7EF, mem[2] = 0xEF0000EF
# ESPERADO: mem[3] = 0xC7EF0000, mem[4] = 0xC7EEFFEF, mem[31] = 0xC7EEFFEF
# ESPERADO: estado = 0x01, ciclos = 34, pc = 0x74
