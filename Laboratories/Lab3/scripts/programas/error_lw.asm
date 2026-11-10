# Parada por error: lw fuera de la memoria de datos (128 bytes: 0..127).
        addi x1, x0, 42
        sw   x1, 124(x0)        # ultima palabra valida: mem[31] = 42
        lw   x2, 128(x0)        # fuera de rango: error en MEM, x2 no se escribe
        addi x3, x0, 1          # NO se ejecuta
        addi x4, x0, 1          # NO se ejecuta
        halt
# Estado 0x05. El PC ya busco 3 instrucciones despues del lw: 0x08 + 12.
# ESPERADO: x1 = 42, x2 = 0, x3 = 0, x4 = 0, mem[31] = 42
# ESPERADO: estado = 0x05, ciclos = 6, pc = 0x14
