# Loop con bne: suma 10 + 9 + ... + 1 = 55, la guarda con sw y la relee.
# Despues: load-use hacia un addi y hacia un beq (1 stall cada uno).
        addi x1, x0, 10         # contador
        addi x2, x0, 0          # suma
loop:   add  x2, x2, x1
        addi x1, x1, -1
        bne  x1, x0, loop       # tomado 9 veces, no tomado la ultima
        sw   x2, 0(x0)          # mem[0] = 55
        lw   x3, 0(x0)          # x3 = 55
        addi x4, x3, 1          # load-use (stall): x4 = 56
        lw   x5, 0(x0)          # x5 = 55
        beq  x5, x2, ok         # load-use (stall) y tomado
        addi x6, x0, 1          # NO se ejecuta (flush)
ok:     halt
# Ciclos: 37 instrucciones + 2 stalls + 2 x 10 saltos tomados + 4 = 63.
# ESPERADO: x1 = 0, x2 = 55, x3 = 55, x4 = 56, x5 = 55, x6 = 0, mem[0] = 55
# ESPERADO: estado = 0x01, ciclos = 63, pc = 0x30
