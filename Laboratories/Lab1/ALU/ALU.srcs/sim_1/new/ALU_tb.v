`timescale 1ns / 1ps
//==============================================================================
// Testbench autoverificable para el modulo ALU (version 8 bits, sincronica)
//
// Cambios respecto a la version anterior:
//   - LENGTH_BITS pasa de 16 a 8. Todos los vectores se recortan a 8 bits.
//   - La ALU es ahora sincronica: se agrega i_clk (100 MHz) y i_reset sincrono.
//     Las tareas de carga suben el boton, esperan al menos un flanco de clock
//     y despues lo bajan. La sincronizacion se hace con @(posedge i_clk) para
//     no depender de numeros magicos de retardo.
//   - Se agregan las salidas o_zero, o_carry, o_overflow. El modelo de
//     referencia calcula los cuatro valores (leds + 3 flags) y check_result
//     los verifica todos juntos.
//   - Se agrega un test especifico del reset y otro del comportamiento cuando
//     el boton se sostiene varios ciclos (ahora en cada flanco captura el
//     switch, ya no hay latch transparente).
//   - Se elimina el test de "latch transparente" original: no aplica al
//     comportamiento sincronico.
//
// El modelo de referencia (alu_ref) describe la ESPECIFICACION de la ALU, no
// la implementacion del DUT. Si el DUT no implementa una operacion, el
// testbench la reporta como error.
//==============================================================================

module ALU_tb;

    //--------------------------------------------------------------------------
    // Parametros
    //--------------------------------------------------------------------------
    localparam LENGTH_BITS = 8;
    localparam LENGTH_OPT  = 6;
    localparam SHAMT_BITS  = $clog2(LENGTH_BITS);   // 3 bits para 8
    localparam N_RANDOM    = 500;

    // Porcentaje de vectores aleatorios que usan un opcode VALIDO.
    // El resto sortea los 6 bits libremente para ejercitar el default.
    localparam PCT_OP_VALIDO = 85;

    // Periodo del clock: 10 ns => 100 MHz (igual al de la Basys 3)
    localparam CLK_PERIOD = 10;

    // Mismos opcodes que el DUT
    localparam [5:0] ADD  = 6'b100000,
                     SUB  = 6'b100010,
                     AND_ = 6'b100100,
                     OR_  = 6'b100101,
                     XOR_ = 6'b100110,
                     NOR_ = 6'b100111,
                     SRA  = 6'b000011,
                     SRL  = 6'b000010;

    localparam N_OPS = 8;

    //--------------------------------------------------------------------------
    // Senales
    //--------------------------------------------------------------------------
    reg                    i_clk;
    reg                    i_reset;
    reg  [LENGTH_BITS-1:0] i_switch;
    reg                    i_button_1;
    reg                    i_button_2;
    reg                    i_button_3;

    wire [LENGTH_BITS-1:0] o_leds;
    wire                   o_zero;
    wire                   o_carry;
    wire                   o_overflow;

    // Modelo espejo: refleja lo que el DUT deberia tener guardado
    reg [LENGTH_BITS-1:0] m_A;
    reg [LENGTH_BITS-1:0] m_B;
    reg [LENGTH_OPT-1:0]  m_opt;

    // Contadores y utilidades del testbench
    integer errors;
    integer checks;
    integer i;
    integer seed;
    reg     verbose;

    reg [5:0] ops [0:N_OPS-1];
    integer cov [0:63];
    integer cov_faltantes;

    //--------------------------------------------------------------------------
    // Generacion del clock: 100 MHz (periodo 10 ns)
    //--------------------------------------------------------------------------
    initial i_clk = 1'b0;
    always #(CLK_PERIOD/2) i_clk = ~i_clk;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    ALU #(
        .LENGTH_BITS (LENGTH_BITS),
        .LENGTH_OPT  (LENGTH_OPT)
    ) dut (
        .o_leds     (o_leds),
        .o_zero     (o_zero),
        .o_carry    (o_carry),
        .o_overflow (o_overflow),
        .i_clk      (i_clk),
        .i_reset    (i_reset),
        .i_switch   (i_switch),
        .i_button_1 (i_button_1),
        .i_button_2 (i_button_2),
        .i_button_3 (i_button_3)
    );

    //--------------------------------------------------------------------------
    // Modelo de referencia (bible model)
    //
    // Calcula el resultado y los tres flags a partir de la especificacion.
    // Se usa una task porque hay que devolver varios valores.
    //--------------------------------------------------------------------------
    task alu_ref;
        input  [LENGTH_BITS-1:0] a;
        input  [LENGTH_BITS-1:0] b;
        input  [LENGTH_OPT-1:0]  op;
        output [LENGTH_BITS-1:0] r_result;
        output                   r_zero;
        output                   r_carry;
        output                   r_overflow;
        reg    [LENGTH_BITS:0]   tmp;      // 1 bit extra para capturar el carry
        begin
            r_result   = {LENGTH_BITS{1'b0}};
            r_carry    = 1'b0;
            r_overflow = 1'b0;

            case (op)
                ADD: begin
                    tmp = {1'b0, a} + {1'b0, b};
                    {r_carry, r_result} = tmp;
                    r_overflow = (a[LENGTH_BITS-1] == b[LENGTH_BITS-1]) &&
                                 (r_result[LENGTH_BITS-1] != a[LENGTH_BITS-1]);
                end
                SUB: begin
                    tmp = {1'b0, a} - {1'b0, b};
                    {r_carry, r_result} = tmp;
                    r_overflow = (a[LENGTH_BITS-1] != b[LENGTH_BITS-1]) &&
                                 (r_result[LENGTH_BITS-1] != a[LENGTH_BITS-1]);
                end
                AND_: r_result = a & b;
                OR_:  r_result = a | b;
                XOR_: r_result = a ^ b;
                NOR_: r_result = ~(a | b);
                SRA:  r_result = $signed(a) >>> b[SHAMT_BITS-1:0];
                SRL:  r_result = a          >>  b[SHAMT_BITS-1:0];
                default: r_result = {LENGTH_BITS{1'b0}};
            endcase

            r_zero = (r_result == {LENGTH_BITS{1'b0}});
        end
    endtask

    // Nombre legible del opcode
    function [8*8-1:0] op_name;
        input [LENGTH_OPT-1:0] op;
        begin
            case (op)
                ADD:  op_name = "ADD";
                SUB:  op_name = "SUB";
                AND_: op_name = "AND";
                OR_:  op_name = "OR";
                XOR_: op_name = "XOR";
                NOR_: op_name = "NOR";
                SRA:  op_name = "SRA";
                SRL:  op_name = "SRL";
                default: op_name = "INVALID";
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Tareas de estimulo
    //
    // Como la ALU es sincronica, las tareas se sincronizan al clock:
    //   - se preparan las entradas en el flanco descendente (para respetar
    //     setup contra el proximo flanco de subida)
    //   - se espera un flanco de subida (ahi el DUT captura)
    //   - se baja el boton en el siguiente flanco descendente
    //   - se espera un ciclo mas para dejar estabilizar la salida combinacional
    //--------------------------------------------------------------------------

    // Pulso de reset: mantiene i_reset alto durante 2 flancos de clock.
    task apply_reset;
        begin
            @(negedge i_clk);
            i_reset    = 1'b1;
            i_button_1 = 1'b0;
            i_button_2 = 1'b0;
            i_button_3 = 1'b0;
            @(posedge i_clk);
            @(posedge i_clk);
            @(negedge i_clk);
            i_reset = 1'b0;
            m_A     = {LENGTH_BITS{1'b0}};
            m_B     = {LENGTH_BITS{1'b0}};
            m_opt   = {LENGTH_OPT{1'b0}};
            @(posedge i_clk);
        end
    endtask

    task load_A;
        input [LENGTH_BITS-1:0] v;
        begin
            @(negedge i_clk);
            i_switch   = v;
            i_button_1 = 1'b1;
            @(posedge i_clk);       // este flanco captura y carga dato_A
            @(negedge i_clk);
            i_button_1 = 1'b0;
            m_A = v;
            @(posedge i_clk);       // margen para que se propague al result combinacional
            #1;
        end
    endtask

    task load_B;
        input [LENGTH_BITS-1:0] v;
        begin
            @(negedge i_clk);
            i_switch   = v;
            i_button_2 = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_button_2 = 1'b0;
            m_B = v;
            @(posedge i_clk);
            #1;
        end
    endtask

    // Solo los LENGTH_OPT bits bajos del switch llegan a opt
    task load_OPT;
        input [LENGTH_BITS-1:0] v;
        begin
            @(negedge i_clk);
            i_switch   = v;
            i_button_3 = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_button_3 = 1'b0;
            m_opt = v[LENGTH_OPT-1:0];
            @(posedge i_clk);
            #1;
        end
    endtask

    // Carga los tres registros de una
    task load_all;
        input [LENGTH_BITS-1:0] a;
        input [LENGTH_BITS-1:0] b;
        input [5:0]             op;
        begin
            load_A(a);
            load_B(b);
            load_OPT({{(LENGTH_BITS-LENGTH_OPT){1'b0}}, op});
        end
    endtask

    //--------------------------------------------------------------------------
    // Generacion aleatoria
    //--------------------------------------------------------------------------
    function [5:0] random_op;
        input dummy;
        begin
            if (({$random(seed)} % 100) < PCT_OP_VALIDO)
                random_op = ops[{$random(seed)} % N_OPS];
            else
                random_op = $random(seed);
        end
    endfunction

    // Palabra de LENGTH_BITS bits con sesgo hacia valores borde
    function [LENGTH_BITS-1:0] random_data;
        input dummy;
        integer r;
        begin
            r = {$random(seed)} % 100;
            if      (r < 5)  random_data = {LENGTH_BITS{1'b0}};                       // 0x00
            else if (r < 10) random_data = {LENGTH_BITS{1'b1}};                       // 0xFF
            else if (r < 15) random_data = {1'b1, {(LENGTH_BITS-1){1'b0}}};           // 0x80
            else if (r < 20) random_data = {1'b0, {(LENGTH_BITS-1){1'b1}}};           // 0x7F
            else             random_data = $random(seed);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Tareas de verificacion
    //
    // check_result compara los CUATRO outputs (leds + zero + carry + overflow)
    // contra el modelo de referencia. Un unico FAIL cubre los cuatro.
    //--------------------------------------------------------------------------
    task check_result;
        input [8*40-1:0] etiqueta;
        reg [LENGTH_BITS-1:0] e_result;
        reg                   e_zero;
        reg                   e_carry;
        reg                   e_overflow;
        reg                   ok;
        begin
            alu_ref(m_A, m_B, m_opt, e_result, e_zero, e_carry, e_overflow);
            checks = checks + 1;
            if (^m_opt !== 1'bx) cov[m_opt] = cov[m_opt] + 1;

            ok = (o_leds     === e_result)   &&
                 (o_zero     === e_zero)     &&
                 (o_carry    === e_carry)    &&
                 (o_overflow === e_overflow);

            if (!ok) begin
                errors = errors + 1;
                $display("[FAIL] t=%0t %0s | op=%b (%0s) A=0x%h B=0x%h",
                         $time, etiqueta, m_opt, op_name(m_opt), m_A, m_B);
                $display("        esperado: leds=0x%h Z=%b C=%b V=%b",
                         e_result, e_zero, e_carry, e_overflow);
                $display("        obtenido: leds=0x%h Z=%b C=%b V=%b",
                         o_leds, o_zero, o_carry, o_overflow);
            end
            else if (verbose) begin
                $display("[ OK ] t=%0t %0s | op=%b (%0s) A=0x%h B=0x%h | leds=0x%h Z=%b C=%b V=%b",
                         $time, etiqueta, m_opt, op_name(m_opt), m_A, m_B,
                         o_leds, o_zero, o_carry, o_overflow);
            end
        end
    endtask

    // Compara solo o_leds contra un valor esperado explicito (para tests
    // donde interesa el resultado y no todos los flags, como el barrido inicial)
    task check_leds;
        input [8*40-1:0] etiqueta;
        input [LENGTH_BITS-1:0] esperado;
        begin
            checks = checks + 1;
            if (o_leds !== esperado) begin
                errors = errors + 1;
                $display("[FAIL] t=%0t %0s | esperado=0x%h obtenido=0x%h",
                         $time, etiqueta, esperado, o_leds);
            end
            else if (verbose) begin
                $display("[ OK ] t=%0t %0s | leds=0x%h", $time, etiqueta, o_leds);
            end
        end
    endtask

    task run_op;
        input [LENGTH_BITS-1:0] a;
        input [LENGTH_BITS-1:0] b;
        input [5:0]             op;
        begin
            load_all(a, b, op);
            check_result("op");
        end
    endtask

    //--------------------------------------------------------------------------
    // Secuencia principal
    //--------------------------------------------------------------------------
    initial begin
        errors     = 0;
        checks     = 0;
        verbose    = 1'b1;
        seed       = 32'd02092026;
        i_switch   = {LENGTH_BITS{1'b0}};
        i_button_1 = 1'b0;
        i_button_2 = 1'b0;
        i_button_3 = 1'b0;
        i_reset    = 1'b0;
        m_A        = {LENGTH_BITS{1'b0}};
        m_B        = {LENGTH_BITS{1'b0}};
        m_opt      = {LENGTH_OPT{1'b0}};

        ops[0] = ADD;  ops[1] = SUB;  ops[2] = AND_;
        ops[3] = OR_;  ops[4] = XOR_; ops[5] = NOR_;
        ops[6] = SRA;  ops[7] = SRL;

        for (i = 0; i < 64; i = i + 1) cov[i] = 0;

        $display("\n==================================================================");
        $display(" TESTBENCH ALU (8 bits, sincronica) - inicio");
        $display(" Semilla aleatoria: %0d  (anotarla para reproducir la corrida)", seed);
        $display("==================================================================\n");

        //----------------------------------------------------------------------
        // TEST 1: reset inicial
        //----------------------------------------------------------------------
        $display("--- TEST 1: reset inicial ---");
        apply_reset;
        // Post-reset: A=B=opt=0, resultado ADD default = 0, zero=1, carry=0, overflow=0
        check_result("post-reset (A=B=opt=0)");
        $display("");

        //----------------------------------------------------------------------
        // TEST 2: carga individual y verificacion combinada
        //----------------------------------------------------------------------
        $display("--- TEST 2: carga de registros ---");
        load_A(8'h12);
        load_B(8'h01);
        load_OPT({2'b0, ADD});
        check_result("carga A=0x12 B=0x01 ADD");

        load_A(8'hFF);
        check_result("recarga A=0xFF (ADD) -> carry esperado");

        load_B(8'h02);
        check_result("recarga B=0x02 (ADD)");
        $display("");

        //----------------------------------------------------------------------
        // TEST 3: reset despues de haber cargado datos
        //----------------------------------------------------------------------
        $display("--- TEST 3: reset limpia los registros ---");
        load_all(8'hAB, 8'hCD, XOR_);
        check_result("pre-reset A=0xAB B=0xCD XOR");
        apply_reset;
        check_result("post-reset: todo en 0, zero=1");
        $display("");

        //----------------------------------------------------------------------
        // TEST 4: sostener el boton varios ciclos
        //
        // Ahora la ALU es sincronica sin edge detector: mientras el boton
        // este apretado, cada flanco de clock captura el switch actual. El
        // valor final guardado es el ultimo que estuvo en los switches antes
        // de soltar el boton. Se verifica ese comportamiento.
        //----------------------------------------------------------------------
        $display("--- TEST 4: boton sostenido -> gana el ultimo switch ---");
        apply_reset;
        load_B(8'h01);
        load_OPT({2'b0, ADD});

        @(negedge i_clk);
        i_switch   = 8'h11;
        i_button_1 = 1'b1;
        @(posedge i_clk);           // captura 0x11
        @(negedge i_clk);
        i_switch = 8'h22;
        @(posedge i_clk);           // captura 0x22
        @(negedge i_clk);
        i_switch = 8'h33;
        @(posedge i_clk);           // captura 0x33
        @(negedge i_clk);
        i_button_1 = 1'b0;
        m_A = 8'h33;
        @(posedge i_clk); #1;
        check_result("boton sostenido: gana el ultimo (A=0x33)");
        $display("");

        //----------------------------------------------------------------------
        // TEST 5: prioridad entre botones
        //----------------------------------------------------------------------
        $display("--- TEST 5: prioridad entre botones (if / else if / else if) ---");
        apply_reset;
        load_all(8'h11, 8'h22, ADD);
        check_result("base A=0x11 B=0x22 ADD");

        // button_1 y button_2 juntos -> solo carga A
        @(negedge i_clk);
        i_switch = 8'hAA; i_button_1 = 1'b1; i_button_2 = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_button_1 = 1'b0; i_button_2 = 1'b0;
        m_A = 8'hAA;
        @(posedge i_clk); #1;
        check_result("btn1+btn2 -> solo carga A");

        // button_2 y button_3 juntos -> solo carga B
        @(negedge i_clk);
        i_switch = 8'h01; i_button_2 = 1'b1; i_button_3 = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_button_2 = 1'b0; i_button_3 = 1'b0;
        m_B = 8'h01;                // opt NO cambia
        @(posedge i_clk); #1;
        check_result("btn2+btn3 -> solo carga B");

        // los tres juntos -> solo carga A
        @(negedge i_clk);
        i_switch = 8'h02;
        i_button_1 = 1'b1; i_button_2 = 1'b1; i_button_3 = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_button_1 = 1'b0; i_button_2 = 1'b0; i_button_3 = 1'b0;
        m_A = 8'h02;
        @(posedge i_clk); #1;
        check_result("btn1+btn2+btn3 -> solo carga A");
        $display("");

        //----------------------------------------------------------------------
        // TEST 6: truncamiento del opcode
        //----------------------------------------------------------------------
        $display("--- TEST 6: truncamiento de opt (8 switches -> 6 bits) ---");
        apply_reset;
        load_A(8'h0C);
        load_B(8'h0A);
        // 8'hE2 = 11100010 -> bits [5:0] = 100010 = SUB. Los 2 bits altos se descartan.
        load_OPT(8'hE2);
        check_result("switch=0xE2 -> opt=100010 (SUB)");
        $display("");

        //----------------------------------------------------------------------
        // TEST 7: barrido de los 64 opcodes posibles
        //----------------------------------------------------------------------
        $display("--- TEST 7: barrido de los 64 opcodes con A=0xF0 B=0x0A ---");
        apply_reset;
        load_A(8'hF0);
        load_B(8'h0A);
        for (i = 0; i < 64; i = i + 1) begin
            load_OPT({2'b0, i[5:0]});
            check_result("barrido");
        end
        $display("");

        //----------------------------------------------------------------------
        // TEST 8: casos borde por operacion (verifica leds + flags)
        //----------------------------------------------------------------------
        $display("--- TEST 8: ADD (carry / overflow / zero) ---");
        run_op(8'h00, 8'h00, ADD);   // 0+0    -> Z=1
        run_op(8'h01, 8'h01, ADD);   // 1+1    -> 2
        run_op(8'hFF, 8'h01, ADD);   // -1 + 1 -> 0, C=1, V=0, Z=1
        run_op(8'hFF, 8'hFF, ADD);   // -1+-1  -> 0xFE, C=1
        run_op(8'h7F, 8'h01, ADD);   // +127+1 -> 0x80, V=1 (overflow con signo)
        run_op(8'h80, 8'h80, ADD);   // -128+-128 -> 0, C=1, V=1, Z=1
        run_op(8'h40, 8'h40, ADD);   // +64+64 -> 0x80, V=1
        run_op(8'hAA, 8'h55, ADD);   // -> 0xFF
        $display("");

        $display("--- TEST 8: SUB (borrow / overflow) ---");
        run_op(8'h00, 8'h00, SUB);   // -> 0, Z=1
        run_op(8'h05, 8'h03, SUB);   // -> 2
        run_op(8'h03, 8'h05, SUB);   // -> 0xFE, C=1 (borrow)
        run_op(8'h00, 8'h01, SUB);   // -> 0xFF, C=1
        run_op(8'h80, 8'h01, SUB);   // -128 - 1 -> 0x7F, V=1
        run_op(8'h7F, 8'hFF, SUB);   // +127 - (-1) -> 0x80, V=1
        run_op(8'hFF, 8'hFF, SUB);   // -> 0, Z=1
        $display("");

        $display("--- TEST 8: AND ---");
        run_op(8'hFF, 8'hFF, AND_);
        run_op(8'hFF, 8'h00, AND_);  // -> 0, Z=1
        run_op(8'hAA, 8'h55, AND_);  // -> 0, Z=1
        run_op(8'hF0, 8'hCC, AND_);  // -> 0xC0
        $display("");

        $display("--- TEST 8: OR ---");
        run_op(8'h00, 8'h00, OR_);   // -> 0, Z=1
        run_op(8'hAA, 8'h55, OR_);   // -> 0xFF
        run_op(8'hF0, 8'h0F, OR_);   // -> 0xFF
        run_op(8'h12, 8'h00, OR_);
        $display("");

        $display("--- TEST 8: XOR ---");
        run_op(8'hFF, 8'hFF, XOR_);  // -> 0, Z=1
        run_op(8'hAA, 8'h55, XOR_);  // -> 0xFF
        run_op(8'h12, 8'h00, XOR_);  // -> 0x12
        run_op(8'hF0, 8'hCC, XOR_);  // -> 0x3C
        $display("");

        $display("--- TEST 8: NOR ---");
        run_op(8'h00, 8'h00, NOR_);  // -> 0xFF
        run_op(8'hFF, 8'h00, NOR_);  // -> 0, Z=1
        run_op(8'hAA, 8'h55, NOR_);  // -> 0, Z=1
        run_op(8'hF0, 8'h0C, NOR_);  // -> 0x03
        $display("");

        // Shift amount = 3 bits bajos de dato_B (rango 0..7)
        $display("--- TEST 8: SRL (desplazamiento logico a derecha) ---");
        run_op(8'hF0, 8'h02, SRL);   // -> 0x3C
        run_op(8'h80, 8'h07, SRL);   // -> 0x01
        run_op(8'hFF, 8'h00, SRL);   // shift 0 -> sin cambios
        run_op(8'h01, 8'h01, SRL);   // -> 0, Z=1
        run_op(8'hAB, 8'h04, SRL);   // -> 0x0A
        $display("");

        $display("--- TEST 8: SRA (desplazamiento aritmetico a derecha) ---");
        run_op(8'hF0, 8'h02, SRA);   // negativo -> 0xFC
        run_op(8'h80, 8'h07, SRA);   // -> 0xFF (todo signo)
        run_op(8'h7F, 8'h01, SRA);   // positivo -> 0x3F
        run_op(8'hFF, 8'h00, SRA);   // shift 0 -> sin cambios
        run_op(8'h80, 8'h01, SRA);   // -> 0xC0
        $display("");

        $display("--- TEST 8: opcodes invalidos (deben dar 0x00, flags en 0) ---");
        run_op(8'h12, 8'h34, 6'b000000);
        run_op(8'h12, 8'h34, 6'b111111);
        run_op(8'h12, 8'h34, 6'b100001);  // pegado a ADD
        run_op(8'h12, 8'h34, 6'b101010);  // SLT en MIPS, aca no implementado
        run_op(8'h12, 8'h34, 6'b101011);
        $display("");

        //----------------------------------------------------------------------
        // TEST 9: vectores aleatorios
        //----------------------------------------------------------------------
        $display("--- TEST 9: %0d vectores aleatorios (%0d%% con opcode valido) ---",
                 N_RANDOM, PCT_OP_VALIDO);
        verbose = 1'b0;
        for (i = 0; i < N_RANDOM; i = i + 1) begin
            load_all(random_data(0), random_data(0), random_op(0));
            check_result("aleatorio");
        end
        verbose = 1'b1;
        $display("Test aleatorio terminado.\n");

        //----------------------------------------------------------------------
        // Cobertura de opcodes
        //----------------------------------------------------------------------
        $display("--- COBERTURA de opcodes validos ---");
        cov_faltantes = 0;
        for (i = 0; i < N_OPS; i = i + 1) begin
            $display("   %0s (%b) : %0d veces", op_name(ops[i]), ops[i], cov[ops[i]]);
            if (cov[ops[i]] == 0) cov_faltantes = cov_faltantes + 1;
        end
        if (cov_faltantes != 0)
            $display("   [AVISO] %0d operaciones nunca se ejercitaron.", cov_faltantes);
        $display("");

        //----------------------------------------------------------------------
        // Resumen
        //----------------------------------------------------------------------
        $display("==================================================================");
        $display(" RESUMEN");
        $display("   Semilla        : %0d", seed);
        $display("   Verificaciones : %0d", checks);
        $display("   Errores        : %0d", errors);
        if (errors == 0)
            $display("   RESULTADO      : *** TODOS LOS TESTS PASARON ***");
        else
            $display("   RESULTADO      : *** %0d TESTS FALLARON ***", errors);
        $display("==================================================================\n");

        #50 $finish;
    end

    //--------------------------------------------------------------------------
    // Timeout de seguridad
    //--------------------------------------------------------------------------
    initial begin
        #5000000;
        $display("[ERROR] Timeout: la simulacion no termino a tiempo.");
        $finish;
    end

endmodule
