"""
svgdiag.py - Mini biblioteca para dibujar los diagramas de bloques con el
MISMO estilo que docs/img/B_completo.svg (colores, fuentes, puertos, buses con
su ancho en bits, circulos numerados y leyenda).

La usa diagramas.py. Coordenadas en pixeles de un lienzo de 3300 x 2330.
"""

SANS = "Liberation Sans, Arial, Helvetica, sans-serif"
MONO = "Liberation Mono, DejaVu Sans Mono, monospace"
TINTA = "#3F3E3B"        # lineas y titulos
GRIS = "#6B6862"         # nombres de puertos y textos secundarios
CABLE = "#1F1E1C"        # nombres de cables

# Paleta de B_completo: nombre -> (relleno, borde, texto)
PALETA = {
    "azul": ("#E8EFF9", "#3D5F8F", "#23426E"),       # uart / IF
    "turquesa": ("#E3F3F1", "#2B7A78", "#1A5654"),   # intf / ID
    "ambar": ("#FBF1DC", "#A9792A", "#6E4C10"),      # control_fsmd / latches
    "rojo": ("#F9ECE7", "#A2472C", "#7E2E17"),       # dump_mux / MEM
    "verde": ("#E3F4EB", "#2E7D64", "#145C47"),      # cpu / EX
    "violeta": ("#EEEAF6", "#6A5A9A", "#46397A"),    # clock y reset / WB
    "gris": ("#F3F2EF", "#7A776F", "#3F3D3A"),       # PC / control de riesgos
}

# Colores de flechas especiales
AZUL_FWD = "#2F6DB5"     # forwarding
VIOLETA_WB = "#6A5A9A"   # escritura en WB
ROJO_SALTO = "#B23B2A"   # saltos / flush
NARANJA = "#B4531A"      # circulos numerados


