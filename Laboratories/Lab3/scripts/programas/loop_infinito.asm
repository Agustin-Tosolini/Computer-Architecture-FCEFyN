# Programa sin fin: despues de dos instrucciones, un salto a si mismo (j .).
# 'R' corre para siempre; 'I' lo corta y el volcado trae estado = 0x02.
        addi x1, x0, 3
        sw   x1, 8(x0)          # mem[2] = 3
fin:    j    fin
# ESPERADO: x1 = 3, mem[2] = 3, estado = 0x02
