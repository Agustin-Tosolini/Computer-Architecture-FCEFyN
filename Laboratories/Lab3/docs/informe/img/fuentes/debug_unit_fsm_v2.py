"""
debug_unit_fsm_v2.py - Diagrama de estados de control_fsmd (version 2).

Genera docs/informe/img/debug_unit_fsm_v2.svg. A diferencia de la v1, separa
visualmente lo Moore de lo Mealy:

  - Estado MOORE (rectangulo, borde simple, azul): todas sus salidas dependen
    solo del estado. Las salidas van ADENTRO del recuadro, despues de "->".
  - Estado MEALY (esquinas redondeadas, borde doble, ambar): al menos una
    salida depende tambien de las entradas. Esas salidas van SOBRE LA FLECHA,
    despues de la condicion y de "->". Si el estado tiene ademas salidas Moore
    (ACK, DUMP), van adentro como en un estado Moore.
  - [ ... ] en gris monoespaciado: registros del datapath que se cargan en el
    flanco (no son salidas de la FSM).

Fuente de verdad: src/debug_unit/control_fsmd.v
Uso:  python3 debug_unit_fsm_v2.py
"""

import os

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(os.path.dirname(AQUI), "debug_unit_fsm_v2.svg")

SANS = "Liberation Sans, Arial, Helvetica, sans-serif"
MONO = "DejaVu Sans Mono, Liberation Mono, monospace"

ANCHO, ALTO = 2940, 2640

TINTA = "#2E2D2A"        # condiciones y nombres
GRIS = "#6B6862"         # acciones sobre registros
LINEA = "#8A8985"        # flechas

# Moore: azul.  Mealy: ambar.
MOORE = dict(relleno="#E8EFF9", borde="#3D5F8F", titulo="#23426E", salida="#1F5FAF")
MEALY = dict(relleno="#FBF1DC", borde="#A9792A", titulo="#6E4C10", salida="#B5530C")

T_COND = 28      # tamano de condiciones
T_ACC = 23       # tamano de acciones [..]
INTERLINEA = 34


def esc(t):
    return str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


el = []


# --------------------------------------------------------------------- texto
def seg_svg(texto, estilo):
    """Un tramo de una linea de etiqueta."""
    if estilo == "cond":
        return f'<tspan fill="{TINTA}">{esc(texto)}</tspan>'
    if estilo == "mealy":
        return (f'<tspan fill="{MEALY["salida"]}" font-weight="bold">'
                f'{esc(texto)}</tspan>')
    if estilo == "moore":
        return (f'<tspan fill="{MOORE["salida"]}" font-weight="bold">'
                f'{esc(texto)}</tspan>')
    if estilo in ("acc", "acc_chico"):
        tam = T_ACC if estilo == "acc" else T_ACC - 2
        return (f'<tspan fill="{GRIS}" font-family="{MONO}" '
                f'font-size="{tam}">{esc(texto)}</tspan>')
    raise ValueError(estilo)


def etiqueta(x, y, lineas, ancla="start"):
    """lineas: lista de lineas; cada linea es str (condicion) o lista de
    (texto, estilo). Estilos: cond, mealy, acc."""
    for i, linea in enumerate(lineas):
        if isinstance(linea, str):
            linea = [(linea, "cond")]
        tramos = "".join(seg_svg(t, e) for t, e in linea)
        el.append(f'<text x="{x}" y="{y + i * INTERLINEA}" font-size="{T_COND}" '
                  f'text-anchor="{ancla}">{tramos}</text>')


def C(t):
    return (t, "cond")


def M(t):
    return ("  → " + t, "mealy")


def A(t):
    return ("[" + t + "]", "acc")


# ------------------------------------------------------------------- estados
ESTADOS = {}


