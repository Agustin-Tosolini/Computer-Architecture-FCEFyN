# Sumas encadenadas: cada instruccion usa el resultado de la anterior.
# Prueba forwarding EX/MEM -> EX, MEM/WB -> EX, bypass WB -> ID y x0 destino.
        addi x1, x0, 1          # x1 = 1
        add  x2, x1, x1         # x2 = 2    (los dos operandos desde EX/MEM)
        add  x3, x2, x1         # x3 = 3    (rs1 desde EX/MEM, rs2 desde MEM/WB)
        add  x4, x3, x2         # x4 = 5
        add  x5, x4, x3         # x5 = 8
        add  x6, x5, x4         # x6 = 13
        addi x0, x6, 7          # escribe x0: se descarta
        add  x7, x0, x6         # x7 = 0 + 13 (x0 NO se adelanta)
        sub  x8, x1, x7         # x8 = 1 - 13 = -12
        nop
        add  x9, x8, x2         # x9 = -12 + 2 = -10   (x8 desde MEM/WB)
        nop
        nop
        add  x10, x9, x9        # x10 = -20            (x9 por el bypass WB -> ID)
        halt
# Ciclos: 14 instrucciones + 4 = 18 (sin stalls ni saltos).
# ESPERADO: x1 = 1, x2 = 2, x3 = 3, x4 = 5, x5 = 8, x6 = 13, x7 = 13
# ESPERADO: x8 = 0xFFFFFFF4, x9 = 0xFFFFFFF6, x10 = 0xFFFFFFEC, x0 = 0
# ESPERADO: estado = 0x01, ciclos = 18, pc = 0x3C
