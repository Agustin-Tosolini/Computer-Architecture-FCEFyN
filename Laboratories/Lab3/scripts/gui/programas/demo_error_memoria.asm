# Error: acceso fuera de la memoria de datos (128 bytes: direcciones 0..127).
        li   t0, 64
        sw   t0, 124(x0)        # ultima palabra valida: mem[31] = 64
        lw   t1, 128(x0)        # fuera de rango: error en MEM; t1 no se escribe
        li   t2, 1              # NO se ejecuta
        halt
# ESPERADO: t0 = 64, t1 = 0, t2 = 0, mem[31] = 64
# ESPERADO: estado = 0x05, ciclos = 6, pc = 0x14