def estado(nombre, cx, cy, tipo, moore=(), w=440, h=180):
    p = MOORE if tipo == "moore" else MEALY
    x, y = cx - w / 2, cy - h / 2
    ESTADOS[nombre] = (cx, cy, w, h)
    if tipo == "moore":
        el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" '
                  f'fill="{p["relleno"]}" stroke="{p["borde"]}" stroke-width="4"/>')
    else:
        el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="40" '
                  f'fill="{p["relleno"]}" stroke="{p["borde"]}" stroke-width="3"/>')
        el.append(f'<rect x="{x + 9}" y="{y + 9}" width="{w - 18}" height="{h - 18}" '
                  f'rx="31" fill="none" stroke="{p["borde"]}" stroke-width="1.5"/>')
    # pastilla con el tipo
    rotulo = "MOORE" if tipo == "moore" else "MEALY"
    pw = 104
    el.append(f'<rect x="{cx - pw / 2}" y="{y + 18}" width="{pw}" height="28" rx="14" '
              f'fill="{p["borde"]}"/>')
    el.append(f'<text x="{cx}" y="{y + 39}" font-size="19" font-weight="bold" '
              f'letter-spacing="2" text-anchor="middle" fill="#FFFFFF">{rotulo}</text>')
    el.append(f'<text x="{cx}" y="{y + 92}" font-size="40" font-weight="bold" '
              f'text-anchor="middle" fill="{p["titulo"]}">{esc(nombre)}</text>')
    if moore:
        for i, s in enumerate(moore):
            el.append(f'<text x="{cx}" y="{y + 134 + i * 33}" font-size="26" '
                      f'font-weight="bold" text-anchor="middle" fill="{MOORE["salida"]}">'
                      f'{esc(s)}</text>')
    else:
        el.append(f'<text x="{cx}" y="{y + 136}" font-size="24" font-style="italic" '
                  f'text-anchor="middle" fill="{GRIS}">(sin salidas Moore)</text>')


def borde(nombre, lado, desplazamiento=0):
    """Punto sobre el borde de un estado. desplazamiento: a lo largo del lado."""
    cx, cy, w, h = ESTADOS[nombre]
    if lado == "arriba":
        return (cx + desplazamiento, cy - h / 2)
    if lado == "abajo":
        return (cx + desplazamiento, cy + h / 2)
    if lado == "izq":
        return (cx - w / 2, cy + desplazamiento)
    if lado == "der":
        return (cx + w / 2, cy + desplazamiento)
    raise ValueError(lado)


# ------------------------------------------------------------------- flechas
def punta(tip, desde):
    (x2, y2), (x1, y1) = tip, desde
    dx, dy = x2 - x1, y2 - y1
    n = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / n, dy / n
    L, W = 22, 12
    bx, by = x2 - ux * L, y2 - uy * L
    p1 = (bx - uy * W, by + ux * W)
    p2 = (bx + uy * W, by - ux * W)
    el.append(f'<polygon points="{p1[0]:.1f},{p1[1]:.1f} {x2:.1f},{y2:.1f} '
              f'{p2[0]:.1f},{p2[1]:.1f}" fill="{LINEA}"/>')


def flecha(*puntos, con_punta=True):
    pts = list(puntos)
    if con_punta:
        # acortar el ultimo tramo para que la linea no asome por la punta
        (x1, y1), (x2, y2) = pts[-2], pts[-1]
        dx, dy = x2 - x1, y2 - y1
        n = (dx * dx + dy * dy) ** 0.5
        fin = (x2 - dx / n * 2, y2 - dy / n * 2)
        linea = pts[:-1] + [(x2 - dx / n * 18, y2 - dy / n * 18)]
    else:
        linea = pts
    s = " ".join(f"{x:.1f},{y:.1f}" for x, y in linea)
    el.append(f'<polyline points="{s}" fill="none" stroke="{LINEA}" '
              f'stroke-width="4" stroke-linejoin="round"/>')
    if con_punta:
        punta(fin, pts[-2])


def lazo(p0, c1, c2, p3):
    """Auto-transicion: curva de Bezier cubica con punta en p3."""
    el.append(f'<path d="M {p0[0]} {p0[1]} C {c1[0]} {c1[1]}, {c2[0]} {c2[1]}, '
              f'{p3[0]} {p3[1]}" fill="none" stroke="{LINEA}" stroke-width="4"/>')
    punta(p3, c2)


# ===================================================================== dibujo
el.append(f'<rect width="{ANCHO}" height="{ALTO}" fill="#FFFFFF"/>')

IZQ, MED = 700, 1420
RUN_X, STEP_X, DUMP_X = 2000, 2560, 2180
F0, F1, F2, F3, F4 = 210, 640, 1080, 1500, 1920
DER1, DER2 = 2870, 2870

