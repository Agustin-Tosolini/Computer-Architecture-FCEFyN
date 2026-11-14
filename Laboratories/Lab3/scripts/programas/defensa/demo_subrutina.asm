# demo_subrutina — "Subrutina con jal / jalr" (reserva)
#
# QUE DEMUESTRA: jal guarda la direccion de retorno (PC + 4) en ra y salta;
# jalr vuelve a esa direccion. Los dos se resuelven en EX: cada uno cuesta
# 2 ciclos de flush.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   5 instrucciones ejecutadas, 0 stalls, 2 saltos tomados (jal y jalr)
#   ciclos = 5 + 4 + 2 x 2 = 13   ->   CPI = 13 / 5 = 2,6
#   a0 (x10) = 12, ra (x1) = 0x08 (la direccion del sw), mem[0] = 12
#   PC final = 0x10 (el HALT esta en 0x0C)
#
# ESPERADO: a0 = 12, ra = 0x08, mem[0] = 12
# ESPERADO: estado = 0x01, ciclos = 13, pc = 0x10
# VERIFICADO: instrucciones = 5, stalls = 0, saltos_tomados = 2, cpi = 2.6


        addi a0, x0, 6
        jal  ra, doble        # ra = direccion de retorno (PC+4); flush
        sw   a0, 0(x0)        # mem[0] = 12
        halt
doble:  add  a0, a0, a0
        jalr x0, 0(ra)        # vuelve; flush
