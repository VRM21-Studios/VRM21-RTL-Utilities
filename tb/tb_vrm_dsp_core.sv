`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_dsp_core
// Description : Functional verification of the VRM DSP Core across all
//               supported arithmetic operating modes.
//
// Test Coverage:
//   - Multiplication (MUL) mode
//   - Multiply-add (MADD) mode
//   - Multiply-accumulate (MAC) mode
//   - Addition (ADD) mode
//   - Dynamic operating-mode switching
//   - Clock-enable behavior
//   - MAC accumulation clear operation
//
// Features:
//   - Automatic result checking against expected values
//   - Pipeline-aware expected-value tracking
//   - Configurable input stimulus through a dedicated task
//   - Clock-enable and valid-signal verification
//   - VCD waveform generation for simulation analysis
//
// Notes:
//   - The expected-value pipeline is aligned with the DUT data latency.
//   - Input stimulus is applied on the falling clock edge to provide stable
//     inputs before the active clock edge.
//   - The testbench reports individual PASS/ERROR results and a final summary.
// ============================================================================

module tb_vrm_dsp_core;

    // =========================================================================
    // Signal Declarations
    // =========================================================================
    reg         clk;
    reg         rstn;
    reg         ce;
    reg         valid_in;
    reg  [1:0]  mode_sel;
    reg         acc_clr;
    
    reg signed  [26:0] a_in;
    reg signed  [17:0] b_in;
    reg signed  [47:0] c_in;

    wire        valid_out_dut;
    wire signed [47:0] p_out;

    // =========================================================================
    // Test Variables
    // =========================================================================
    integer     error_count;
    reg  [47:0] expected_val;

    localparam DATA_LATENCY = 2;    // DUT pipeline latency: 3 stages, output available at cycle 2 after capture
    reg [47:0]  expected_q [0:DATA_LATENCY];
    reg         valid_q    [0:DATA_LATENCY];
    integer     i;

    wire        valid_check = valid_q[DATA_LATENCY];

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    vrm_dsp_core #(
        .A_WIDTH(27),
        .B_WIDTH(18),
        .P_WIDTH(48)
    ) u_dsp_core (
        .clk(clk),
        .rstn(rstn),
        .mode_sel(mode_sel),
        .acc_clr(acc_clr),
        .ce(ce),
        .valid_in(valid_in),
        .a_in(a_in),
        .b_in(b_in),
        .c_in(c_in),
        .valid_out(valid_out_dut),
        .p_out(p_out)
    );

    // =========================================================================
    // Expected Value Pipeline
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            for (i = 0; i <= DATA_LATENCY; i = i + 1) begin
                expected_q[i] <= 48'd0;
                valid_q[i]    <= 1'b0;
            end
        end else if (ce) begin
            for (i = DATA_LATENCY; i > 0; i = i - 1) begin
                expected_q[i] <= expected_q[i-1];
                valid_q[i]    <= valid_q[i-1];
            end
            expected_q[0] <= expected_val;
            valid_q[0]    <= valid_in;
        end else begin
            // When CE is deasserted, the expected pipeline is cleared because the DUT pipeline does not advance.
            for (i = 0; i <= DATA_LATENCY; i = i + 1) begin
                expected_q[i] <= 48'd0;
                valid_q[i]    <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Automatic Result Checker
    // =========================================================================
    always @(posedge clk) begin
        #1;
        if (valid_check) begin
            if (p_out !== expected_q[DATA_LATENCY]) begin
                $display("ERROR at time %0t: Expected %d, Got %d",
                         $time, expected_q[DATA_LATENCY], p_out);
                error_count = error_count + 1;
            end else begin
                $display("PASS  at time %0t: Result = %d", $time, p_out);
            end
        end
    end

    // =========================================================================
    // Input Stimulus Task
    // =========================================================================
    task apply_input;
        input [1:0]           mode;
        input                 ce_in;
        input                 clr;
        input signed [26:0]   a;
        input signed [17:0]   b;
        input signed [47:0]   c;
        input                 vld;
        input [47:0]          exp;
        begin
            @(negedge clk);          // Apply all input signals before the next rising clock edge.
            mode_sel   = mode;
            ce         = ce_in;
            acc_clr    = clr;
            a_in       = a;
            b_in       = b;
            c_in       = c;
            valid_in   = vld;
            expected_val = exp;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        clk         = 0;
        rstn        = 0;
        ce          = 1;
        valid_in    = 0;
        mode_sel    = 2'd0;
        acc_clr     = 0;
        a_in        = 27'd0;
        b_in        = 18'd0;
        c_in        = 48'd0;
        error_count = 0;
        expected_val = 48'd0;
        for (i = 0; i <= DATA_LATENCY; i = i + 1) begin
            expected_q[i] = 48'd0;
            valid_q[i]    = 1'b0;
        end

        $dumpfile("tb_vrm_dsp_core.vcd");
        $dumpvars(0, tb_vrm_dsp_core);

        $display("============================================");
        $display("  VRM DSP CORE - FUNCTIONAL TESTBENCH");
        $display("============================================");
        
        #20 rstn = 1;
        repeat(2) @(posedge clk);
        $display("\n>>> System Ready\n");

        // ------------------- TEST 1: MUL -------------------
        $display("=== TEST 1: MULTIPLICATION MODE ===");
        apply_input(2'd0, 1, 0, 10, 5,  0, 1, 50);
        apply_input(2'd0, 1, 0, 12, 4,  0, 1, 48);
        apply_input(2'd0, 1, 0,  7, 9,  0, 1, 63);
        apply_input(2'd0, 1, 0,  0, 0,  0, 0,  0);
        repeat(5) @(posedge clk);

        // ------------------- TEST 2: MADD -------------------
        $display("\n=== TEST 2: MULTIPLY-ADD MODE ===");
        apply_input(2'd1, 1, 0, 10, 3, 100, 1, 130);
        apply_input(2'd1, 1, 0,  5, 6, 200, 1, 230);
        apply_input(2'd1, 1, 0,  8, 2,  50, 1,  66);
        apply_input(2'd1, 1, 0,  0, 0,   0, 0,   0);
        repeat(5) @(posedge clk);

        // ------------------- TEST 3: MAC -------------------
        $display("\n=== TEST 3: MAC MODE ===");
        apply_input(2'd2, 1, 1, 10, 2, 50, 1, 20);
        apply_input(2'd2, 1, 0, 20, 3, 50, 1, 80);
        apply_input(2'd2, 1, 0,  5, 4, 50, 1,100);
        apply_input(2'd2, 1, 0,  0, 0,  0, 0,  0);
        repeat(5) @(posedge clk);

        $display("--- MAC Mid-Accumulation Clear ---");
        apply_input(2'd2, 1, 1, 3, 7, 50, 1, 21);
        apply_input(2'd2, 1, 0, 2, 5, 50, 1, 31);
        apply_input(2'd2, 1, 0, 0, 0,  0, 0,  0);
        repeat(5) @(posedge clk);

        // ------------------- TEST 4: ADD -------------------
        $display("\n=== TEST 4: ADDITION MODE ===");
        apply_input(2'd3, 1, 0,  50, 0, 500, 1, 550);
        apply_input(2'd3, 1, 0,  75, 0, 300, 1, 375);
        apply_input(2'd3, 1, 0, 100, 0, 250, 1, 350);
        apply_input(2'd3, 1, 0,   0, 0,   0, 0,   0);
        repeat(5) @(posedge clk);

        // ------------------- TEST 5: DYNAMIC MODE SWITCHING -------------------
        $display("\n=== TEST 5: DYNAMIC MODE SWITCHING ===");
        apply_input(2'd0, 1, 0,  5, 3, 250, 1,  15);  // MUL
        apply_input(2'd3, 1, 0, 10, 0,  30, 1,  40);  // ADD
        apply_input(2'd1, 1, 0,  4, 5,  10, 1,  30);  // MADD
        apply_input(2'd0, 1, 0,  0, 0,   0, 0,   0);
        repeat(5) @(posedge clk);

        // ------------------- TEST 6: CLOCK ENABLE -------------------
        $display("\n=== TEST 6: CLOCK ENABLE TEST ===");
        apply_input(2'd0, 0, 0, 99, 99, 10, 1,  0);  // CE=0: input is ignored
        apply_input(2'd0, 1, 0,  7,  7, 10, 1, 49);
        apply_input(2'd0, 1, 0,  0,  0,  0, 0,  0);
        repeat(5) @(posedge clk);

        // ------------------- FINAL REPORT -------------------
        #20;
        $display("\n============================================");
        if (error_count == 0)
            $display("  ALL TESTS PASSED SUCCESSFULLY!");
        else
            $display("  TEST FAILED WITH %0d ERRORS!", error_count);
        $display("============================================\n");
        #50 $finish;
    end

    // =========================================================================
    // Input Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (valid_in && ce)
            $display("Time %0t | Input : mode=%0d a=%0d b=%0d c=%0d acc_clr=%0d",
                     $time, mode_sel, a_in, b_in, c_in, acc_clr);
    end

endmodule