estado("IDLE", MED, F0, "mealy", w=480)
estado("LOAD_LEN", IZQ, F1, "mealy")
estado("LOAD_WORD", IZQ, F2, "mealy")
estado("WRITE", IZQ, F3, "moore", w=520, h=214,
       moore=("→ imem_we = (idx < 256)", "→ imem_data = word",
              "(HALT si idx = 255)"))
estado("CLEAR", IZQ, F4, "moore", w=500,
       moore=("→ imem_we = 1, imem_data = HALT",))
estado("RESET", MED, F3, "moore", moore=("→ cpu_reset = 1",))
estado("ACK", MED, F4, "mealy", moore=("→ w_data = 'K'",))
estado("RUN", RUN_X, F1, "mealy", w=480)
estado("STEP", STEP_X, F1, "moore", w=420, moore=("→ cpu_enable = 1",))
estado("DUMP", DUMP_X, F2, "mealy", w=480,
       moore=("→ w_data = dump_mux[dump_idx]",))

# ---------------------------------------------------------------- reset global
el.append(f'<circle cx="{MED}" cy="44" r="18" fill="#111"/>')
flecha((MED, 64), borde("IDLE", "arriba"))
el.append(f'<text x="{MED + 28}" y="52" font-size="24" fill="{TINTA}">reset global</text>')

# ---------------------------------------------------------------------- IDLE
ix0 = MED - 240
lazo((ix0 + 70, 120), (ix0 + 40, 10), (ix0 + 210, 10), (ix0 + 180, 120))
etiqueta(ix0 + 20, 70, [[C("otro byte (incluida 'I')"), M("rd")]], ancla="end")

# 'L'
p = borde("IDLE", "izq", 30)
flecha(p, (IZQ, p[1]), borde("LOAD_LEN", "arriba"))
etiqueta(IZQ + 16, 390, [[C("'L'"), M("rd")], [A("byte_cnt ← 0")]])

# 'X'
flecha(borde("IDLE", "abajo"), borde("RESET", "arriba"))
etiqueta(MED - 16, 1250, [[C("'X'"), M("rd")]], ancla="end")

# 'R'
p = borde("IDLE", "der", 30)
flecha(p, (RUN_X, p[1]), borde("RUN", "arriba"))
etiqueta(RUN_X - 16, 380, [[C("'R'"), M("rd")], [A("interrupted ← 0")]],
         ancla="end")

# 'S'
p = borde("IDLE", "der", -30)
flecha(p, (STEP_X, p[1]), borde("STEP", "arriba"))
etiqueta(STEP_X + 16, 380, [[C("'S'"), M("rd")], [A("interrupted ← 0")]])

# 'D'
p = borde("IDLE", "abajo", 160)
q = borde("DUMP", "izq", 20)
flecha(p, (p[0], q[1]), q)
etiqueta(p[0] + 16, 960, [[C("'D'"), M("rd")], [A("dump_idx ← 0")]])

# ------------------------------------------------------------------ LOAD_LEN
cx, cy, w, h = ESTADOS["LOAD_LEN"]
xr = cx + w / 2
lazo((xr, cy - 40), (xr + 170, cy - 90), (xr + 170, cy + 90), (xr + 2, cy + 40))
etiqueta(xr + 150, cy - 6, [[C("1.er byte"), M("rd")], [A("N[7:0] ← byte")]])

# LOAD_LEN -> LOAD_WORD
flecha(borde("LOAD_LEN", "abajo"), borde("LOAD_WORD", "arriba"))
etiqueta(IZQ + 16, 820, [[C("2.º byte y N ≠ 0"), M("rd")],
                         [A("N[15:8] ← byte, idx ← 0")]])

# LOAD_LEN -> CLEAR (N = 0)
p = borde("LOAD_LEN", "izq", 20)
q = borde("CLEAR", "izq", 20)
flecha(p, (80, p[1]), (80, q[1]), q)
etiqueta(96, 740, ["2.º byte y", [C("N = 0"), M("rd")], [A("idx ← 0")]])

