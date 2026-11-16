# Loop sin fin: cuenta para siempre (no hay HALT que se alcance).
# 'R' (Correr) no termina nunca: hay que cortarlo con Interrumpir ('I', Esc);
# el volcado trae estado 0x02. t0 muestra cuantas vueltas dio.
        li   t0, 0
bucle:  addi t0, t0, 1
        j    bucle
# ESPERADO: estado = 0x02
