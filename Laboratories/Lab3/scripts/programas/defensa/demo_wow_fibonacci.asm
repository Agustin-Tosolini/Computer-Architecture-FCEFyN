# demo_wow_fibonacci — "Wow: Fibonacci en memoria"
#
# QUE DEMUESTRA: un programa real que llena las 32 palabras de la memoria de
# datos con la serie de Fibonacci: F(0) = 0 ... F(31) = 1346269. En el loop hay
# forwarding MEM/WB -> EX (addi x2, x5, 0) y EX/MEM -> EX hacia la comparacion
# del bne (usa el x3 recien calculado): forwarding -> ALU -> decision del salto
# -> proximo PC, el camino critico del diseno.
#
# RESULTADO VERIFICADO (modelo de referencia = RTL):
#   196 instrucciones ejecutadas (4 + 32 vueltas x 6), 0 stalls,
#   31 saltos tomados (la vuelta 32 no salta)
#   ciclos = 196 + 4 + 2 x 31 = 262   ->   CPI = 262 / 196 = 1,34
#   x1 = F(32) = 2178309, x2 = x5 = F(33) = 3524578, x3 = x4 = 128
#   mem[i] = F(i) para i = 0..31 (mem[31] = 1346269); PC final = 0x2C (HALT + 4)
#
# ESPERADO: x1 = 2178309, x2 = 3524578, x3 = 128, x4 = 128, x5 = 3524578
# ESPERADO: mem[0] = 0, mem[1] = 1, mem[2] = 1, mem[3] = 2, mem[4] = 3, mem[5] = 5
# ESPERADO: mem[6] = 8, mem[7] = 13, mem[8] = 21, mem[9] = 34, mem[10] = 55, mem[11] = 89
# ESPERADO: mem[12] = 144, mem[13] = 233, mem[14] = 377, mem[15] = 610, mem[16] = 987, mem[17] = 1597
# ESPERADO: mem[18] = 2584, mem[19] = 4181, mem[20] = 6765, mem[21] = 10946, mem[22] = 17711, mem[23] = 28657
# ESPERADO: mem[24] = 46368, mem[25] = 75025, mem[26] = 121393, mem[27] = 196418, mem[28] = 317811, mem[29] = 514229
# ESPERADO: mem[30] = 832040, mem[31] = 1346269
# ESPERADO: estado = 0x01, ciclos = 262, pc = 0x2C
# VERIFICADO: instrucciones = 196, stalls = 0, saltos_tomados = 31, cpi = 1.34


        addi x1, x0, 0        # f(n)
        addi x2, x0, 1        # f(n+1)
        addi x3, x0, 0        # direccion actual
        addi x4, x0, 128      # fin: 32 palabras * 4 bytes
loop:   sw   x1, 0(x3)        # mem[i] = f(i)
        add  x5, x1, x2       # f(n+2)
        addi x1, x2, 0        # avanzar (mv x1, x2)
        addi x2, x5, 0        # avanzar (mv x2, x5)  <- forwarding MEM/WB
        addi x3, x3, 4
        bne  x3, x4, loop     # <- forwarding EX/MEM al comparador del salto
        halt
