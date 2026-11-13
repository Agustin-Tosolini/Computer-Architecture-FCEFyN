#!/usr/bin/env python3
"""
diagramas.py - Genera los diagramas de la documentacion con el mismo estilo que
docs/informe/img/B_completo.svg:

    docs/informe/img/CPU_completo.svg        datapath del cpu (5 etapas, latches, riesgos)
    docs/informe/img/sistema_completo.svg    PC (parte C) <-> UART <-> debug_unit <-> cpu

    python3 docs/informe/img/fuentes/diagramas.py
    (si esta PySide6, por ejemplo con scripts/gui/.venv/bin/python, tambien
     genera los .png)

Los numeros que aparecen (tamanos, ciclos, offsets) salen del codigo y de los
tests; si cambian, hay que cambiarlos aca.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgdiag import (AZUL_FWD, GRIS, Lienzo, PALETA, ROJO_SALTO, TINTA,  # noqa: E402
                     VIOLETA_WB)

IMG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # docs/informe/img


# ============================================================== CPU
def cpu():
    L = Lienzo(alto=2200)
    L.titulo("CPU RISC-V RV32I — pipeline de 5 etapas",
             "src/cpu/cpu.v: módulos, registros de pipeline (latches), forwarding, stall, "
             "flush, HALT e interfaz de debug.")
    L.marco(60, 160, 3180, 1500, "cpu", "cpu.v — clock único i_clk; step = i_enable && "
            "!o_halted habilita todo el estado")

    # ---------------------------------------------------- etapas
    etapas = [("1 · IF", "búsqueda", 100, 600, "azul"),
              ("2 · ID", "decodificación", 830, 1290, "turquesa"),
              ("3 · EX", "ejecución", 1540, 2190, "verde"),
              ("4 · MEM", "memoria de datos", 2420, 2780, "rojo"),
              ("5 · WB", "escritura", 3010, 3210, "violeta")]
    for nombre, desc, x0, x1, c in etapas:
        f, b, t = PALETA[c]
        L.el.append(f'<rect x="{x0}" y="226" width="{x1 - x0}" height="40" rx="8" '
                    f'fill="{f}" stroke="{b}" stroke-width="2"/>')
        L.texto((x0 + x1) / 2, 254, f"{nombre}  {desc}", 22, t, "middle", negrita=True)

    # ---------------------------------------------------- latches
    L.latch(640, 290, 150, 860, "IF/ID", "if_id", ["pc", "instr", "valid"],
            "65 bits")
    L.latch(1330, 290, 170, 860, "ID/EX", "id_ex",
            ["pc", "rs1_data", "rs2_data", "imm", "rs1 rs2 rd", "funct3, bit30",
             "controles (16)", "halt illegal", "valid"], "163 bits")
    L.latch(2230, 290, 150, 860, "EX/MEM", "ex_mem",
            ["result", "store_data", "rd, funct3", "controles", "halt illegal", "valid"],
            "79 bits")
    L.latch(2820, 290, 150, 860, "MEM/WB", "mem_wb",
            ["result", "mem_data", "rd", "controles", "halt illegal", "valid"], "74 bits")

    # ---------------------------------------------------- IF
    L.caja(230, 370, 130, 80, "azul", "+4", None, punteada=True, tam_nombre=26)
    L.mux(130, 520, 60, 150, "mux", "azul")
    L.caja(220, 530, 150, 130, "azul", "pc_reg", "PC (bytes)")
    L.caja(390, 700, 200, 200, "azul", "instr_mem", "256 × 32")
    L.lineas(490, 800, ["lectura asinc.", "RAM distribuida"], 16, PALETA["azul"][2],
             "middle", mono=True)
    L.caja(390, 930, 200, 120, "azul", None, None, punteada=True)
    L.lineas(490, 962, ["fetch fuera de", "rango o impar →", "0xFFFFFFFF (ilegal)"], 15,
             PALETA["azul"][2], "middle", mono=True)
    L.flecha([(190, 595), (220, 595)])                                  # mux -> pc_reg
    L.flecha([(295, 530), (295, 450)])                                  # pc -> +4
    L.flecha([(230, 410), (100, 410), (100, 560), (130, 560)], cable="PC+4",
             pos_cable=(108, 400))
    L.flecha([(370, 595), (640, 595)], 32, cable="pc", pos_cable=(390, 585))
    L.flecha([(490, 595), (490, 700)], 8, cable="PC[9:2]", pos_cable=(500, 650))
    L.flecha([(590, 800), (640, 800)], 32)
    L.texto(596, 826, "instr", 17, "#1F1E1C", italica=True, mono=True)
    # carga desde debug
    L.flecha([(520, 1180), (520, 1050)], cable=None)
    L.lineas(400, 1120, ["i_imem_we/addr/data", "(carga 'L': solo con", " i_enable = 0)"], 15,
             GRIS, mono=True)

    # ---------------------------------------------------- ID
    tc = PALETA["turquesa"][2]
    L.caja(860, 320, 400, 160, "turquesa", "control_unit", None)
    L.lineas(1060, 400, ["opcode · funct3 · funct7 → controles",
                         "0x00000000 = HALT · otra no soportada = ilegal"], 16, tc, "middle",
             mono=True)
    L.caja(860, 530, 400, 280, "turquesa", "reg_file", "x0…x31 · 32 × 32 (flip-flops)")
    L.lineas(1060, 640, ["2 lecturas (rs1, rs2) asinc.", "1 escritura (WB, flanco)",
                         "bypass WB → ID", "x0 = 0 siempre (también debug)"], 16, tc, "middle",
             mono=True)
    L.caja(860, 860, 310, 140, "turquesa", "imm_gen", None)
    L.lineas(1015, 935, ["formatos I·S·B·U·J", "signo extendido", "(B y J: bit 0 = 0)"],
             16, tc, "middle", mono=True)
    L.flecha([(790, 400), (860, 400)], 32)
    L.flecha([(790, 600), (860, 600)], 5, cable="rs1", pos_cable=(798, 624))
    L.flecha([(790, 680), (860, 680)], 5, cable="rs2", pos_cable=(798, 704))
    L.flecha([(790, 930), (860, 930)], 32)
    L.flecha([(1260, 400), (1330, 400)], 16, cable="ctrl", pos_cable=(1266, 424))
    L.flecha([(1260, 600), (1330, 600)], 32)
    L.flecha([(1260, 680), (1330, 680)], 32)
    L.flecha([(1170, 930), (1330, 930)], 32)
    L.flecha([(790, 1080), (1330, 1080)], cable="pc · rd · rs1 · rs2 · funct3 · bit30 (pasan)",
             pos_cable=(820, 1068))

    # ---------------------------------------------------- EX
    tv = PALETA["verde"][2]
    L.mux(1560, 560, 50, 120, "A", "verde")
    L.mux(1560, 720, 50, 120, "B", "verde")
    L.mux(1680, 560, 50, 120, "a", "verde")
    L.mux(1680, 720, 50, 120, "b", "verde")
    L.caja(1790, 560, 180, 280, "verde", "alu", None)
    L.lineas(1880, 650, ["+ − << >> >>>", "and or xor", "slt sltu", "→ zero"], 16, tv,
             "middle", mono=True)
    L.caja(1790, 400, 180, 120, "verde", None, None)
    L.texto(1880, 445, "alu_control", 20, tv, "middle", negrita=True, mono=True)
    L.lineas(1880, 478, ["ALUOp + funct3", "+ bit30 → op"], 15, tv, "middle", mono=True)
    L.mux(2030, 620, 50, 140, "res", "verde")
    L.caja(1640, 900, 360, 160, "rojo", None, None, punteada=True)
    L.texto(1820, 935, "saltos (lógica en cpu.v)", 20, PALETA["rojo"][2], "middle",
            negrita=True)
    L.lineas(1820, 965, ["beq/bne: zero · jal/jalr: siempre",
                         "destino = PC+imm | (rs1+imm)&~1",
                         "redirect → PC nuevo + flush"], 16, PALETA["rojo"][2],
             "middle", mono=True)
    L.flecha([(1500, 460), (1790, 460)], cable="alu_op, funct3, bit30", pos_cable=(1520, 448))
    L.flecha([(1500, 600), (1560, 600)], 32, cable="rs1", pos_cable=(1506, 626))
    L.flecha([(1500, 760), (1560, 760)], 32)
    L.texto(1506, 786, "rs2", 17, "#1F1E1C", italica=True, mono=True)
    L.flecha([(1610, 620), (1680, 620)])
    L.flecha([(1610, 780), (1680, 780)])
    L.flecha([(1500, 930), (1520, 930), (1520, 880), (1705, 880), (1705, 840)], 32,
             cable="imm", pos_cable=(1528, 870))
    L.flecha([(1730, 620), (1790, 620)])
    L.flecha([(1730, 780), (1790, 780)])
    L.flecha([(1970, 690), (2030, 690)], 32)
    L.flecha([(2080, 690), (2230, 690)], 32, cable="ex_result", pos_cable=(2088, 716))
    L.flecha([(1635, 780), (1635, 860), (2200, 860), (2200, 780), (2230, 780)], 32,
             cable="store_data", pos_cable=(2090, 850))
    L.flecha([(1500, 1080), (2055, 1080), (2055, 760)], cable="PC+4",
             pos_cable=(2064, 1065))
    # salto -> PC (rojo, por arriba)
    L.flecha([(2000, 980), (2010, 980), (2010, 205), (80, 205), (80, 640), (130, 640)],
             color=ROJO_SALTO, cable="target + redirect", pos_cable=(1700, 197))

    # ---------------------------------------------------- MEM
    tr = PALETA["rojo"][2]
    L.caja(2450, 560, 300, 250, "rojo", "data_mem", "32 × 32 · 128 bytes")
    L.lineas(2600, 660, ["sb/sh/sw por byte", "lb lh lw lbu lhu", "fuera de 0..127 →",
                         "error (o_fault)", "RAM: el reset no la borra"], 15, tr, "middle",
             mono=True)
    L.flecha([(2380, 690), (2450, 690)], 32, cable="addr", pos_cable=(2388, 716))
    L.flecha([(2380, 780), (2450, 780)], 32, cable="wdata", pos_cable=(2388, 806))
    L.flecha([(2750, 700), (2820, 700)], 32, cable="rdata", pos_cable=(2756, 726))
    L.flecha([(2380, 880), (2820, 880)], 32, cable="result (no pasa por la RAM)",
             pos_cable=(2470, 868))

    # ---------------------------------------------------- WB
    L.mux(3060, 650, 60, 290, "wb", "violeta")
    L.flecha([(2970, 700), (3060, 700)], 32, cable="mem_data", pos_cable=(2976, 726))
    L.flecha([(2970, 880), (3060, 880)], 32, cable="result", pos_cable=(2976, 906))
    L.texto(3135, 640, "result_src", 15, PALETA["violeta"][2], "middle", mono=True)
    L.flecha([(3120, 795), (3180, 795), (3180, 1260), (1220, 1260), (1220, 810)],
             32, color=VIOLETA_WB, cable="wb_data · rd · reg_write  →  escribe el banco (flanco)",
             pos_cable=(1180, 1250))

    # ---------------------------------------------------- forwarding (azul)
    L.flecha([(2400, 690), (2400, 1200), (1575, 1200), (1575, 840)], color=AZUL_FWD,
             cable="EX/MEM.result → A/B", pos_cable=(1990, 1190))
    L.flecha([(1600, 1260), (1600, 840)], color=AZUL_FWD)
    L.texto(1610, 1240, "wb_data → A/B", 17, AZUL_FWD, italica=True, mono=True)

    # ---------------------------------------------------- unidades de riesgos y control
    tg = PALETA["gris"][2]
    L.caja(640, 1320, 640, 170, "gris", "hazard_unit", None, tam_nombre=24)
    L.lineas(960, 1395, ["load-use: congela PC e IF/ID + burbuja en ID/EX (1 ciclo)",
                         "salto tomado: flush de IF/ID e ID/EX (2 ciclos)",
                         "→ pc_write · if_id_write · if_id_flush · id_ex_flush"], 16, tg,
             "middle", mono=True)
    L.caja(1330, 1320, 640, 170, "gris", "forwarding_unit", None, tam_nombre=24)
    L.lineas(1650, 1395, ["rs1/rs2 de EX contra rd de EX/MEM y MEM/WB",
                          "rd ≠ 0 · prioridad EX/MEM · load en MEM no",
                          "→ forward_a/b: 00 ID/EX · 10 EX/MEM · 01 WB"], 16, tg, "middle",
             mono=True)
    L.caja(2020, 1320, 620, 170, "violeta", "HALT y errores", None, punteada=True,
           tam_nombre=24)
    L.lineas(2330, 1395, ["HALT/ilegal en ID: deja de buscar (PC = HALT+4)",
                          "o_halted = MEM/WB.valid && halt  (9 ciclos*)",
                          "o_fault = o_halted && illegal"], 16, PALETA["violeta"][2], "middle",
             mono=True)
    L.caja(2690, 1320, 520, 170, "violeta", "clock enable", None, punteada=True,
           tam_nombre=24)
    L.lineas(2950, 1395, ["step = i_enable && !o_halted",
                          "PC, latches, banco, escritura de",
                          "datos y halting: solo con step"], 16, PALETA["violeta"][2], "middle",
             mono=True)
    L.texto(2030, 1520, "* con 5 NOPs + HALT: o_halted = 1 después de exactamente 9 ciclos "
            "habilitados (N + 4).", 17, GRIS, italica=True)

    # ---------------------------------------------------- abajo: contrato, volcado, leyenda
    L.texto(60, 1730, "Interfaz de debug (contrato, src/params.vh §4)", 26, TINTA, negrita=True)
    for i, (k, v) in enumerate([
            ("Control", "i_clk · i_cpu_reset (PC, latches, registros, halted, fault;"),
            ("", "NO las memorias) · i_enable (clock enable)"),
            ("Carga", "i_imem_we · i_imem_addr[7:0] · i_imem_data[31:0]"),
            ("", "(solo con i_enable = 0)"),
            ("Lecturas", "i_dbg_reg_addr[4:0] → o_dbg_reg_data[31:0] (x0 = 0)"),
            ("", "i_dbg_mem_addr[7:0] → o_dbg_mem_data[31:0] (asincrónicas)"),
            ("Estado", "o_pc[31:0] · o_halted · o_fault · o_latches[479:0]")]):
        L.texto(60, 1775 + 30 * i, k, 18, TINTA, negrita=True)
        L.texto(180, 1775 + 30 * i, v, 18, TINTA, mono=True)

    L.texto(1500, 1730, "Latches en el volcado: 480 bits = 15 palabras", 26, TINTA, negrita=True)
    filas = [("IF/ID", "65", "96", "12–14"), ("ID/EX", "163", "192", "6–11"),
             ("EX/MEM", "79", "96", "3–5"), ("MEM/WB", "74", "96", "0–2")]
    cols = (1500, 1680, 1860, 2060)
    for j, h in enumerate(("latch", "bits reales", "en el volcado", "palabras")):
        L.texto(cols[j], 1775, h, 18, TINTA, negrita=True)
    for i, fila in enumerate(filas):
        for j, v in enumerate(fila):
            L.texto(cols[j], 1805 + 30 * i, v, 18, TINTA, mono=True)
    L.lineas(1500, 1955 + 10, ["Cada latch ocupa palabras enteras (relleno en 0).",
                          "Burbuja: valid = 0 (IF/ID guarda NOP, nunca HALT).",
                          "Tabla campo por campo: src/params.vh §4b."], 17, GRIS, italica=True)

    L.texto(2560, 1730, "Cómo leer el diagrama", 26, TINTA, negrita=True)
    ley = [(TINTA, "datos y controles que avanzan"), (AZUL_FWD, "forwarding hacia EX"),
           (VIOLETA_WB, "escritura en WB (y bypass a ID)"), (ROJO_SALTO, "salto: nuevo PC + flush")]
    for i, (c, t) in enumerate(ley):
        y = 1775 + 34 * i
        L.flecha([(2560, y - 6), (2640, y - 6)], color=c)
        L.texto(2660, y, t, 18, TINTA)
    f, b, _ = PALETA["ambar"]
    L.el.append(f'<rect x="2560" y="1905" width="80" height="26" rx="5" fill="{f}" stroke="{b}" '
                f'stroke-width="2"/>')
    L.texto(2660, 1925, "registro de pipeline (flanco de i_clk)", 18, TINTA)
    L.el.append(f'<rect x="2560" y="1945" width="80" height="26" rx="5" fill="#FFFFFF" '
                f'stroke="{GRIS}" stroke-width="2" stroke-dasharray="8 5"/>')
    L.texto(2660, 1965, "punteado: lógica escrita dentro de cpu.v", 18, TINTA)
    L.flecha([(2560, 2000), (2640, 2000)], 32)
    L.texto(2660, 2006, "bus y su ancho en bits", 18, TINTA)

    L.texto(60, 2010, "Números clave", 26, TINTA, negrita=True)
    L.lineas(60, 2055, [
        "ciclos = instrucciones + 4 + stalls + 2 × saltos tomados     (CPI ideal = 1)",
        "load-use: 1 ciclo de stall · salto tomado (beq/bne/jal/jalr): 2 ciclos de penalidad",
        "memoria de programa 256 × 32 (1 KiB) · memoria de datos 32 × 32 (128 bytes)",
        "error (0x05): instrucción ilegal, fetch fuera de rango/desalineado, acceso inválido a datos",
    ], 18, TINTA, mono=True, interlineado=30)
    return L


# ============================================================== SISTEMA COMPLETO
def sistema():
    L = Lienzo(alto=1950)
    L.titulo("Sistema completo — PC (parte C) ↔ UART ↔ Debug Unit (parte B) ↔ cpu (parte A)",
             "Qué corre en la PC, qué viaja por el cable y qué hay en la FPGA. "
             "Los números salen del código (src/params.vh y los tests).")

    # ---------------------------------------------------- PC
    L.marco(40, 160, 1240, 1320, "PC", "Python 3 · scripts/ (Linux Mint)", claro=True)
    tg = PALETA["gris"][2]
    tvi = PALETA["violeta"][2]
    L.caja(90, 240, 1140, 380, "violeta", "Depurador gráfico (GUI)",
           "scripts/gui/depurador.py · app/")
    L.lineas(660, 345, ["editor · listado · registros · memoria · latches · log",
                        "Cargar (L) · Reset (X) · Paso (S) · Correr (R) · Interrumpir (I) · Volcar (D)"],
             17, tvi, "middle", mono=True)
    for x, nombre, color, lin in (
            (110, "ensamblador.py", "turquesa", [".asm → palabras", "etiquetas, pseudo-instr."]),
            (490, "decodificador.py", "rojo", ["326 bytes → Estado", "latches campo por campo"]),
            (870, "desensamblador.py", "ambar", ["palabra → texto", "(listado, latches)"])):
        L.caja(x, 420, 340, 170, color, None, None)
        L.texto(x + 170, 460, nombre, 21, PALETA[color][2], "middle", negrita=True, mono=True)
        L.lineas(x + 170, 500, lin, 16, PALETA[color][2], "middle", mono=True)
    L.caja(90, 690, 540, 160, "gris", "hilo_serie.py", "Trabajador en un QThread")
    L.lineas(360, 790, ["la ventana nunca espera al puerto", "pedidos y respuestas por señales"],
             16, tg, "middle", mono=True)
    L.caja(690, 690, 540, 160, "gris", "protocolo.py", "clase Enlace")
    L.lineas(960, 790, ["cargar · reset · paso · correr · volcar", "timeouts y errores claros"],
             16, tg, "middle", mono=True)
    L.caja(90, 910, 540, 180, "verde", "fpga_simulada.py", "modo demo, sin placa")
    L.lineas(360, 1010, ["habla el mismo protocolo", "byte a byte"], 16, PALETA["verde"][2],
             "middle", mono=True)
    L.caja(690, 910, 540, 180, "azul", "transporte.py", "PuertoSerie (pyserial)")
    L.lineas(960, 1010, ["115200 8N1 · /dev/ttyUSB1", "★ = la Basys 3 (FTDI)"], 16,
             PALETA["azul"][2], "middle", mono=True)
    L.caja(90, 1160, 540, 170, "ambar", "rv32i_model.py", "modelo de referencia")
    L.lineas(360, 1255, ["ISA + tiempos del pipeline", "valores esperados de los tests"], 16,
             PALETA["ambar"][2], "middle", mono=True)
    L.caja(690, 1160, 540, 170, "gris", None, None, punteada=True)
    L.texto(960, 1205, "uart_test.py", 22, tg, "middle", negrita=True, mono=True)
    L.lineas(960, 1245, ["la misma comunicación por consola", "modos x · l · d · s · r · step"],
             16, tg, "middle", mono=True)
    L.lineas(110, 1400, ["Tests: 883 pytest (scripts/gui/tests) · testbenches autoverificados ·",
                         "pruebas de mutación (scripts/run_all_tests.sh, scripts/mutaciones.py)."],
             17, GRIS, italica=True)
    # flechas internas PC
    L.flecha([(360, 620), (360, 690)], doble=True, cable="señales", pos_cable=(372, 662))
    L.flecha([(630, 770), (690, 770)])
    L.flecha([(960, 850), (960, 880), (360, 880), (360, 910)], cable="un transporte u otro",
             pos_cable=(520, 872))
    L.flecha([(960, 880), (960, 910)])
    L.flecha([(360, 1160), (360, 1090)])

    # ---------------------------------------------------- cable
    L.flecha([(1230, 950), (1591, 950)], cable="'L' N palabras · 'X' · 'D' · 'S' · 'R' · 'I'",
             pos_cable=(1240, 938))
    L.flecha([(1591, 1040), (1230, 1040)], cable="'K' · volcado de 326 bytes (~28 ms)",
             pos_cable=(1240, 1068))
    L.caja(1300, 700, 210, 130, "gris", "USB-UART", None, tam_nombre=22)
    L.lineas(1405, 780, ["FTDI en la", "Basys 3"], 16, tg, "middle", mono=True)
    L.lineas(1300, 1120, ["115200 baudios, 8N1", "1 byte = 10 bits ≈ 87 µs", "pedido → respuesta"],
             17, GRIS, italica=True)

    # ---------------------------------------------------- FPGA
    L.marco(1600, 160, 1660, 1320, "FPGA Basys 3", "top.v — un solo clock: clk_wiz_0, 100 → 70 MHz")
    L.pin(1600, 950, "i_rx", "der")
    L.pin(1600, 1040, "o_tx", "der")
    L.caja(1680, 250, 360, 150, "violeta", "reset_gen", None, tam_nombre=24)
    L.lineas(1860, 330, ["encendido + botón", "(sincronizado) + locked"], 16,
             PALETA["violeta"][2], "middle", mono=True)
    L.pastilla(2070, 325, "reset")
    L.texto(2200, 300, "reset global: UART, intf, debug_unit y cpu", 17, PALETA["violeta"][2],
            italica=True)
    L.texto(2200, 325, "cpu_rst = reset OR cpu_reset ('X' y 'L')", 17, PALETA["violeta"][2],
            italica=True)
    L.texto(2200, 350, "clk_wiz_0 (MMCM): i_clk 100 MHz → clk 70 MHz, locked", 17,
            PALETA["violeta"][2], italica=True)

    L.caja(1680, 700, 300, 400, "azul", "uart", "uart.v")
    L.lineas(1830, 820, ["baud_rate_generator", "÷38 · ×16 por bit", "(tick = enable)", "",
                         "rx_fsmd", "sincronizador 2 FF", "", "tx_fsmd"], 16,
             PALETA["azul"][2], "middle", mono=True)
    L.flecha([(1609, 950), (1680, 950)])
    L.flecha([(1680, 1040), (1609, 1040)])
    L.caja(2050, 700, 240, 400, "turquesa", "intf", "intf.v")
    L.lineas(2170, 830, ["rx_intf", "buffer de 1 byte", "", "tx_intf", "1 byte + full"], 16,
             PALETA["turquesa"][2], "middle", mono=True)
    L.flecha([(1980, 830), (2050, 830)], 8, cable="dout", pos_cable=(1986, 856))
    L.flecha([(2050, 1000), (1980, 1000)], 8, cable="din", pos_cable=(1986, 1026))

    L.marco(2360, 520, 520, 900, "debug_unit", "", claro=True)
    L.caja(2400, 600, 440, 380, "ambar", "control_fsmd", "FSM + registros")
    L.lineas(2620, 710, ["IDLE · LOAD_LEN · LOAD_WORD", "WRITE · CLEAR · RESET · ACK",
                         "RUN · STEP · DUMP", "", "cycles (32 bits)", "interrupted",
                         "estado = {fault, interrupted, halted}"], 16, PALETA["ambar"][2],
             "middle", mono=True)
    L.caja(2400, 1030, 440, 340, "rojo", "dump_mux", "combinacional")
    L.lineas(2620, 1140, ["dump_idx 0…325 → byte", "A5 · PC · ciclos · estado",
                          "x0..x31 · latches (60 B)", "mem[0..31] (128 B)",
                          "volcado \"al vuelo\":", "sin buffer"], 16, PALETA["rojo"][2], "middle",
             mono=True)
    L.flecha([(2290, 830), (2400, 830)], 8, cable="r_data, rd", pos_cable=(2296, 856))
    L.flecha([(2400, 930), (2290, 930)], 8, cable="w_data, wr", pos_cable=(2296, 956))
    L.flecha([(2560, 980), (2560, 1030)], 9, cable=None)
    L.flecha([(2700, 1030), (2700, 980)], 8, cable=None)

    L.caja(2940, 520, 280, 900, "verde", "cpu", "cpu.v (parte A)")
    L.lineas(3080, 640, ["IF · ID · EX", "MEM · WB", "", "instr_mem", "256 × 32", "",
                         "data_mem", "32 × 32", "", "reg_file", "32 × 32", "",
                         "forwarding", "stall · flush", "HALT · error"], 16,
             PALETA["verde"][2], "middle", mono=True)
    L.flecha([(2840, 650), (2940, 650)], cable="enable", pos_cable=(2846, 674))
    L.flecha([(2840, 720), (2940, 720)], cable="cpu_reset", pos_cable=(2846, 744))
    L.flecha([(2840, 800), (2940, 800)], 32, cable="imem_we/addr/data", pos_cable=(2846, 824))
    L.flecha([(2940, 900), (2840, 900)], cable="halted, fault", pos_cable=(2846, 924))
    L.flecha([(2940, 1120), (2840, 1120)], 480, cable="latches", pos_cable=(2846, 1144))
    L.flecha([(2840, 1200), (2940, 1200)], 5, cable="dbg_reg_addr", pos_cable=(2846, 1224))
    L.flecha([(2940, 1260), (2840, 1260)], 32, cable="regs / mem / pc", pos_cable=(2846, 1284))
    L.flecha([(2840, 1330), (2940, 1330)], 8, cable="dbg_mem_addr", pos_cable=(2846, 1354))

    L.pin(2620, 160, "o_leds[7:0]")
    L.flecha([(2620, 600), (2620, 169)], 8, cable="{3'b000, halted, estado FSM}",
             pos_cable=(2630, 470))

    # ---------------------------------------------------- sesión típica
    L.texto(60, 1530, "Una sesión típica, de punta a punta", 26, TINTA, negrita=True)
    pasos = [
        "Se escribe el programa en ensamblador (o se abre un ejemplo) en la GUI.",
        "ensamblador.py lo traduce a palabras de 32 bits (etiquetas, pseudo-instrucciones).",
        "'L' + N + palabras: control_fsmd arma cada palabra y la escribe en instr_mem (con enable = 0);",
        "     CLEAR pone HALT en el resto, RESET reinicia el cpu (registros y PC en 0) y responde 'K'.",
        "'S' (un ciclo de enable) o 'R' (enable = !halted hasta el HALT; 'I' interrumpe).",
        "control_fsmd pasa a DUMP: dump_mux arma cada byte del volcado mientras el cpu está congelado.",
        "La PC recibe 326 bytes, decodificador.py los convierte y la GUI muestra los cambios.",
    ]
    n = 1
    for i, t in enumerate(pasos):
        y = 1580 + 38 * i
        if not t.startswith("     "):
            L.numero(80, y - 7, str(n), r=14)
            n += 1
        L.texto(110, y, t.strip(), 19, TINTA)

    L.texto(2000, 1530, "Referencias", 26, TINTA, negrita=True)
    refs = [("violeta", "interfaz de usuario / reset"), ("gris", "control y comunicación (PC)"),
            ("azul", "UART"), ("turquesa", "buffers / ensamblador"),
            ("ambar", "control_fsmd / modelo"), ("rojo", "volcado / decodificador"),
            ("verde", "procesador / FPGA simulada")]
    for i, (c, t) in enumerate(refs):
        f, b, _ = PALETA[c]
        y = 1570 + 36 * i
        L.el.append(f'<rect x="2000" y="{y - 18}" width="60" height="24" rx="5" fill="{f}" '
                    f'stroke="{b}" stroke-width="2"/>')
        L.texto(2080, y, t, 18, TINTA)
    L.flecha([(2580, 1564), (2660, 1564)], 32)
    L.texto(2680, 1570, "bus y su ancho en bits", 18, TINTA)
    L.texto(2580, 1606, "Comandos: un byte ASCII. Respuestas:", 18, TINTA)
    L.texto(2580, 1634, "'K' (L, X) o volcado (D, S, R/I).", 18, TINTA)
    L.texto(2580, 1662, "Estado: 0x01 HALT · 0x05 error ·", 18, TINTA)
    L.texto(2580, 1690, "0x02 interrumpido.", 18, TINTA)
    return L


def a_png(svg, png, ancho):
    """Convierte con Qt (PySide6) si esta disponible."""
    try:
        from PySide6.QtCore import QRectF
        from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter
        from PySide6.QtSvg import QSvgRenderer
    except ImportError:
        print("  (sin PySide6: no se genera el .png)")
        return False
    app = QGuiApplication.instance() or QGuiApplication([])  # noqa: F841
    r = QSvgRenderer(svg)
    s = r.defaultSize()
    img = QImage(ancho, int(s.height() * ancho / s.width()), QImage.Format_ARGB32)
    img.fill(QColor("white"))
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    r.render(p, QRectF(0, 0, img.width(), img.height()))
    p.end()
    img.save(png)
    return True


def main():
    for nombre, f in (("CPU_completo", cpu), ("sistema_completo", sistema)):
        svg = os.path.join(IMG, nombre + ".svg")
        f().guardar(svg)
        print("generado:", os.path.relpath(svg, os.path.dirname(IMG)))
        png = svg[:-4] + ".png"
        if a_png(svg, png, 3300):
            print("generado:", os.path.relpath(png, os.path.dirname(IMG)))


if __name__ == "__main__":
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    main()
