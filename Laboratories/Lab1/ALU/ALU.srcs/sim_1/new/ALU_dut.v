`timescale 1ns / 1ps
//==============================================================================
// Testbench autoverificable para el modulo ALU
//
// Cubre:
//   1. Estado inicial (registros sin inicializar)
//   2. Carga de dato_A / dato_B / opt via switches + botones
//   3. Prioridad entre botones (button_1 > button_2 > button_3)
//   4. Retencion de valor (latch) al soltar el boton
//   5. Truncamiento de opt (6 bits tomados de 16 switches)
//   6. Barrido de los 64 opcodes posibles
//   7. Casos borde por operacion (ceros, unos, overflow, signo, shifts)
//   8. Test aleatorio con semilla reproducible y opcodes ponderados
//
// El modelo de referencia (alu_ref) describe la ESPECIFICACION de la ALU,
// no la implementacion del DUT. Si el DUT no implementa una operacion, el
// testbench la reporta como error en lugar de darla por buena.
//
// Al final imprime un resumen con checks, errores y cobertura de opcodes.
//==============================================================================

module ALU_dut;

    //--------------------------------------------------------------------------
    // Parametros
    //--------------------------------------------------------------------------
    localparam LENGTH_BITS = 16;
    localparam LENGTH_OPT  = 6;
    localparam SHAMT_BITS  = $clog2(LENGTH_BITS);  // bits de dato_B usados como shift amount
    localparam N_RANDOM    = 500;

    // Porcentaje de vectores aleatorios que usan un opcode VALIDO.
    // El resto sortea los 6 bits libremente para ejercitar el default.
    localparam PCT_OP_VALIDO = 85;

    // Retardos parametrizados: subirlos para simulacion post-implementacion,
    // donde el netlist tiene retardos reales y hay que esperar a que la
    // salida se estabilice antes de muestrear.
    localparam TSETUP = 2;           // switch estable antes de pulsar
    localparam TPRESS = 5;           // ancho del pulso del boton
    localparam THOLD  = 2;           // espera antes de muestrear o_leds

    // Mismos opcodes que el DUT
    localparam [5:0] ADD  = 6'b100000,
                     SUB  = 6'b100010,
                     AND_ = 6'b100100,
                     OR_  = 6'b100101,
                     XOR_ = 6'b100110,
                     NOR_ = 6'b100111,
                     SRA  = 6'b000011,
                     SRL  = 6'b000010;

    localparam N_OPS = 8;            // cantidad de opcodes validos

    //--------------------------------------------------------------------------
    // Senales
    //--------------------------------------------------------------------------
    reg  [15:0] i_switch;
    reg         i_button_1;
    reg         i_button_2;
    reg         i_button_3;
    wire [LENGTH_BITS-1:0] o_leds;

    // Modelo espejo: refleja lo que el DUT deberia tener guardado
    reg [LENGTH_BITS-1:0] m_A;
    reg [LENGTH_BITS-1:0] m_B;
    reg [LENGTH_OPT-1:0]  m_opt;

    // Enteros utilizados para llevar un registro de el testbench
    integer errors;
    integer checks;
    integer i;
    integer seed;                    // semilla del generador aleatorio
    reg     verbose;                 // 1 = imprime tambien los OK

    // Tabla de opcodes validos, para el sorteo ponderado
    reg [5:0] ops [0:N_OPS-1];

    // Cobertura: cuantas veces se ejercito cada uno de los 64 opcodes
    integer cov [0:63];
    integer cov_faltantes;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    ALU #(
        .LENGTH_BITS (LENGTH_BITS),
        .LENGTH_OPT  (LENGTH_OPT)
    ) dut (
        .o_leds     (o_leds),
        .i_switch   (i_switch),
        .i_button_1 (i_button_1),
        .i_button_2 (i_button_2),
        .i_button_3 (i_button_3)
    );

    //--------------------------------------------------------------------------
    // Modelo de referencia (bible model)
    //
    // IMPORTANTE: se escribe a partir de la especificacion de la ALU, no
    // copiando el case del DUT.
    //--------------------------------------------------------------------------
    function [LENGTH_BITS-1:0] alu_ref;
        input [LENGTH_BITS-1:0] a;
        input [LENGTH_BITS-1:0] b;
        input [LENGTH_OPT-1:0]  op;
        begin
            case (op)
                ADD:  alu_ref = a + b;
                SUB:  alu_ref = a - b;
                AND_: alu_ref = a & b;
                OR_:  alu_ref = a | b;
                XOR_: alu_ref = a ^ b;
                NOR_: alu_ref = ~(a | b);
                SRA:  alu_ref = $signed(a) >>> b[SHAMT_BITS-1:0];
                SRL:  alu_ref = a >> b[SHAMT_BITS-1:0];
                default: alu_ref = 16'd0;   // opcode no definido -> salida en 0
            endcase
        end
    endfunction

    // Nombre legible del opcode, para los mensajes
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
    //--------------------------------------------------------------------------

    // Carga dato_A: pone el valor en los switches y pulsa el boton 1
    task load_A;
        input [15:0] v;
        begin
            i_switch = v;
            #TSETUP i_button_1 = 1'b1;
            #TPRESS i_button_1 = 1'b0;
            #THOLD;
            m_A = v;
        end
    endtask

    task load_B;
        input [15:0] v;
        begin
            i_switch = v;
            #TSETUP i_button_2 = 1'b1;
            #TPRESS i_button_2 = 1'b0;
            #THOLD;
            m_B = v;
        end
    endtask

    // Solo los 6 bits bajos del switch llegan a opt
    task load_OPT;
        input [15:0] v;
        begin
            i_switch = v;
            #TSETUP i_button_3 = 1'b1;
            #TPRESS i_button_3 = 1'b0;
            #THOLD;
            m_opt = v[LENGTH_OPT-1:0];
        end
    endtask

    // Carga los tres registros de una
    task load_all;
        input [15:0] a;
        input [15:0] b;
        input [5:0]  op;
        begin
            load_A(a);
            load_B(b);
            load_OPT({10'b0, op});
        end
    endtask

    //--------------------------------------------------------------------------
    // Generacion aleatoria
    //--------------------------------------------------------------------------

    // Sortea un opcode: PCT_OP_VALIDO % de las veces devuelve una operacion
    // implementada, el resto sortea los 6 bits para ejercitar el default.
    // Sin esto, un sorteo plano de 6 bits acierta una operacion valida solo
    // en 9 de 64 casos y el 86% de los vectores no prueba nada util.
    function [5:0] random_op;
        input dummy;
        begin
            if (({$random(seed)} % 100) < PCT_OP_VALIDO)
                random_op = ops[{$random(seed)} % N_OPS];
            else
                random_op = $random(seed);
        end
    endfunction

    // Palabra de 16 bits aleatoria, con sesgo hacia valores borde:
    // 0x0000, 0xFFFF, 0x8000 y 0x7FFF aparecen mas seguido que por azar puro.
    function [15:0] random_data;
        input dummy;
        integer r;
        begin
            r = {$random(seed)} % 100;
            if      (r < 5)  random_data = 16'h0000;
            else if (r < 10) random_data = 16'hFFFF;
            else if (r < 15) random_data = 16'h8000;
            else if (r < 20) random_data = 16'h7FFF;
            else             random_data = $random(seed);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Tareas de verificacion
    //--------------------------------------------------------------------------

    // Compara la salida contra el modelo de referencia.
    // Los FAIL se imprimen siempre; los OK solo si verbose = 1.
    task check_result;
        input [8*40-1:0] etiqueta;
        reg [LENGTH_BITS-1:0] esperado;
        begin
            esperado = alu_ref(m_A, m_B, m_opt);
            checks   = checks + 1;
            if (^m_opt !== 1'bx) cov[m_opt] = cov[m_opt] + 1;

            if (o_leds !== esperado) begin
                errors = errors + 1;
                $display("[FAIL] t=%0t %0s | op=%b (%0s) A=0x%h B=0x%h | esperado=0x%h obtenido=0x%h",
                         $time, etiqueta, m_opt, op_name(m_opt), m_A, m_B, esperado, o_leds);
            end
            else if (verbose) begin
                $display("[ OK ] t=%0t %0s | op=%b (%0s) A=0x%h B=0x%h | leds=0x%h (%0d dec, %0d signed)",
                         $time, etiqueta, m_opt, op_name(m_opt), m_A, m_B,
                         o_leds, o_leds, $signed(o_leds));
            end
        end
    endtask

    // Compara la salida contra un valor esperado explicito (no usa el modelo)
    task check_value;
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

    // Ejecuta una operacion completa: carga A, B, opcode y verifica
    task run_op;
        input [15:0] a;
        input [15:0] b;
        input [5:0]  op;
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
        seed       = 32'd02092026;      // cambiar para otra corrida aleatoria
        i_switch   = 16'h0000;
        i_button_1 = 1'b0;
        i_button_2 = 1'b0;
        i_button_3 = 1'b0;
        m_A        = 16'hxxxx;
        m_B        = 16'hxxxx;
        m_opt      = 6'bxxxxxx;

        ops[0] = ADD;  ops[1] = SUB;  ops[2] = AND_;
        ops[3] = OR_;  ops[4] = XOR_; ops[5] = NOR_;
        ops[6] = SRA;  ops[7] = SRL;

        for (i = 0; i < 64; i = i + 1) cov[i] = 0;

        $display("\n==================================================================");
        $display(" TESTBENCH ALU - inicio");
        $display(" Semilla aleatoria: %0d  (anotarla para reproducir la corrida)", seed);
        $display("==================================================================\n");

        //----------------------------------------------------------------------
        // TEST 1: estado inicial
        //----------------------------------------------------------------------
        $display("--- TEST 1: estado inicial (sin cargar nada) ---");
        #20;
        // Los registros arrancan en X. Como opt=X no coincide con ningun item
        // del case, se toma el default y la salida es 0x0000 en lugar de X.
        // Es decir: el 0 de arranque es indistinguible de un resultado valido.
        if (o_leds === {LENGTH_BITS{1'bx}})
            $display("[INFO] t=%0t Salida indefinida (X): los registros no tienen reset.", $time);
        else
            $display("[INFO] t=%0t Salida = 0x%h sin haber cargado nada (default del case).", $time, o_leds);
        $display("");

        //----------------------------------------------------------------------
        // TEST 2: carga individual de cada registro
        //----------------------------------------------------------------------
        $display("--- TEST 2: carga de registros ---");
        load_A(16'h1234);
        load_B(16'h0001);
        load_OPT({10'b0, ADD});
        check_value("carga A=0x1234 B=0x0001 ADD", 16'h1235);

        load_A(16'hFFFF);
        check_value("recarga A=0xFFFF (ADD)", 16'h0000);   // overflow: 0xFFFF+1

        load_B(16'h0002);
        check_value("recarga B=0x0002 (ADD)", 16'h0001);
        $display("");

        //----------------------------------------------------------------------
        // TEST 3: retencion de valor al soltar el boton (latch)
        //----------------------------------------------------------------------
        $display("--- TEST 3: retencion de valor (latch) ---");
        load_all(16'h00F0, 16'h000F, OR_);
        check_value("A=0x00F0 B=0x000F OR", 16'h00FF);

        // Cambio los switches sin tocar ningun boton: la salida NO debe cambiar
        i_switch = 16'hDEAD; #10;
        check_value("switch cambia sin botones -> sin efecto", 16'h00FF);

        i_switch = 16'h0000; #10;
        check_value("switch en 0 sin botones -> sin efecto", 16'h00FF);

        // Transparencia: con el boton apretado el latch sigue el switch, asi
        // que queda guardado el ULTIMO valor presente antes de soltarlo.
        i_switch = 16'h1111;
        #TSETUP i_button_1 = 1'b1;
        #3      i_switch   = 16'h2222;   // cambia con el boton todavia apretado
        #3      i_button_1 = 1'b0;
        #THOLD;
        m_A = 16'h2222;
        check_result("latch transparente (gana el ultimo valor)");
        $display("");

        //----------------------------------------------------------------------
        // TEST 4: prioridad entre botones
        //----------------------------------------------------------------------
        $display("--- TEST 4: prioridad entre botones ---");
        load_all(16'h1111, 16'h2222, ADD);
        check_value("base A=0x1111 B=0x2222 ADD", 16'h3333);

        // button_1 y button_2 juntos -> solo carga A (prioridad del if)
        i_switch = 16'hAAAA;
        #TSETUP i_button_1 = 1'b1; i_button_2 = 1'b1;
        #TPRESS i_button_1 = 1'b0; i_button_2 = 1'b0;
        #THOLD;
        m_A = 16'hAAAA;   // B NO se modifica
        check_value("btn1+btn2 -> solo carga A", 16'hCCCC);  // AAAA + 2222

        // button_2 y button_3 juntos -> solo carga B
        i_switch = 16'h0001;
        #TSETUP i_button_2 = 1'b1; i_button_3 = 1'b1;
        #TPRESS i_button_2 = 1'b0; i_button_3 = 1'b0;
        #THOLD;
        m_B = 16'h0001;   // opt NO se modifica, sigue siendo ADD
        check_value("btn2+btn3 -> solo carga B", 16'hAAAB);

        // los tres a la vez -> solo carga A
        i_switch = 16'h0002;
        #TSETUP i_button_1 = 1'b1; i_button_2 = 1'b1; i_button_3 = 1'b1;
        #TPRESS i_button_1 = 1'b0; i_button_2 = 1'b0; i_button_3 = 1'b0;
        #THOLD;
        m_A = 16'h0002;
        check_value("btn1+btn2+btn3 -> solo carga A", 16'h0003);
        $display("");

        //----------------------------------------------------------------------
        // TEST 5: truncamiento del opcode
        //----------------------------------------------------------------------
        $display("--- TEST 5: truncamiento de opt (16 switches -> 6 bits) ---");
        load_A(16'h000C);
        load_B(16'h000A);
        // 16'hFFE2 -> bits [5:0] = 100010 = SUB. Los 10 bits altos se descartan.
        load_OPT(16'hFFE2);
        check_value("switch=0xFFE2 -> opt=100010 (SUB)", 16'h0002);
        $display("");

        //----------------------------------------------------------------------
        // TEST 6: barrido de los 64 opcodes posibles
        //----------------------------------------------------------------------
        $display("--- TEST 6: barrido de los 64 opcodes con A=0x00F0 B=0x000F ---");
        load_A(16'h00F0);
        load_B(16'h000F);
        for (i = 0; i < 64; i = i + 1) begin
            load_OPT({10'b0, i[5:0]});
            check_result("barrido");
        end
        $display("");

        //----------------------------------------------------------------------
        // TEST 7: casos borde por operacion
        //----------------------------------------------------------------------
        $display("--- TEST 7: ADD ---");
        run_op(16'h0000, 16'h0000, ADD);   // 0 + 0
        run_op(16'h0001, 16'h0001, ADD);   // 1 + 1
        run_op(16'hFFFF, 16'h0001, ADD);   // overflow -> 0x0000
        run_op(16'hFFFF, 16'hFFFF, ADD);   // 0xFFFE con carry perdido
        run_op(16'h7FFF, 16'h0001, ADD);   // overflow con signo -> 0x8000
        run_op(16'h8000, 16'h8000, ADD);   // -32768 + -32768 -> 0x0000
        run_op(16'hAAAA, 16'h5555, ADD);   // -> 0xFFFF
        $display("");

        $display("--- TEST 7: SUB ---");
        run_op(16'h0000, 16'h0000, SUB);
        run_op(16'h0005, 16'h0003, SUB);   // 2
        run_op(16'h0003, 16'h0005, SUB);   // underflow -> 0xFFFE
        run_op(16'h0000, 16'h0001, SUB);   // -> 0xFFFF
        run_op(16'h8000, 16'h0001, SUB);   // -> 0x7FFF
        run_op(16'hFFFF, 16'hFFFF, SUB);   // -> 0x0000
        $display("");

        $display("--- TEST 7: AND ---");
        run_op(16'hFFFF, 16'hFFFF, AND_);
        run_op(16'hFFFF, 16'h0000, AND_);
        run_op(16'hAAAA, 16'h5555, AND_);  // -> 0x0000
        run_op(16'hF0F0, 16'hFF00, AND_);  // -> 0xF000
        $display("");

        $display("--- TEST 7: OR ---");
        run_op(16'h0000, 16'h0000, OR_);
        run_op(16'hAAAA, 16'h5555, OR_);   // -> 0xFFFF
        run_op(16'hF0F0, 16'h0F0F, OR_);   // -> 0xFFFF
        run_op(16'h1234, 16'h0000, OR_);
        $display("");

        $display("--- TEST 7: XOR ---");
        run_op(16'hFFFF, 16'hFFFF, XOR_);  // -> 0x0000
        run_op(16'hAAAA, 16'h5555, XOR_);  // -> 0xFFFF
        run_op(16'h1234, 16'h0000, XOR_);  // -> 0x1234
        run_op(16'hF0F0, 16'hFF00, XOR_);  // -> 0x0FF0
        $display("");

        $display("--- TEST 7: NOR ---");
        run_op(16'h0000, 16'h0000, NOR_);  // -> 0xFFFF
        run_op(16'hFFFF, 16'h0000, NOR_);  // -> 0x0000
        run_op(16'hAAAA, 16'h5555, NOR_);  // -> 0x0000
        run_op(16'hF0F0, 16'h0F00, NOR_);  // -> 0x000F
        $display("");

        // El shift amount son los 4 bits bajos de dato_B (0..15)
        $display("--- TEST 7: SRL (desplazamiento logico a derecha) ---");
        run_op(16'hF000, 16'h0002, SRL);   // -> 0x3C00
        run_op(16'h8000, 16'h000F, SRL);   // -> 0x0001
        run_op(16'hFFFF, 16'h0000, SRL);   // shift 0 -> sin cambios
        run_op(16'h0001, 16'h0001, SRL);   // -> 0x0000
        run_op(16'hABCD, 16'h0004, SRL);   // -> 0x0ABC
        $display("");

        $display("--- TEST 7: SRA (desplazamiento aritmetico a derecha) ---");
        run_op(16'hF000, 16'h0002, SRA);   // negativo -> 0xFC00
        run_op(16'h8000, 16'h000F, SRA);   // -> 0xFFFF (todo signo)
        run_op(16'h7FFF, 16'h0001, SRA);   // positivo -> 0x3FFF
        run_op(16'hFFFF, 16'h0000, SRA);   // shift 0 -> sin cambios
        run_op(16'h8000, 16'h0001, SRA);   // -> 0xC000
        $display("");

        $display("--- TEST 7: opcodes invalidos (deben dar 0x0000) ---");
        run_op(16'h1234, 16'h5678, 6'b000000);
        run_op(16'h1234, 16'h5678, 6'b111111);
        run_op(16'h1234, 16'h5678, 6'b100001);  // pegado a ADD
        run_op(16'h1234, 16'h5678, 6'b101010);  // funct de SLT en MIPS, aca no implementado
        run_op(16'h1234, 16'h5678, 6'b101011);
        $display("");

        //----------------------------------------------------------------------
        // TEST 8: vectores aleatorios
        //----------------------------------------------------------------------
        $display("--- TEST 8: %0d vectores aleatorios (%0d%% con opcode valido) ---",
                 N_RANDOM, PCT_OP_VALIDO);
        verbose = 1'b0;                 // solo se imprimen los FAIL
        for (i = 0; i < N_RANDOM; i = i + 1) begin
            load_all(random_data(0), random_data(0), random_op(0));
            check_result("aleatorio");
            #(({$random(seed)} % 5) + 1);   // separacion variable entre vectores
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
        $display("   Semilla        : %0d", 32'd20260830);
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
        #500000;
        $display("[ERROR] Timeout: la simulacion no termino a tiempo.");
        $finish;
    end

endmodule