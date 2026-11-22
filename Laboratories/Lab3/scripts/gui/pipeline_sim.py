"""
pipeline_sim.py - Simulador ciclo a ciclo del cpu (src/cpu/cpu.v) en Python.

A diferencia de rv32i_model.py (que ejecuta la ISA y calcula los TIEMPOS con
una formula), este modulo copia el hardware senal por senal: los 4 latches,
el banco de registros con bypass WB -> ID, la memoria de datos, el forwarding,
el stall, el flush, el HALT y los errores. Por eso reproduce los 480 bits de
o_latches IGUAL que el RTL (lo verifica tests/test_pipeline_sim.py contra
Icarus Verilog, ciclo por ciclo, en todos los programas de ejemplo).

Ademas guarda un dato que el hardware NO guarda: el PC de la instruccion que
hay en EX/MEM y en MEM/WB (pc_mem, pc_wb). La vista del pipeline lo usa cuando
no hay dos volcados consecutivos, pero SOLO si los 480 bits simulados
coinciden con los del volcado real.

Uso:
    cpu = PipelineSim(palabras, mem_inicial)    # como despues de un reset
    cpu.paso()                                  # un ciclo habilitado
    cpu.latches_bits(), cpu.pc, cpu.halted, cpu.regs, cpu.dmem
"""

M32 = 0xFFFFFFFF
NOP = 0x00000013
IMEM_WORDS = 256
DMEM_WORDS = 32

OP_REG, OP_IMM, LOAD, STORE = 0x33, 0x13, 0x03, 0x23
BRANCH, JAL, JALR, LUI = 0x63, 0x6F, 0x67, 0x37


def _sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


# ============================================================== ID
def control_unit(instr, valid):
    """Copia de src/cpu/id/control_unit.v. Devuelve un dict de controles."""
    op, f3, f7 = instr & 0x7F, (instr >> 12) & 7, (instr >> 25) & 0x7F
    if op == OP_REG:
        sup = f7 == 0 or (f7 == 0x20 and f3 in (0, 5))
    elif op == OP_IMM:
        sup = (f7 == 0) if f3 == 1 else ((f7 in (0, 0x20)) if f3 == 5 else True)
    elif op == LOAD:
        sup = f3 in (0, 1, 2, 4, 5)
    elif op == STORE:
        sup = f3 in (0, 1, 2)
    elif op == BRANCH:
        sup = f3 in (0, 1)
    elif op in (JAL, LUI):
        sup = True
    elif op == JALR:
        sup = f3 == 0
    else:
        sup = instr == 0
    c = dict(reg_write=0, alu_src_a=0, alu_src_b=0, mem_read=0, mem_write=0,
             result_src=0, branch=0, jump=0, jalr=0, alu_op=0, halt=0, uses_rs1=0,
             uses_rs2=0, illegal=int(valid and not sup))
    if valid and sup:
        if op == OP_REG:
            c.update(reg_write=1, uses_rs1=1, uses_rs2=1, alu_op=2)
        elif op == OP_IMM:
            c.update(reg_write=1, alu_src_b=1, uses_rs1=1, alu_op=3)
        elif op == LOAD:
            c.update(reg_write=1, alu_src_b=1, mem_read=1, result_src=1, uses_rs1=1)
        elif op == STORE:
            c.update(alu_src_b=1, mem_write=1, uses_rs1=1, uses_rs2=1)
        elif op == BRANCH:
            c.update(branch=1, uses_rs1=1, uses_rs2=1, alu_op=1)
        elif op == JAL:
            c.update(reg_write=1, jump=1)
        elif op == JALR:
            c.update(reg_write=1, jump=1, jalr=1, alu_src_b=1, uses_rs1=1)
        elif op == LUI:
            c.update(reg_write=1, alu_src_a=1, alu_src_b=1)
        else:
            c.update(halt=1)
    return c


def imm_gen(i):
    """Copia de src/cpu/id/imm_gen.v."""
    op = i & 0x7F
    if op in (OP_IMM, LOAD, JALR):
        v = _sext(i >> 20, 12)
    elif op == STORE:
        v = _sext(((i >> 25) << 5) | ((i >> 7) & 0x1F), 12)
    elif op == BRANCH:
        v = _sext((((i >> 31) & 1) << 12) | (((i >> 7) & 1) << 11) |
                  (((i >> 25) & 0x3F) << 5) | (((i >> 8) & 0xF) << 1), 13)
    elif op == LUI:
        v = i & 0xFFFFF000
    elif op == JAL:
        v = _sext((((i >> 31) & 1) << 20) | (((i >> 12) & 0xFF) << 12) |
                  (((i >> 20) & 1) << 11) | (((i >> 21) & 0x3FF) << 1), 21)
    else:
        v = 0
    return v & M32


