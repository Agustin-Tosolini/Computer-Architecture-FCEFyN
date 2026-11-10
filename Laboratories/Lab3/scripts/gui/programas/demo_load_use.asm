# Load-use: una instruccion que usa el registro que cargo el lw INMEDIATAMENTE
# anterior espera 1 ciclo (stall): en el paso a paso el PC se repite una vez.
        li   t0, 7
        sw   t0, 0(x0)          # mem[0] = 7
        lw   t1, 0(x0)
        add  t2, t1, t1         # usa t1 apenas cargado: 1 ciclo de stall
        lw   t3, 0(x0)
        nop                     # con una instruccion en el medio NO hay stall
        add  t4, t3, t3
        halt
# Ciclos: 7 instrucciones + 1 stall + 4 = 12.
# ESPERADO: t0 = 7, t1 = 7, t2 = 14, t3 = 7, t4 = 14, mem[0] = 7
# ESPERADO: estado = 0x01, ciclos = 12, pc = 0x20
