# Flush: un salto se resuelve en EX; si se toma, las 2 instrucciones que ya se
# habian buscado se descartan (flush de IF/ID e ID/EX): 2 ciclos de penalidad.
        li   t0, 1
        beq  t0, x0, nunca      # NO tomado: no se pierde nada
        beq  t0, t0, salto      # tomado: se descartan las 2 siguientes
        li   t1, 111            # descartada
        li   t2, 222            # descartada
salto:  li   t3, 3
        j    fin                # j (= jal x0) tambien descarta 2
        li   t4, 444            # descartada
nunca:  li   t5, 555            # nunca se ejecuta
fin:    halt
# Ciclos: 5 instrucciones + 2 x 2 saltos tomados + 4 = 13.
# ESPERADO: t0 = 1, t1 = 0, t2 = 0, t3 = 3, t4 = 0, t5 = 0
# ESPERADO: estado = 0x01, ciclos = 13, pc = 0x28
