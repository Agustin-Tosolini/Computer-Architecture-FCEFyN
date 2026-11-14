# demo_signo — "Con signo y sin signo" (reserva)
#
# QUE DEMUESTRA: lb extiende el signo y lbu completa con ceros; srai copia el
# bit de signo y srli mete ceros. Respuesta a "¿que diferencia hay entre ...?".
# CAMBIO respecto de la propuesta: se agrego "sw x0, 0(x0)" antes del sb,
# porque la memoria de datos (RAM) NO se borra al reprogramar: sin eso, los
# bytes 1 a 3 de mem[0] tendrian lo que dejo el programa anterior.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   8 instrucciones, 0 stalls, 0 saltos; ciclos = 8 + 4 = 12; CPI = 1,5
#   x1 = 0xFFFFFFFF (-1), x2 = 0xFFFFFFFF (-1), x3 = 0xFF (255),
#   x4 = 0xFFFFFFF0 (-16), x5 = 0xFFFFFFFC (-4), x6 = 0x3FFFFFFC
#   mem[0] = 0x000000FF; PC final = 0x24
#
# ESPERADO: x1 = 0xFFFFFFFF, x2 = 0xFFFFFFFF, x3 = 255, x4 = 0xFFFFFFF0
# ESPERADO: x5 = 0xFFFFFFFC, x6 = 0x3FFFFFFC, mem[0] = 0xFF
# ESPERADO: estado = 0x01, ciclos = 12, pc = 0x24
# VERIFICADO: instrucciones = 8, stalls = 0, saltos_tomados = 0, cpi = 1.5


        addi x1, x0, -1       # 0xFFFFFFFF
        sw   x0, 0(x0)        # mem[0] = 0 (la RAM no se borra al reprogramar)
        sb   x1, 0(x0)        # mem[0] = 0x000000FF
        lb   x2, 0(x0)        # x2 = -1          (extiende el signo)
        lbu  x3, 0(x0)        # x3 = 255         (rellena con ceros)
        addi x4, x0, -16
        srai x5, x4, 2        # x5 = -4          (desplazamiento aritmetico)
        srli x6, x4, 2        # x6 = 0x3FFFFFFC  (desplazamiento logico)
        halt