# ============================================================== EX
def alu_control(alu_op, f3, f7b5):
    if alu_op == 0:
        return 0
    if alu_op == 1:
        return 8
    if alu_op == 2:
        return (f7b5 << 3) | f3
    return ((f7b5 if f3 == 5 else 0) << 3) | f3


def alu(a, b, op):
    sh = b & 0x1F
    sa = a - (1 << 32) if a & 0x80000000 else a
    sb = b - (1 << 32) if b & 0x80000000 else b
    r = {0: a + b, 8: a - b, 1: a << sh, 2: int(sa < sb), 3: int(a < b), 4: a ^ b,
         5: a >> sh, 13: sa >> sh, 6: a | b, 7: a & b}.get(op, 0)
    return r & M32


# ============================================================== MEM
def data_mem(mem, addr, wdata, re, we, f3):
    """Copia de src/cpu/mem/data_mem.v (parte combinacional).
    Devuelve (rdata, error, escritura) con escritura = (palabra, mascara, dato)."""
    word, off = (addr >> 2) & 0x1F, addr & 3
    in_range = (addr >> 7) == 0
    load_sup = f3 in (0, 1, 2, 4, 5)
    store_sup = f3 in (0, 1, 2)
    t = f3 & 3
    aligned = t == 0 or (t == 1 and not addr & 1) or (t == 2 and off == 0)
    err = bool((re or we) and (not in_range or not aligned or (re and we) or
                               (re and not load_sup) or (we and not store_sup)))
    rdata = 0
    if re and not err:
        w = mem[word]
        s = w >> (8 * off)
        rdata = {0: _sext(s, 8) & M32, 1: _sext(s, 16) & M32, 2: w,
                 4: s & 0xFF, 5: s & 0xFFFF}.get(f3, 0)
    if f3 == 0:
        mask, ww = (1 << off) & 0xF, (wdata & 0xFF) * 0x01010101
    elif f3 == 1:
        mask, ww = (3 << off) & 0xF, (wdata & 0xFFFF) * 0x00010001
    elif f3 == 2:
        mask, ww = 0xF, wdata
    else:
        mask, ww = 0, wdata
    return rdata, err, (word, mask, ww & M32)


# ============================================================== latches
_IDEX_CAMPOS = ("pc", "rs1_data", "rs2_data", "imm", "rs1", "rs2", "rd", "funct3",
                "f7b5", "reg_write", "alu_src_a", "alu_src_b", "mem_read", "mem_write",
                "result_src", "branch", "jump", "jalr", "alu_op", "halt", "uses_rs1",
                "uses_rs2", "illegal", "valid")
_EXMEM_CAMPOS = ("result", "store_data", "rd", "funct3", "reg_write", "mem_read",
                 "mem_write", "result_src", "halt", "illegal", "valid")
_MEMWB_CAMPOS = ("result", "mem_data", "rd", "reg_write", "result_src", "halt",
                 "illegal", "valid")


def _vacio(campos):
    return {c: 0 for c in campos}


