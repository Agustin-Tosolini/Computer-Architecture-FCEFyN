# demo_loop_infinito — "Loop infinito (interrumpir con I)"
#
# QUE DEMUESTRA: un programa que nunca llega al HALT. Correr ('R') no termina:
# la placa queda en RUN (LEDs LD1 + LD2) hasta que se manda Interrumpir ('I').
# El volcado trae estado 0x02 (interrumpido), distinto de 0x01 (HALT).
#
# RESULTADO VERIFICADO: cada vuelta es 1 instruccion + 2 ciclos de flush
# (el j se resuelve en EX), asi que el PC muestra 0x00, 0x04 o 0x08 y los
# registros y la memoria no cambian. Ciclos: los que hayan pasado hasta la 'I'.
#
# ESPERADO: estado = 0x02


loop:   j loop
