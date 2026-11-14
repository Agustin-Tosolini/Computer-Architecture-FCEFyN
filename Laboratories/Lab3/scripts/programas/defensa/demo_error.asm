# demo_error — "Error: acceso fuera de memoria"
#
# QUE DEMUESTRA: un acceso a la direccion 128, fuera de la memoria de datos
# (0..127). El cpu se detiene con estado 0x05 (detenido + error), distinto
# de un HALT normal (0x01). El sw no escribe nada y lo que viene despues no
# se ejecuta.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   1 instruccion completa (addi); el sw falla en MEM en el ciclo 5
#   ciclos = 5; x1 = 5; estado 0x05; PC final = 0x0C (el HALT ya estaba en
#   ID cuando el sw llego a MEM, asi que el PC ya estaba congelado)
#
# ESPERADO: x1 = 5
# ESPERADO: estado = 0x05, ciclos = 5, pc = 0x0C
# VERIFICADO: instrucciones = 1, stalls = 0, saltos_tomados = 0, cpi = 5.0


        addi x1, x0, 5
        sw   x1, 128(x0)      # direccion 128: fuera de la memoria de datos (0..127)
        halt