class PipelineSim:

    def __init__(self, palabras=(), mem_inicial=None):
        # La memoria queda como despues de un 'L': el programa, HALT en el resto
        # y la palabra 255 SIEMPRE HALT (la debug_unit la fuerza, igual que
        # rv32i_model y tb_traza). Sin esto, un programa de 256 palabras sin HALT
        # seguia de largo hasta el fetch en 0x400 y terminaba con error.
        p = list(palabras)[:IMEM_WORDS]
        self.imem = [w & M32 for w in p] + [0] * (IMEM_WORDS - len(p))
        self.imem[IMEM_WORDS - 1] = 0
        self.dmem = list(mem_inicial) if mem_inicial is not None else [0] * DMEM_WORDS
        self.regs = [0] * 32
        self.reset()

    def reset(self):
        """i_cpu_reset: PC, latches, registros y halting. Las memorias no."""
        self.pc = 0
        self.halting = 0
        self.regs = [0] * 32
        self.ifid = {"pc": 0, "instr": NOP, "valid": 0}
        self.idex = _vacio(_IDEX_CAMPOS)
        self.exmem = _vacio(_EXMEM_CAMPOS)
        self.memwb = _vacio(_MEMWB_CAMPOS)
        self.pc_mem = None          # PC de la instruccion en EX/MEM (no esta en el hardware)
        self.pc_wb = None           # PC de la instruccion en MEM/WB
        self.ciclos = 0

    # -------------------------------------------------- salidas
    @property
    def halted(self):
        return int(self.memwb["valid"] and self.memwb["halt"])

    @property
    def fault(self):
        return int(self.halted and self.memwb["illegal"])

    def reg(self, n):
        return 0 if n == 0 else self.regs[n]

    def latches_bits(self):
        """Los 480 bits de o_latches (misma concatenacion que cpu.v)."""
        a, e, m, w = self.ifid, self.idex, self.exmem, self.memwb

        def cat(*partes):
            v = 0
            for valor, ancho in partes:
                v = (v << ancho) | (valor & ((1 << ancho) - 1))
            return v
        sid = cat((a["pc"], 32), (a["instr"], 32), (0, 31), (a["valid"], 1))
        sex = cat((e["pc"], 32), (e["rs1_data"], 32), (e["rs2_data"], 32), (e["imm"], 32),
                  (0, 13), (e["rs1"], 5), (e["rs2"], 5), (e["rd"], 5), (e["funct3"], 3),
                  (e["f7b5"], 1), (0, 16), (e["reg_write"], 1), (e["alu_src_a"], 1),
                  (e["alu_src_b"], 1), (e["mem_read"], 1), (e["mem_write"], 1),
                  (e["result_src"], 1), (e["branch"], 1), (e["jump"], 1), (e["jalr"], 1),
                  (e["alu_op"], 2), (e["halt"], 1), (e["uses_rs1"], 1), (e["uses_rs2"], 1),
                  (e["illegal"], 1), (e["valid"], 1))
        smem = cat((m["result"], 32), (m["store_data"], 32), (0, 17), (m["rd"], 5),
                   (m["funct3"], 3), (m["reg_write"], 1), (m["mem_read"], 1),
                   (m["mem_write"], 1), (m["result_src"], 1), (m["halt"], 1),
                   (m["illegal"], 1), (m["valid"], 1))
        swb = cat((w["result"], 32), (w["mem_data"], 32), (0, 22), (w["rd"], 5),
                  (w["reg_write"], 1), (w["result_src"], 1), (w["halt"], 1),
                  (w["illegal"], 1), (w["valid"], 1))
        return (sid << 384) | (sex << 192) | (smem << 96) | swb

    # -------------------------------------------------- un ciclo
    def paso(self):
        """Un flanco con i_enable = 1. Con halted = 1 no hace nada (step = 0).
        Devuelve False si no avanzo."""
        if self.halted:
            return False
        a, e, m, w = self.ifid, self.idex, self.exmem, self.memwb
        instr, id_valid = a["instr"], a["valid"]
        dec = control_unit(instr, id_valid)
        id_rs1, id_rs2, id_rd = (instr >> 15) & 0x1F, (instr >> 20) & 0x1F, (instr >> 7) & 0x1F

        # WB y banco de registros (con bypass WB -> ID)
        wb_data = w["mem_data"] if w["result_src"] else w["result"]
        wb_write = bool(w["valid"] and w["reg_write"] and not w["illegal"])
        write_en = wb_write and w["rd"] != 0

        def leer(rs):
            if rs == 0:
                return 0
            return wb_data if (write_en and w["rd"] == rs) else self.regs[rs]
        rs1_data, rs2_data = leer(id_rs1), leer(id_rs2)

        # IF
        fetch_error = (self.pc >> 10) != 0 or (self.pc & 3) != 0
        if_instr = M32 if fetch_error else self.imem[(self.pc >> 2) & 0xFF]

        # EX: forwarding (forwarding_unit.v)
        mem_writes = m["valid"] and m["reg_write"] and m["rd"] != 0
        wb_writes = w["valid"] and wb_write and w["rd"] != 0

        def fwd(usa, rs, dato):
            if e["valid"] and usa:
                if mem_writes and m["rd"] == rs:
                    return m["result"] if not m["result_src"] else dato
                if wb_writes and w["rd"] == rs:
                    return wb_data
            return dato
        rs1v = fwd(e["uses_rs1"], e["rs1"], e["rs1_data"])
        rs2v = fwd(e["uses_rs2"], e["rs2"], e["rs2_data"])
        alu_a = 0 if e["alu_src_a"] else rs1v
        alu_b = e["imm"] if e["alu_src_b"] else rs2v
        res = alu(alu_a, alu_b, alu_control(e["alu_op"], e["funct3"], e["f7b5"]))
        zero = res == 0
        taken = e["branch"] and ((e["funct3"] == 0 and zero) or (e["funct3"] == 1 and not zero))
        redirect = bool(e["valid"] and not e["illegal"] and (e["jump"] or taken))
        target = ((rs1v + e["imm"]) & 0xFFFFFFFE) if e["jalr"] else (e["pc"] + e["imm"]) & M32
        ex_result = (e["pc"] + 4) & M32 if e["jump"] else res

        # MEM
        rdata, err, escritura = data_mem(self.dmem, m["result"], m["store_data"],
                                         m["valid"] and m["mem_read"],
                                         m["valid"] and m["mem_write"], m["funct3"])
        mem_fault = bool(m["valid"] and err)

        stop_id = bool(id_valid and (dec["halt"] or dec["illegal"]) and not redirect
                       and not mem_fault and not self.halting)
        pc_next = target if redirect else (self.pc + 4) & M32

        # hazard_unit.v
        load_use = bool(id_valid and e["valid"] and e["mem_read"] and e["reg_write"] and
                        e["rd"] != 0 and ((dec["uses_rs1"] and id_rs1 == e["rd"]) or
                                          (dec["uses_rs2"] and id_rs2 == e["rd"])))
        pc_write, if_write, if_flush, ex_flush = 1, 1, 0, 0
        if e["valid"] and redirect:
            if_flush = ex_flush = 1
        elif load_use:
            pc_write, if_write, ex_flush = 0, 0, 1

        # ---------------- flanco: todo se actualiza "a la vez"
        nuevo_pc = self.pc
        if pc_write and (redirect or not fetch_error) and not self.halting and \
                not stop_id and not mem_fault:
            nuevo_pc = pc_next
        halting = 1 if (stop_id or mem_fault) else self.halting

        # IF/ID
        if if_flush or stop_id or self.halting or mem_fault:
            n_ifid = {"pc": 0, "instr": NOP, "valid": 0}
        elif if_write:
            n_ifid = {"pc": self.pc, "instr": if_instr, "valid": int(not self.halting)}
        else:
            n_ifid = dict(a)

        # ID/EX
        if ex_flush or mem_fault or not (id_valid and not self.halting):
            n_idex = _vacio(_IDEX_CAMPOS)
        else:
            n_idex = dict(pc=a["pc"], rs1_data=rs1_data, rs2_data=rs2_data,
                          imm=imm_gen(instr), rs1=id_rs1, rs2=id_rs2, rd=id_rd,
                          funct3=(instr >> 12) & 7, f7b5=(instr >> 30) & 1,
                          reg_write=dec["reg_write"], alu_src_a=dec["alu_src_a"],
                          alu_src_b=dec["alu_src_b"], mem_read=dec["mem_read"],
                          mem_write=dec["mem_write"], result_src=dec["result_src"],
                          branch=dec["branch"], jump=dec["jump"], jalr=dec["jalr"],
                          alu_op=dec["alu_op"], halt=int(dec["halt"] or dec["illegal"]),
                          uses_rs1=dec["uses_rs1"], uses_rs2=dec["uses_rs2"],
                          illegal=dec["illegal"], valid=1)

        # EX/MEM
        if not (e["valid"] and not mem_fault):
            n_exmem, n_pc_mem = _vacio(_EXMEM_CAMPOS), None
        else:
            n_exmem = dict(result=ex_result, store_data=rs2v, rd=e["rd"], funct3=e["funct3"],
                           reg_write=e["reg_write"], mem_read=e["mem_read"],
                           mem_write=e["mem_write"], result_src=e["result_src"],
                           halt=e["halt"], illegal=e["illegal"], valid=1)
            n_pc_mem = e["pc"]

        # MEM/WB
        if not m["valid"]:
            n_memwb, n_pc_wb = _vacio(_MEMWB_CAMPOS), None
        else:
            n_memwb = dict(result=m["result"], mem_data=rdata, rd=m["rd"],
                           reg_write=int(m["reg_write"] and not mem_fault),
                           result_src=m["result_src"], halt=int(m["halt"] or mem_fault),
                           illegal=int(m["illegal"] or mem_fault), valid=1)
            n_pc_wb = self.pc_mem

        # escrituras de memoria y banco
        if m["valid"] and m["mem_write"] and not err:
            pal, mask, ww = escritura
            v = self.dmem[pal]
            for k in range(4):
                if mask >> k & 1:
                    v = (v & ~(0xFF << 8 * k)) | (ww & (0xFF << 8 * k))
            self.dmem[pal] = v & M32
        if write_en:
            self.regs[w["rd"]] = wb_data

        self.pc, self.halting = nuevo_pc, halting
        self.ifid, self.idex, self.exmem, self.memwb = n_ifid, n_idex, n_exmem, n_memwb
        self.pc_mem, self.pc_wb = n_pc_mem, n_pc_wb
        self.ciclos += 1
        return True

    def correr(self, max_ciclos):
        """Avanza hasta halted o hasta max_ciclos ciclos en total."""
        while not self.halted and self.ciclos < max_ciclos:
            self.paso()
        return self.halted
