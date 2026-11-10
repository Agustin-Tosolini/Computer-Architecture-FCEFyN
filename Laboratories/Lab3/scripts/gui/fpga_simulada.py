"""
fpga_simulada.py - Una FPGA "de mentira" que habla EXACTAMENTE el mismo
protocolo que la real, byte por byte (src/params.vh, seccion 6).

Sirve para:
  * el "modo demo" del depurador (usar toda la app sin la placa);
  * los tests del protocolo (tests/test_protocolo.py).

Por dentro imita a control_fsmd (la debug_unit) y, para saber que hace el
procesador, usa el modelo de referencia (scripts/rv32i_model.py): registros,
memoria de datos, PC y estado despues de cada ciclo.

Limitaciones (a proposito, documentadas en la interfaz):
  * Los LATCHES no se simulan: el volcado los manda como burbujas (patron de
    reset). Solo al terminar por HALT se manda el patron real de parada (el
    marcador del HALT en MEM/WB), que es conocido.
  * Un programa sin fin "corre" a VELOCIDAD ciclos por segundo (la placa hace
    100 millones): al llegar la 'I' se calcula el estado en ese ciclo.

Mismos metodos que transporte.PuertoSerie:
    escribir(bytes), leer(n, timeout), vaciar_entrada(), cerrar()
"""
import threading
import time

import rutas  # noqa: F401  (agrega scripts/ al path)
from rv32i_model import ejecutar
from decodificador import armar_volcado, LAT_RESET, N_MEM_WORDS
from protocolo import ErrorConexion

VELOCIDAD = 2000            # ciclos por segundo de un 'R' sin fin (simulado)
MAX_CICLOS_SIN_FIN = 200_000
IMEM_WORDS = 256