# ----------------------------------------------------------------- LOAD_WORD
cx, cy, w, h = ESTADOS["LOAD_WORD"]
xr = cx + w / 2
lazo((xr, cy - 40), (xr + 170, cy - 90), (xr + 170, cy + 90), (xr + 2, cy + 40))
etiqueta(xr + 140, cy - 6, [[C("byte 1, 2 o 3"), M("rd")],
                             [("[word ← {byte, word[31:8]}]", "acc_chico")]])

# LOAD_WORD -> WRITE
flecha(borde("LOAD_WORD", "abajo"), borde("WRITE", "arriba"))
etiqueta(IZQ + 16, 1250, [[C("4.º byte"), M("rd")],
                          [A("word ← {byte, word[31:8]}")]])

# --------------------------------------------------------------------- WRITE
# faltan palabras -> LOAD_WORD
p = borde("WRITE", "izq", 0)
q = borde("LOAD_WORD", "izq", 20)
flecha(p, (300, p[1]), (300, q[1]), q)
etiqueta(284, 1270, ["faltan", "palabras", [A("idx++")]], ancla="end")

# ultima y N < 256 -> CLEAR
flecha(borde("WRITE", "abajo"), borde("CLEAR", "arriba"))
etiqueta(IZQ + 16, 1700, ["última y N < 256", [A("idx++")]])

# ultima y N >= 256 -> RESET
p = borde("WRITE", "der", -30)
flecha(p, (borde("RESET", "izq")[0], p[1]))
etiqueta((p[0] + borde("RESET", "izq")[0]) / 2, p[1] - 16,
         ["última y N ≥ 256"], ancla="middle")

# --------------------------------------------------------------------- CLEAR
cx, cy, w, h = ESTADOS["CLEAR"]
yb = cy + h / 2
lazo((cx - 40, yb), (cx - 110, yb + 150), (cx + 110, yb + 150), (cx + 40, yb + 2))
etiqueta(cx, yb + 170, [[C("idx < 255  "), A("idx++")]], ancla="middle")

# idx = 255 -> RESET
p = borde("CLEAR", "der", -20)
q = borde("RESET", "izq", 50)
flecha(p, (1090, p[1]), (1090, q[1]), q)
etiqueta(1074, 1760, ["idx = 255"], ancla="end")

# ------------------------------------------------------------- RESET / ACK
flecha(borde("RESET", "abajo"), borde("ACK", "arriba"))
etiqueta(MED + 16, 1700, ["siempre (1 ciclo)",
                          [A("cycles ← 0, interrupted ← 0")]])

# ACK -> IDLE (por la derecha, se une a la vuelta de DUMP)
p = borde("ACK", "der", 0)
flecha(p, (DER1, p[1]), (DER1, borde("DUMP", "der", 40)[1]), con_punta=False)
etiqueta(p[0] + 30, p[1] - 16, [[C("!tx_full"), M("wr")]])

# ----------------------------------------------------------------------- RUN
cx, cy, w, h = ESTADOS["RUN"]
yt = cy - h / 2
xr = cx + w / 2
lazo((cx + 140, yt), (cx + 140, yt - 110), (xr + 110, cy - 20), (xr + 2, cy - 20))
etiqueta(cx + 70, yt - 160, [[C("!halted y no llega 'I'")],
                             [M("cpu_enable")],
                             [M("rd si llegó otro byte")]])

# RUN -> DUMP: 'I'
p = borde("RUN", "abajo", -40)
flecha(p, (p[0], borde("DUMP", "arriba")[1]))
etiqueta(p[0] - 16, 790, [[C("!halted y 'I'")],
                          [M("cpu_enable, rd")],
                          [A("interrupted ← 1")],
                          [A("dump_idx ← 0")]], ancla="end")

# RUN -> DUMP: halted
p = borde("RUN", "abajo", 120)
flecha(p, (p[0], borde("DUMP", "arriba")[1]))
etiqueta(p[0] + 16, 830, ["halted", [A("dump_idx ← 0")]])

# ---------------------------------------------------------------------- STEP
p = borde("STEP", "abajo", 0)
q = borde("DUMP", "der", -20)
flecha(p, (p[0], q[1]), q)
etiqueta(p[0] + 16, 830, ["siempre (1 ciclo)", [A("dump_idx ← 0")]])

