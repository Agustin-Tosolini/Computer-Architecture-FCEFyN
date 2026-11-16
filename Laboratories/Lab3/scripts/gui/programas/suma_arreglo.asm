# Suma de un arreglo: primero lo arma en memoria (3, 6, 9, ..., 24) y despues
# lo recorre con lw y lo suma. Cada lw seguido del add que lo usa es un stall.
        li   t0, 0              # direccion
        li   t1, 8              # cantidad de elementos
        li   t2, 3              # valor del elemento
armar:  sw   t2, 0(t0)
        addi t2, t2, 3
        addi t0, t0, 4
        addi t1, t1, -1
        bnez t1, armar
        li   t0, 0
        li   t1, 8
        li   a0, 0              # suma
sumar:  lw   t3, 0(t0)
        add  a0, a0, t3         # usa t3 recien cargado: 1 ciclo de stall
        addi t0, t0, 4
        addi t1, t1, -1
        bnez t1, sumar
        sw   a0, 32(x0)         # mem[8] = suma
        halt
# Ciclos: 87 instrucciones + 8 stalls + 2 x 14 saltos tomados + 4 = 127.
# ESPERADO: a0 = 108, t0 = 32, t1 = 0, t2 = 27, t3 = 24
# ESPERADO: mem[0] = 3, mem[1] = 6, mem[2] = 9, mem[3] = 12, mem[4] = 15
# ESPERADO: mem[5] = 18, mem[6] = 21, mem[7] = 24, mem[8] = 108
# ESPERADO: estado = 0x01, ciclos = 127, pc = 0x48
