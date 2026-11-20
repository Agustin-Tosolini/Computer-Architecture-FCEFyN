# demo_sin_halt — "Programa sin HALT"
#
# QUE DEMUESTRA: la pregunta de la consigna "¿que pasa si no hay instruccion de
# parada?". No hay halt en el programa, pero termina igual: el comando 'L'
# escribe HALT (0x00000000) en todas las palabras que no usa el programa
# (estado CLEAR de la debug unit), y la palabra 255 siempre es HALT.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   2 instrucciones ejecutadas; el HALT de relleno esta en 0x08
#   ciclos = 2 + 4 = 6   ->   CPI = 6 / 2 = 3 (casi todo es llenar y vaciar)
#   x1 = 1, x2 = 2; estado 0x01 (HALT); PC final = 0x0C
#
# ESPERADO: x1 = 1, x2 = 2
# ESPERADO: estado = 0x01, ciclos = 6, pc = 0x0C
# VERIFICADO: instrucciones = 2, stalls = 0, saltos_tomados = 0, cpi = 3.0


        addi x1, x0, 1
        addi x2, x0, 2        # sin halt: termina igual por el CLEAR de 'L'
