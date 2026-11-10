# Latencia del HALT: 5 NOPs + HALT -> o_halted = 1 despues de 9 ciclos.
# (5 NOPs + 1 ciclo en que el HALT entra a ID + 3 hasta que llega a WB.)
# Con el cpu_stub daba PC = 0x14; con el cpu real el PC queda en HALT + 4.
        nop
        nop
        nop
        nop
        nop
        halt
# ESPERADO: estado = 0x01, ciclos = 9, pc = 0x18