def esc(t):
    return (str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


class Lienzo:
    def __init__(self, ancho=3300, alto=2330):
        self.ancho, self.alto = ancho, alto
        self.el = [f'<rect width="{ancho}" height="{alto}" fill="#FFFFFF"/>']

    # -------------------------------------------------- texto
    def texto(self, x, y, t, tam=18, color=TINTA, ancla="start", negrita=False,
              italica=False, mono=False):
        estilo = (f' font-weight="{"bold" if negrita else "normal"}"' +
                  (' font-style="italic"' if italica else ""))
        self.el.append(f'<text x="{x}" y="{y}" font-family="{MONO if mono else SANS}" '
                       f'font-size="{tam}" text-anchor="{ancla}" fill="{color}"{estilo}>'
                       f'{esc(t)}</text>')

    def lineas(self, x, y, lista, tam=18, color=TINTA, ancla="start", mono=False,
               interlineado=None, **kw):
        paso = interlineado or round(tam * 1.35, 2)
        for i, t in enumerate(lista):
            self.texto(x, round(y + i * paso, 2), t, tam, color, ancla, mono=mono, **kw)

    def titulo(self, t, sub):
        self.texto(60, 72, t, 40, TINTA, negrita=True)
        self.texto(60, 112, sub, 22, GRIS)

    # -------------------------------------------------- cajas
    def caja(self, x, y, w, h, color="gris", nombre=None, sub=None, rx=14,
             punteada=False, grosor=2.5, tam_nombre=28):
        f, b, t = PALETA[color]
        dash = ' stroke-dasharray="10 7"' if punteada else ""
        self.el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
                       f'fill="{f}" stroke="{b}" stroke-width="{grosor}"{dash}/>')
        if nombre:
            self.texto(x + w / 2, y + 40, nombre, tam_nombre, t, "middle", negrita=True,
                       mono=False)
        if sub:
            self.texto(x + w / 2, y + 68, sub, 18, t, "middle", italica=True)
        return t

    def marco(self, x, y, w, h, etiqueta, nota="", claro=False):
        """Marco con solapa (como el de 'top' o 'debug_unit')."""
        borde = "#A8A49B" if claro else "#7A776F"
        fondo = "#FBFBFA" if claro else "#FFFFFF"
        self.el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" '
                       f'fill="{fondo}" stroke="{borde}" stroke-width="2.5"/>')
        ancho_tab = 30 + 15 * len(etiqueta)
        self.el.append(f'<path d="M {x} {y + 16} Q {x} {y} {x + 16} {y} L {x + ancho_tab} {y} '
                       f'L {x + ancho_tab} {y + 44} L {x} {y + 44} Z" fill="{borde}"/>')
        self.texto(x + 18, y + 31, etiqueta, 24, "#FFFFFF", negrita=True, mono=True)
        if nota:
            self.texto(x + w - 24, y + 42, nota, 18, GRIS, "end", italica=True)

    def latch(self, x, y, w, h, nombre, modulo, campos, bits):
        """Registro de pipeline: barra ambar con sus campos."""
        f, b, t = PALETA["ambar"]
        self.el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
                       f'fill="{f}" stroke="{b}" stroke-width="2.5"/>')
        # "flanco": triangulito de reloj abajo
        cx = x + w / 2
        self.el.append(f'<polyline points="{cx - 12},{y + h} {cx},{y + h - 16} {cx + 12},{y + h}" '
                       f'fill="none" stroke="{b}" stroke-width="2.2"/>')
        self.texto(cx, y + 34, nombre, 24, t, "middle", negrita=True)
        self.texto(cx, y + 58, modulo, 16, t, "middle", italica=True, mono=True)
        self.lineas(cx, y + 100, campos, 15, t, "middle", mono=True, interlineado=24)
        self.texto(cx, y + h - 30, bits, 15, t, "middle", negrita=True)

    def nota(self, x, y, lineas, color="gris", tam=17):
        t = PALETA[color][2]
        self.lineas(x, y, lineas, tam, t, italica=True)

    # -------------------------------------------------- flechas y buses
    def flecha(self, puntos, ancho=None, color=TINTA, cable=None, pos_cable=None,
               punteada=False, sin_punta=False, doble=False, grosor=None):
        """puntos: [(x, y), ...]. ancho: bits del bus (dibuja la barrita y el
        numero). cable: nombre del cable (cursiva, arriba del primer tramo)."""
        g = grosor or (4 if ancho and ancho > 1 else 2.4)
        dash = ' stroke-dasharray="9 6"' if punteada else ""
        pts = " ".join(f"{x},{y}" for x, y in puntos)
        self.el.append(f'<polyline points="{pts}" fill="none" stroke="{color}" '
                       f'stroke-width="{g}" stroke-linejoin="round"{dash}/>')
        if not sin_punta:
            self._punta(puntos[-2], puntos[-1], color)
        if doble:
            self._punta(puntos[1], puntos[0], color)
        if ancho and ancho > 1:
            (x1, y1), (x2, y2) = puntos[-2], puntos[-1]
            if y1 == y2:                                  # tramo horizontal
                mx = x2 - 33 if x2 > x1 else x2 + 33
                self.el.append(f'<line x1="{mx - 7}" y1="{y2 + 9}" x2="{mx + 7}" y2="{y2 - 9}" '
                               f'stroke="{color}" stroke-width="2.2"/>')
                self.texto(mx, y2 - 14, ancho, 17, color, "middle", mono=True)
            else:                                         # tramo vertical
                my = y2 - 40 if y2 > y1 else y2 + 40
                self.el.append(f'<line x1="{x2 - 9}" y1="{my + 7}" x2="{x2 + 9}" y2="{my - 7}" '
                               f'stroke="{color}" stroke-width="2.2"/>')
                self.texto(x2 + 14, my + 6, ancho, 17, color, mono=True)
        if cable:
            (x1, y1), (x2, y2) = puntos[0], puntos[1]
            if pos_cable:
                cx, cy = pos_cable
            elif y1 == y2:
                cx, cy = min(x1, x2) + 8, y1 - 10
            else:
                cx, cy = x1 + 8, min(y1, y2) + 24
            self.texto(cx, cy, cable, 17, CABLE if color == TINTA else color, italica=True,
                       mono=True)

    def _punta(self, a, b, color):
        (x1, y1), (x2, y2) = a, b
        if y1 == y2:
            d = 13 if x2 < x1 else -13
            pts = f"{x2},{y2} {x2 + d},{y2 - 5.9} {x2 + d},{y2 + 5.9}"
        else:
            d = 13 if y2 < y1 else -13
            pts = f"{x2},{y2} {x2 - 5.9},{y2 + d} {x2 + 5.9},{y2 + d}"
        self.el.append(f'<polygon points="{pts}" fill="{color}"/>')

    def pin(self, x, y, nombre, lado="arriba"):
        """Pin del chip: cuadradito blanco con el nombre en negrita."""
        self.el.append(f'<rect x="{x - 9}" y="{y - 9}" width="18" height="18" fill="#FFFFFF" '
                       f'stroke="{TINTA}" stroke-width="2.4"/>')
        if lado == "arriba":
            self.texto(x, y - 18, nombre, 19, TINTA, "middle", negrita=True, mono=True)
        elif lado == "izq":
            self.texto(x - 14, y - 12, nombre, 19, TINTA, "end", negrita=True, mono=True)
        else:
            self.texto(x + 14, y - 12, nombre, 19, TINTA, negrita=True, mono=True)

    def puerto(self, x, y, nombre, ancla="start"):
        self.texto(x, y, nombre, 18, GRIS, ancla, mono=True)

    def numero(self, x, y, n, r=18):
        self.el.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{NARANJA}"/>')
        self.texto(x, y + (7 if r >= 18 else 5.5), n, 21 if r >= 18 else 16, "#FFFFFF",
                   "middle", negrita=True)

    def mux(self, x, y, w, h, etiqueta, color="gris"):
        """Multiplexor: trapecio."""
        f, b, t = PALETA[color]
        self.el.append(f'<polygon points="{x},{y} {x + w},{y + 18} {x + w},{y + h - 18} '
                       f'{x},{y + h}" fill="{f}" stroke="{b}" stroke-width="2.4"/>')
        self.texto(x + w / 2, y + h / 2 + 6, etiqueta, 16, t, "middle", negrita=True, mono=True)

    def pastilla(self, x, y, t, color="violeta"):
        """Etiqueta de red global (como 'reset')."""
        f, b, tc = PALETA[color]
        w = 24 + 11 * len(t)
        self.el.append(f'<polygon points="{x},{y - 13} {x + w},{y - 13} {x + w + 14},{y} '
                       f'{x + w},{y + 13} {x},{y + 13}" fill="#FFFFFF" stroke="{b}" stroke-width="2.2"/>')
        self.texto(x + 12, y + 6, t, 18, tc, negrita=True, mono=True)

    def guardar(self, ruta):
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.ancho}" '
                    f'height="{self.alto}" viewBox="0 0 {self.ancho} {self.alto}" role="img">\n')
            f.write("\n".join(self.el))
            f.write("\n</svg>\n")
