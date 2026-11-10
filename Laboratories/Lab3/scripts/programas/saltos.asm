# beq/bne tomados y no tomados, jal/jalr (direccion de retorno) y flush de las
# instrucciones buscadas de mas. Un HALT en el camino descartado no detiene.
        addi x1, x0, 5          # 0x00
        addi x2, x0, 5          # 0x04
        beq  x1, x2, igual      # 0x08  tomado
        halt                    # 0x0C  descartado: el salto gana al HALT en ID
        addi x10, x0, 2         # 0x10  descartado
igual:  bne  x1, x2, mal        # 0x14  no tomado
        addi x3, x0, 3          # 0x18  x3 = 3
        beq  x1, x0, mal        # 0x1C  no tomado
        addi x2, x2, 1          # 0x20  x2 = 6
        bne  x1, x2, sigue      # 0x24  tomado (x2 recien calculado: forwarding)
        addi x11, x0, 1         # 0x28  descartado
mal:    addi x12, x0, 1         # 0x2C  nunca se ejecuta
        halt                    # 0x30
sigue:  jal  x4, funcion        # 0x34  x4 = 0x38 (retorno)
        addi x5, x0, 5          # 0x38  se ejecuta al volver
        j    fin                # 0x3C
        addi x13, x0, 1         # 0x40  descartado
funcion: addi x6, x4, 1         # 0x44  x6 = 0x39 (x4 por el bypass WB -> ID)
        jalr x7, 0(x6)          # 0x48  destino 0x39 & ~1 = 0x38; x7 = 0x4C
        addi x14, x0, 1         # 0x4C  descartado
fin:    addi x8, x7, 0          # 0x50  x8 = 0x4C
        halt                    # 0x54
# Ciclos: 14 instrucciones + 2 x 5 saltos tomados + 4 = 28.
# ESPERADO: x1 = 5, x2 = 6, x3 = 3, x4 = 0x38, x5 = 5, x6 = 0x39, x7 = 0x4C
# ESPERADO: x8 = 0x4C, x10 = 0, x11 = 0, x12 = 0, x13 = 0, x14 = 0
# ESPERADO: estado = 0x01, ciclos = 28, pc = 0x58