class FpgaSimulada:

    def __init__(self, retardo_byte=0.0):
        """retardo_byte: segundos por byte de respuesta (0 = instantaneo).
        Con 10/115200 se imita la velocidad real de la UART."""
        self.retardo_byte = retardo_byte
        self._salida = bytearray()
        self._cv = threading.Condition()
        self._desconectada = False
        self.imem = [0] * IMEM_WORDS               # HALT al configurar la FPGA
        self.dmem = [0] * N_MEM_WORDS              # memoria de datos (RAM)
        self._fsm = "IDLE"                         # IDLE, LOAD_LEN, LOAD_WORD, RUN
        self._acum = bytearray()
        self._n_words = 0
        self._palabras = []
        self._t_run = 0.0
        self._reset_cpu(list(self.dmem))

    # -------------------------------------------------- procesador (modelo)
    def _reset_cpu(self, mem_actual):
        """Lo que hace i_cpu_reset: PC, registros, latches, halted en 0. La
        memoria de datos NO se borra: el programa arranca con mem_actual (lo
        que quedo de antes)."""
        self.mem_reset = list(mem_actual)
        self.dmem = list(mem_actual)
        self.ciclos = 0
        self.interrumpido = False
        self._res = None
        self._horizonte = 0
        r = ejecutar(self.imem, mem_inicial=self.mem_reset,     # ¿termina?
                     verificar_estable=False)
        self.ciclos_halt = r.ciclos if r.termina else None

    def _resultado(self, k):
        """Resultado del modelo que cubre al menos k ciclos."""
        if self.ciclos_halt is not None:
            if self._res is None:
                self._res = ejecutar(self.imem, mem_inicial=self.mem_reset)
            return self._res
        if self._res is None or self._horizonte < k:
            self._horizonte = max(k, 2 * self._horizonte, 64)
            self._res = ejecutar(self.imem, max_instr=self._horizonte + 10,
                                 pasos_sin_fin=self._horizonte,
                                 mem_inicial=self.mem_reset, verificar_estable=False)
        return self._res

    def _paso_modelo(self, k):
        """(regs, mem, pc, estado) despues de k ciclos (k = 0: recien reseteado)."""
        if k == 0:
            return [0] * 32, list(self.mem_reset), 0, 0
        r = self._resultado(k)
        regs, mem, pc, st, _ = r.pasos[min(k, len(r.pasos)) - 1]
        return regs, mem, pc, st

    def _mem_ahora(self):
        return self._paso_modelo(self.ciclos)[1]

    @property
    def detenido(self):
        return self.ciclos_halt is not None and self.ciclos >= self.ciclos_halt

    def _volcado(self):
        regs, mem, pc, st = self._paso_modelo(self.ciclos)
        self.dmem = list(mem)
        estado = st | (2 if self.interrumpido else 0)
        lat = LAT_RESET
        if st == 0x01:                              # HALT normal: patron conocido
            lat = int.from_bytes(b"".join(w.to_bytes(4, "little")
                                          for w in self._resultado(self.ciclos).latches), "little")
        return armar_volcado(pc, self.ciclos, estado, regs, mem, lat)

    # -------------------------------------------------- debug_unit (control_fsmd)
    def _responder(self, datos):
        with self._cv:
            self._salida += datos
            self._cv.notify_all()

    def _byte(self, b):
        if self._fsm == "IDLE":
            c = bytes([b])
            if c == b"X":
                self._reset_cpu(self._mem_ahora())
                self._responder(b"K")
            elif c == b"L":
                self._fsm, self._acum = "LOAD_LEN", bytearray()
            elif c == b"D":
                self._responder(self._volcado())
            elif c == b"S":
                self.interrumpido = False
                if not self.detenido:
                    self.ciclos += 1
                self._responder(self._volcado())
            elif c == b"R":
                self.interrumpido = False
                if self.ciclos_halt is not None:
                    self.ciclos = max(self.ciclos, self.ciclos_halt)
                    self._responder(self._volcado())
                else:
                    self._fsm, self._t_run, self._c_run = "RUN", time.monotonic(), self.ciclos
            # cualquier otro byte (incluida 'I' fuera de RUN): se descarta
        elif self._fsm == "RUN":
            if b == ord("I"):                        # todo lo demas se ignora
                avance = int((time.monotonic() - self._t_run) * VELOCIDAD)
                self.ciclos = min(self._c_run + max(avance, 1), MAX_CICLOS_SIN_FIN)
                self.interrumpido = True
                self._fsm = "IDLE"
                self._responder(self._volcado())
        elif self._fsm == "LOAD_LEN":
            self._acum.append(b)
            if len(self._acum) == 2:
                self._n_words = int.from_bytes(self._acum, "little")
                self._palabras, self._acum = [], bytearray()
                self._fsm = "LOAD_WORD" if self._n_words else "IDLE"
                if not self._n_words:
                    self._fin_carga()
        elif self._fsm == "LOAD_WORD":
            self._acum.append(b)
            if len(self._acum) == 4:
                self._palabras.append(int.from_bytes(self._acum, "little"))
                self._acum = bytearray()
                if len(self._palabras) == self._n_words:
                    self._fsm = "IDLE"
                    self._fin_carga()

    def _fin_carga(self):
        """WRITE + CLEAR: el programa, HALT en el resto, la 255 siempre HALT;
        las palabras 256+ se descartan. Despues RESET + 'K'."""
        mem = self._mem_ahora()              # antes de cambiar el programa
        p = self._palabras[:IMEM_WORDS]
        self.imem = p + [0] * (IMEM_WORDS - len(p))
        self.imem[IMEM_WORDS - 1] = 0
        self._reset_cpu(mem)
        self._responder(b"K")

    # -------------------------------------------------- interfaz de transporte
    def escribir(self, datos):
        if self._desconectada:
            raise ErrorConexion("FPGA simulada desconectada")
        for b in bytes(datos):
            self._byte(b)

    def leer(self, n, timeout):
        if self._desconectada:
            raise ErrorConexion("FPGA simulada desconectada")
        limite = time.monotonic() + timeout
        with self._cv:
            while not self._salida:
                resto = limite - time.monotonic()
                if resto <= 0:
                    return b""
                self._cv.wait(resto)
            n = min(n, len(self._salida))
            if self.retardo_byte:
                n = min(n, max(1, int(timeout / self.retardo_byte)))
            datos = bytes(self._salida[:n])
            del self._salida[:n]
        if self.retardo_byte:
            time.sleep(self.retardo_byte * len(datos))
        return datos

    def vaciar_entrada(self):
        with self._cv:
            self._salida.clear()

    def cerrar(self):
        pass

    def desconectar(self):
        """Para probar el aviso de "cable desconectado"."""
        self._desconectada = True
