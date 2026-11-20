# Fibonacci: guarda F(0)..F(10) en mem[0..10] con un loop (bnez) y deja F(10)
# en a0, leyendo la memoria con lw. Usa pseudo-instrucciones (li, mv, bnez).
        li   t0, 0              # F(i)
        li   t1, 1              # F(i+1)
        li   t2, 11             # cuantos valores faltan
        li   t3, 0              # direccion donde se guarda F(i)
bucle:  sw   t0, 0(t3)          # mem[i] = F(i)
        add  t4, t0, t1         # F(i+2)
        mv   t0, t1
        mv   t1, t4
        addi t3, t3, 4
        addi t2, t2, -1
        bnez t2, bucle          # tomado 10 veces
        lw   a0, 40(x0)         # a0 = mem[10] = F(10)
        halt
# Ciclos: 82 instrucciones + 2 x 10 saltos tomados + 4 = 106.
# ESPERADO: a0 = 55, t0 = 89, t1 = 144, t2 = 0, t3 = 44, t4 = 144
# ESPERADO: mem[0] = 0, mem[1] = 1, mem[2] = 1, mem[3] = 2, mem[4] = 3, mem[5] = 5
# ESPERADO: mem[6] = 8, mem[7] = 13, mem[8] = 21, mem[9] = 34, mem[10] = 55
# ESPERADO: estado = 0x01, ciclos = 106, pc = 0x34
