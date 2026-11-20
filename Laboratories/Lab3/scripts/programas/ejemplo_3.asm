# Ejemplo minimo: dos addi encadenados y HALT.
# El segundo addi usa x1 del ciclo anterior (forwarding EX/MEM -> EX).
        addi x1, x0, 5          # x1 = 5
        addi x2, x1, 3          # x2 = 5 + 3 = 8
        halt
# Ciclos: 2 instrucciones + 4 (llenado y vaciado) = 6. PC = HALT (0x08) + 4.
# ESPERADO: x1 = 5, x2 = 8, estado = 0x01, ciclos = 6, pc = 0x0C
