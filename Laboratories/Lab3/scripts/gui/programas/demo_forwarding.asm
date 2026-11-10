# Forwarding: cada instruccion usa el resultado de la anterior SIN esperar.
# Mirar paso a paso los latches: el dato llega a EX desde EX/MEM o MEM/WB.
        li   t0, 10             # t0 = 10
        addi t1, t0, 5          # t1 = 15  (t0 desde EX/MEM)
        add  t2, t1, t0         # t2 = 25  (t1 desde EX/MEM, t0 desde MEM/WB)
        sub  t3, t2, t1         # t3 = 10
        sw   t3, 0(x0)          # mem[0] = 10 (el dato del store tambien se adelanta)
        halt
# Sin forwarding habria que esperar 2 ciclos entre cada par; aca: 5 + 4 = 9 ciclos.
# ESPERADO: t0 = 10, t1 = 15, t2 = 25, t3 = 10, mem[0] = 10
# ESPERADO: estado = 0x01, ciclos = 9, pc = 0x18
