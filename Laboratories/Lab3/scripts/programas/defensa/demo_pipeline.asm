# demo_pipeline — "Recorrido del pipeline (paso a paso)"
#
# QUE DEMUESTRA, una cosa por bloque: forwarding EX/MEM y MEM/WB, bypass del
# banco de registros, load-use (stall de 1 ciclo), salto no tomado (sin costo)
# y salto tomado (flush de 2 instrucciones). Usar Paso (F10) desde la carga.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   15 instrucciones ejecutadas, 1 stall, 1 salto tomado
#   ciclos = 15 + 4 + 1 + 2 x 1 = 22   ->   CPI = 22 / 15 = 1,47
#   x1 = 5, x2 = 10, x3 = 7, x4 = 14, x5 = 9, x6 = 18, x7 = 10, x8 = 20, x12 = 3
#   x10 = x11 = 0 (descartadas por el flush); mem[0] = 10; PC final = 0x48
#
# PASOS (Paso = cantidad de 'S' desde la carga; la vista muestra el estado
# DESPUES de ese paso). Verificados con pipeline_view.py en el modo simulado:
#   Paso  Que se ve
#   3     add x2,x1,x1 en EX: flecha EX/MEM -> EX (rs1 y rs2 = x1 = 5)
#   6     add x4,x3,x3 en EX: flecha MEM/WB -> EX (rs1 y rs2 = x3 = 7)
#   9     add x6,x5,x5 en ID y addi x5 en WB: bypass WB -> ID (sin flecha;
#         lo dice la nota de ID)
#   12    lw x7 en EX y add x8,x7,x7 en ID: cartel STALL en el proximo paso
#   13    burbuja (stall) en EX; IF e ID no cambiaron (el PC se repite)
#   14    add x8 en EX: flecha MEM/WB -> EX (x7 = 10, recien leido)
#   15    beq en EX: salto no tomado, sin flush
#   16    bne en EX, tomado: cartel FLUSH; IF e ID en naranja (x10, x11)
#   17    burbujas (flush) en ID y EX; IF ya busca addi x12 (0x40)
#   22    HALT en WB: procesador detenido (19: HALT en ID, deja de buscar)
#
# PASO 3  fwd_exmem
# PASO 6  fwd_memwb
# PASO 14 fwd_memwb
# PASO 9  bypass
# PASO 12 stall
# PASO 13 burbuja_stall
# PASO 15 beq_no_tomado
# PASO 16 flush
# PASO 17 burbuja_flush
# PASO 19 halt_en_id
# PASO 22 detenido
#
# ESPERADO: x1 = 5, x2 = 10, x3 = 7, x4 = 14, x5 = 9, x6 = 18, x7 = 10, x8 = 20
# ESPERADO: x10 = 0, x11 = 0, x12 = 3, mem[0] = 10
# ESPERADO: estado = 0x01, ciclos = 22, pc = 0x48
# VERIFICADO: instrucciones = 15, stalls = 1, saltos_tomados = 1, cpi = 1.47


# --- A. Forwarding EX/MEM -> EX (dependencia inmediata)
        addi x1, x0, 5        # x1 = 5
        add  x2, x1, x1       # x2 = 10   (x1 desde EX/MEM)
# --- B. Forwarding MEM/WB -> EX (a distancia 2)
        addi x3, x0, 7        # x3 = 7
        nop
        add  x4, x3, x3       # x4 = 14   (x3 desde MEM/WB)
# --- C. A distancia 3 no hace falta forwarding: bypass del banco de registros
        addi x5, x0, 9
        nop
        nop
        add  x6, x5, x5       # x6 = 18   (WB escribe y ID lee en el mismo ciclo)
# --- D. Load-use: 1 ciclo de stall
        sw   x2, 0(x0)        # mem[0] = 10
        lw   x7, 0(x0)        # x7 = 10
        add  x8, x7, x7       # x8 = 20   (STALL + forwarding MEM/WB)
# --- E. Salto NO tomado: sin penalidad
        beq  x1, x2, salto    # 5 != 10 -> sigue
# --- F. Salto tomado: flush de 2 instrucciones
        bne  x1, x2, salto    # 5 != 10 -> salta
        addi x10, x0, 111     # se descarta
        addi x11, x0, 222     # se descarta
salto:  addi x12, x0, 3       # x12 = 3
        halt