# ---------------------------------------------------------------------- DUMP
cx, cy, w, h = ESTADOS["DUMP"]
yb = cy + h / 2
lazo((cx - 40, yb), (cx - 110, yb + 150), (cx + 110, yb + 150), (cx + 40, yb + 2))
etiqueta(cx, yb + 170, [[C("!tx_full y quedan bytes"), M("wr")],
                        [A("dump_idx++")]], ancla="middle")

# DUMP -> IDLE (ultimo byte)
p = borde("DUMP", "der", 40)
llegada = borde("IDLE", "arriba", 190)
flecha(p, (DER1, p[1]), (DER1, 24), (llegada[0], 24), llegada)
etiqueta(DER1 - 16, p[1] + 50, [[C("!tx_full y último byte"), M("wr")],
                                [A("dump_idx ← 0")]], ancla="end")

# ==================================================================== leyenda
Y0 = 2230
el.append(f'<line x1="60" y1="{Y0}" x2="{ANCHO - 60}" y2="{Y0}" stroke="#DDDAD3" '
          f'stroke-width="2"/>')
el.append(f'<text x="60" y="{Y0 + 50}" font-size="32" font-weight="bold" '
          f'fill="{TINTA}">Cómo leer el diagrama</text>')

# muestras de estado
def muestra(x, y, tipo, texto):
    p = MOORE if tipo == "moore" else MEALY
    if tipo == "moore":
        el.append(f'<rect x="{x}" y="{y}" width="150" height="64" rx="4" '
                  f'fill="{p["relleno"]}" stroke="{p["borde"]}" stroke-width="4"/>')
    else:
        el.append(f'<rect x="{x}" y="{y}" width="150" height="64" rx="22" '
                  f'fill="{p["relleno"]}" stroke="{p["borde"]}" stroke-width="3"/>')
        el.append(f'<rect x="{x + 7}" y="{y + 7}" width="136" height="50" rx="16" '
                  f'fill="none" stroke="{p["borde"]}" stroke-width="1.5"/>')
    el.append(f'<text x="{x + 75}" y="{y + 42}" font-size="22" font-weight="bold" '
              f'letter-spacing="2" text-anchor="middle" fill="{p["titulo"]}">'
              f'{tipo.upper()}</text>')
    etiqueta(x + 175, y + 28, texto)


muestra(60, Y0 + 80, "moore", [
    "Todas sus salidas dependen solo del estado.",
    [("Se escriben ADENTRO:  ", "cond"),
     ("→ cpu_reset = 1", "moore")],
])
muestra(1480, Y0 + 80, "mealy", [
    "Alguna salida depende también de las entradas.",
    [("Se escribe SOBRE LA FLECHA:  ", "cond"),
     ("condición", "cond"), ("  → rd", "mealy")],
])

etiqueta(60, Y0 + 220, [
    [("Flecha:  ", "cond"), ("condición que provoca el cambio", "cond"),
     ("  → salidas Mealy (valen 1 solo en ese ciclo)", "mealy"),
     ("    ", "cond"), ("[registros que se cargan en el flanco]", "acc")],
    "• 'L', 'X', 'S'… = llegó un byte (!rx_empty) y vale ese carácter.   "
    "rd = leer el byte de rx_intf.   wr = escribir w_data en tx_intf.",
    "• Si no se cumple ninguna condición, la FSM se queda: las salidas Mealy "
    "valen 0 (no lee ni escribe) y las Moore se mantienen. Las salidas no "
    "escritas valen 0.",
    "• Siempre: imem_addr = idx[7:0];  cycles++ en cada ciclo con "
    "cpu_enable y !halted.   En RUN, si 'I' y halted llegan juntos, gana halted.",
    "• Carga: la palabra 255 siempre es HALT; con N > 256 las palabras 256+ "
    "se leen pero no se escriben (imem_we = 0). CLEAR pone HALT en N..255.",
])


def main():
    cuerpo = "\n".join(el)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{ANCHO}" height="{ALTO}" '
           f'viewBox="0 0 {ANCHO} {ALTO}" font-family="{SANS}">\n{cuerpo}\n</svg>\n')
    with open(SALIDA, "w", encoding="utf-8") as f:
        f.write(svg)
    print("generado:", os.path.relpath(SALIDA, os.path.dirname(AQUI)))


if __name__ == "__main__":
    main()
