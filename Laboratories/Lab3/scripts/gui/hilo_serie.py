"""
hilo_serie.py - Toda la comunicacion con la FPGA pasa por aca, en un hilo
aparte: la interfaz NUNCA espera al puerto serie.

    Interfaz (hilo principal)                Trabajador (este modulo, otro hilo)
      pedir_paso.emit()  ───── señal ─────►  paso(): enlace.paso() (bloquea aca)
                         ◄──── señal ──────  volcado.emit(estado, "S")

Las señales de Qt que cruzan de un hilo a otro se encolan: cada slot del
Trabajador corre en SU hilo, de a uno por vez y en orden, asi nunca se mezclan
dos respuestas de la FPGA.

La unica excepcion es interrumpir(): se llama directo desde la interfaz
(mientras el trabajador esta ocupado esperando el volcado del 'R') y solo
activa un threading.Event que el bucle de Enlace.correr() mira cada 0,1 s.
"""
import logging
import threading

from PySide6.QtCore import QObject, Signal, Slot

from decodificador import ErrorVolcado
from fpga_simulada import FpgaSimulada
from protocolo import Enlace, ErrorConexion, ErrorProtocolo
from transporte import PuertoSerie

log = logging.getLogger("depurador")

MODO_PLACA, MODO_SIMULADO = "Placa", "Simulado"


class Trabajador(QObject):
    # Hacia la interfaz
    conectado = Signal(str)                  # descripcion ("/dev/ttyUSB1", "FPGA simulada")
    desconectado = Signal(str)               # motivo ("" = lo pidio el usuario)
    volcado = Signal(object, str)            # (Estado, comando que lo genero)
    ack = Signal(str, list)                  # (comando, avisos) para 'L' y 'X'
    error = Signal(str)                      # mensaje para el usuario
    ocupado = Signal(bool)                   # hay un comando en curso
    corriendo = Signal(bool)                 # hay un 'R' en curso
    bytes_tx = Signal(bytes)
    bytes_rx = Signal(bytes)

    def __init__(self):
        super().__init__()
        self.enlace = None
        self.transporte = None
        self._cancelar = threading.Event()

    # -------------------------------------------------- conexion
    @Slot(str, str)
    def conectar(self, modo, puerto):
        self.desconectar_silencioso()
        try:
            if modo == MODO_SIMULADO:
                self.transporte, desc = FpgaSimulada(), "FPGA simulada (modo demo)"
            else:
                self.transporte, desc = PuertoSerie(puerto), puerto
            self.enlace = Enlace(self.transporte, self.bytes_tx.emit, self.bytes_rx.emit)
            self.conectado.emit(desc)
        except ErrorProtocolo as e:
            self.enlace = self.transporte = None
            self.error.emit(str(e))
            self.desconectado.emit(str(e))

    @Slot()
    def desconectar(self):
        self.desconectar_silencioso()
        self.desconectado.emit("")

    def desconectar_silencioso(self):
        if self.enlace is not None:
            self.enlace.cerrar()
        self.enlace = self.transporte = None

    # -------------------------------------------------- comandos
    def _ejecutar(self, que, funcion):
        """Corre funcion() avisando ocupado/libre y convirtiendo los errores en
        señales (nunca una excepcion sin atrapar en este hilo)."""
        if self.enlace is None:
            self.error.emit(f"{que}: no hay conexion")
            return None
        self.ocupado.emit(True)
        try:
            return funcion()
        except ErrorConexion as e:
            self.desconectar_silencioso()
            self.error.emit(str(e))
            self.desconectado.emit(str(e))
        except (ErrorProtocolo, ErrorVolcado) as e:
            self.error.emit(str(e))
        except Exception as e:                       # no deberia pasar: al log
            log.exception("error inesperado en el hilo de comunicacion")
            self.error.emit(f"{que}: error inesperado: {e}")
        finally:
            self.ocupado.emit(False)
        return None

    @Slot(list)
    def cargar(self, palabras):
        avisos = self._ejecutar("Cargar", lambda: self.enlace.cargar(palabras))
        if avisos is not None:
            self.ack.emit("L", avisos)

    @Slot()
    def reset(self):
        if self._ejecutar("Reset", lambda: self.enlace.reset() or True):
            self.ack.emit("X", [])

    @Slot()
    def volcar(self):
        e = self._ejecutar("Volcar", self.enlace.volcar if self.enlace else None)
        if e is not None:
            self.volcado.emit(e, "D")

    @Slot()
    def paso(self):
        e = self._ejecutar("Paso", self.enlace.paso if self.enlace else None)
        if e is not None:
            self.volcado.emit(e, "S")

    @Slot()
    def correr(self):
        self._cancelar.clear()
        self.corriendo.emit(True)
        try:
            e = self._ejecutar("Correr", lambda: self.enlace.correr(self._cancelar))
        finally:
            self.corriendo.emit(False)
        if e is not None:
            self.volcado.emit(e, "R")

    def interrumpir(self):
        """Se llama desde la interfaz (otro hilo): pide la 'I'."""
        self._cancelar.set()
