"""
transporte.py - El "cable" hacia la FPGA real: el puerto serie (pyserial).

Tiene los mismos metodos que la FPGA simulada (fpga_simulada.py), asi Enlace
no sabe con cual de los dos esta hablando:
    escribir(bytes), leer(n, timeout) -> bytes, vaciar_entrada(), cerrar()

Configuracion fija de la FPGA: 115200 baudios, 8 bits, sin paridad, 1 stop.
"""
from dataclasses import dataclass

from protocolo import BAUD, ErrorConexion

try:
    import serial
    import serial.tools.list_ports
except ImportError:              # la app avisa en la ventana; el modo simulado sigue andando
    serial = None

VID_FTDI = 0x0403                # el puente USB-UART de la Basys 3 es un FTDI


@dataclass
class InfoPuerto:
    dispositivo: str             # /dev/ttyUSB1, COM5...
    descripcion: str
    recomendado: bool            # parece la UART de la Basys 3


def listar_puertos():
    """Puertos serie disponibles, con el de la Basys 3 marcado. La placa
    aparece como DOS puertos FTDI (interfaz 0 = JTAG, interfaz 1 = UART): se
    recomienda la interfaz 1 o, si no se sabe, el de numero mas alto."""
    if serial is None:
        return []
    puertos = sorted(serial.tools.list_ports.comports(), key=lambda p: p.device)
    ftdi = [p for p in puertos if p.vid == VID_FTDI]
    elegido = None
    for p in ftdi:
        if (p.location or "").endswith(".1"):          # ...:1.1 = interfaz 1
            elegido = p.device
    if elegido is None and ftdi:
        elegido = ftdi[-1].device
    return [InfoPuerto(p.device, p.description or "", p.device == elegido) for p in puertos]


class PuertoSerie:
    """Puerto serie real. Cualquier error de pyserial se convierte en
    ErrorConexion (con un mensaje claro), por ejemplo si se desconecta el cable."""

    def __init__(self, dispositivo):
        if serial is None:
            raise ErrorConexion("falta pyserial: instalar las dependencias (scripts/gui/requirements.txt)")
        try:
            self.ser = serial.serial_for_url(dispositivo, baudrate=BAUD, bytesize=8,
                                             parity="N", stopbits=1, timeout=0.1)
        except (serial.SerialException, OSError, ValueError) as e:
            raise ErrorConexion(f"no se pudo abrir {dispositivo}: {e}. ¿Puerto correcto? "
                                "¿Otro programa lo esta usando? ¿Permiso (grupo dialout)?") from e
        self.dispositivo = dispositivo

    def escribir(self, datos):
        try:
            self.ser.write(datos)
            self.ser.flush()
        except (serial.SerialException, OSError) as e:
            raise ErrorConexion(f"se perdio la conexion con {self.dispositivo}: {e}") from e

    def leer(self, n, timeout):
        try:
            self.ser.timeout = timeout
            return self.ser.read(n)
        except (serial.SerialException, OSError, TypeError) as e:
            # TypeError: pyserial a veces lo lanza cuando el USB desaparece.
            raise ErrorConexion(f"se perdio la conexion con {self.dispositivo}: {e}") from e

    def vaciar_entrada(self):
        try:
            self.ser.reset_input_buffer()
        except (serial.SerialException, OSError) as e:
            raise ErrorConexion(f"se perdio la conexion con {self.dispositivo}: {e}") from e

    def cerrar(self):
        try:
            self.ser.close()
        except Exception:        # al cerrar no importa si ya estaba roto
            pass
