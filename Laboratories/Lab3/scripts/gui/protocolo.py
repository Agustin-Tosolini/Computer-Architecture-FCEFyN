"""
protocolo.py - Protocolo PC <-> FPGA (src/params.vh, seccion 6) y la clase
Enlace, que lo usa sobre un "transporte" (el puerto serie real o la FPGA
simulada: los dos tienen los mismos metodos).

    Comando                                    Respuesta
    'L' + N (2 bytes, LSB primero) + N palabras little-endian   'K'
    'X'                                        'K'  (reset del procesador)
    'D'                                        volcado
    'S'                                        un ciclo + volcado
    'R'                                        corre hasta el HALT -> volcado
    'I'                                        interrumpe un 'R' (la respuesta es
                                               el volcado del 'R'); fuera de RUN
                                               se ignora

Un transporte tiene: escribir(bytes), leer(n, timeout) -> bytes (puede
devolver menos si se vence el timeout), vaciar_entrada() y cerrar().
"""
import time

from decodificador import DUMP_LEN, decodificar

BAUD = 115200
FRAME_S = 10 / BAUD                 # un byte: start + 8 datos + stop

CMD_LOAD, CMD_RESET, CMD_DUMP = b"L", b"X", b"D"
CMD_STEP, CMD_RUN, CMD_INT = b"S", b"R", b"I"
RSP_ACK = b"K"

IMEM_WORDS = 256
INSTR_HALT = 0x00000000

TIMEOUT_ACK_S = 0.5                 # 'X' -> 'K'
TIMEOUT_VOLCADO_S = 1.0             # 326 bytes a 115200 tardan ~28 ms
ESPERA_TRAS_I_S = 2.0               # despues de 'I' el volcado tiene que llegar


class ErrorProtocolo(Exception):
    """Base de los errores de comunicacion (mensajes en castellano)."""


class SinRespuesta(ErrorProtocolo):
    """La FPGA no respondio a tiempo."""


class RespuestaInvalida(ErrorProtocolo):
    """Llego algo distinto de lo esperado."""


class ErrorConexion(ErrorProtocolo):
    """El puerto se cerro o se desconecto el cable."""


def armar_carga(palabras):
    """Lista de palabras -> (palabras que se mandan, bytes del 'L', avisos).
    Recorta a 256 palabras (la FPGA descartaria el resto) y avisa que la 255
    siempre queda en HALT."""
    avisos = []
    palabras = [p & 0xFFFFFFFF for p in palabras]
    if len(palabras) > IMEM_WORDS:
        avisos.append(f"el programa tiene {len(palabras)} palabras y la memoria "
                      f"{IMEM_WORDS}: se mandan solo las primeras {IMEM_WORDS}")
        palabras = palabras[:IMEM_WORDS]
    if len(palabras) == IMEM_WORDS and palabras[-1] != INSTR_HALT:
        avisos.append("la palabra 255 se reemplaza por HALT (la ultima palabra "
                      "de la memoria siempre es HALT)")
    datos = CMD_LOAD + len(palabras).to_bytes(2, "little")
    for p in palabras:
        datos += p.to_bytes(4, "little")
    return palabras, datos, avisos


class Enlace:
    """Habla con la FPGA. Todos los metodos son bloqueantes: se llaman desde
    el hilo de comunicacion, nunca desde la interfaz.

    al_enviar / al_recibir: funciones opcionales que reciben los bytes
    (para el log en hexadecimal)."""

    def __init__(self, transporte, al_enviar=None, al_recibir=None):
        self.t = transporte
        self.al_enviar = al_enviar
        self.al_recibir = al_recibir

    # -------------------------------------------------- bajo nivel
    def _enviar(self, datos):
        self.t.escribir(datos)
        if self.al_enviar:
            self.al_enviar(bytes(datos))

    def _leer(self, n, timeout):
        """Hasta n bytes, esperando como mucho timeout segundos en total."""
        datos = b""
        limite = time.monotonic() + timeout
        while len(datos) < n:
            resto = limite - time.monotonic()
            if resto <= 0:
                break
            parte = self.t.leer(n - len(datos), min(resto, 0.1))
            if parte:
                datos += parte
                if self.al_recibir:
                    self.al_recibir(bytes(parte))
        return datos

    def _esperar_ack(self, timeout, que):
        r = self._leer(1, timeout)
        if not r:
            raise SinRespuesta(f"{que}: la FPGA no respondio (se esperaba 'K'). "
                               "¿Esta programada la placa y es el puerto correcto?")
        if r != RSP_ACK:
            raise RespuestaInvalida(f"{que}: llego 0x{r[0]:02X} en lugar de 'K' (0x4B)")

    def _recibir_volcado(self, que, timeout=TIMEOUT_VOLCADO_S):
        datos = self._leer(DUMP_LEN, timeout)
        if not datos:
            raise SinRespuesta(f"{que}: la FPGA no mando el volcado")
        if len(datos) < DUMP_LEN:
            raise RespuestaInvalida(f"{que}: llegaron {len(datos)} de {DUMP_LEN} bytes del volcado")
        return decodificar(datos)            # puede lanzar ErrorVolcado

    # -------------------------------------------------- comandos
    def reset(self):
        """'X' -> 'K'."""
        self.t.vaciar_entrada()
        self._enviar(CMD_RESET)
        self._esperar_ack(TIMEOUT_ACK_S, "Reset ('X')")

    def cargar(self, palabras):
        """'L' -> 'K'. Devuelve la lista de avisos (recortes)."""
        palabras, datos, avisos = armar_carga(palabras)
        self.t.vaciar_entrada()
        self._enviar(datos)
        self._esperar_ack(len(datos) * FRAME_S * 1.2 + 1.0, "Carga ('L')")
        return avisos

    def volcar(self):
        """'D' -> Estado."""
        self.t.vaciar_entrada()
        self._enviar(CMD_DUMP)
        return self._recibir_volcado("Volcado ('D')")

    def paso(self):
        """'S' -> Estado (despues de un ciclo)."""
        self.t.vaciar_entrada()
        self._enviar(CMD_STEP)
        return self._recibir_volcado("Paso ('S')")

    def correr(self, cancelar=None):
        """'R' -> Estado. Espera el volcado sin limite de tiempo; si el evento
        `cancelar` (threading.Event) se activa, manda 'I' y espera el volcado
        (como mucho ESPERA_TRAS_I_S). Se puede llamar a interrumpir desde otro
        hilo solo a traves de ese evento."""
        self.t.vaciar_entrada()
        self._enviar(CMD_RUN)
        datos, t_i = b"", None
        while len(datos) < DUMP_LEN:
            parte = self.t.leer(DUMP_LEN - len(datos), 0.1)
            if parte:
                datos += parte
                if self.al_recibir:
                    self.al_recibir(bytes(parte))
            if cancelar is not None and cancelar.is_set() and t_i is None:
                self._enviar(CMD_INT)
                t_i = time.monotonic()
            if t_i is not None and time.monotonic() - t_i > ESPERA_TRAS_I_S:
                raise SinRespuesta(f"Interrumpir ('I'): llegaron {len(datos)} de {DUMP_LEN} "
                                   "bytes del volcado")
        return decodificar(datos)

    def cerrar(self):
        self.t.cerrar()
