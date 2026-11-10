# Parada por error: instruccion ilegal. Lo anterior termina, lo posterior no.
        addi x1, x0, 7          # x1 = 7
        .word 0xFFFFFFFF        # instruccion ilegal
        addi x2, x0, 99         # NO se ejecuta
        halt
# Estado 0x05 = halted (bit 0) + error (bit 2). PC = ilegal (0x04) + 4.
# ESPERADO: x1 = 7, x2 = 0, estado = 0x05, ciclos = 5, pc = 0x08
