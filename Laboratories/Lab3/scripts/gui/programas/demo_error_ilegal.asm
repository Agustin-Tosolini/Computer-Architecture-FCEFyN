# Error: instruccion no soportada. MUL no esta en la consigna (el ensamblador
# la rechaza), asi que se escribe con .word. El cpu se detiene con estado 0x05
# (detenido + error): lo anterior termina, lo posterior no se ejecuta.
        li   a0, 1
        .word 0x02000033        # mul x0, x0, x0: ilegal para nuestro cpu
        li   a0, 2              # NO se ejecuta
        halt
# ESPERADO: a0 = 1, estado = 0x05, ciclos = 5, pc = 0x08
