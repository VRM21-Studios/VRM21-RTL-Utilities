`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_dsp_core
// Description : Parameterized DSP arithmetic wrapper with runtime-selectable
//               operation modes and a pipelined datapath.
//
// Features:
// - Runtime operation mode selection
// - Parameterized A, B, and P data widths
// - Pipelined arithmetic datapath
// - Fixed three-cycle valid pipeline
// - Multiply operation
// - Multiply-Add (MADD) operation
// - Multiply-Accumulate (MAC) operation
// - Add operation
// - Explicit accumulator clear control for MAC mode
// - Clock-enable based pipeline control
// - DSP inference guidance through the use_dsp attribute
//
// Operation Modes:
//   2'b00 : MUL  - Multiply only
//   2'b01 : MADD - Multiply followed by addition with C input
//   2'b10 : MAC  - Multiply-Accumulate
//   2'b11 : ADD  - Addition of A and C inputs
//
// Pipeline:
//   Stage 1 : Input capture
//   Stage 2 : Multiplication and operand alignment
//   Stage 3 : Output ALU selection and accumulator update
//
// Latency:
// - Fixed valid latency: 3 clock cycles when CE is active
// - valid_out corresponds to the result generated at the third pipeline stage
//
// MAC Accumulator:
// - In MAC mode, acc_clr selects whether the current multiplication result
//   starts a new accumulation or is added to the existing accumulator value.
//
// Control:
// - The ce input controls advancement of the pipeline and datapath registers.
// - When ce is low, all pipeline state is held.
//
// Reset:
// - Active-low synchronous reset.
// - All pipeline registers and the accumulator are cleared to zero.
// ============================================================================

(* use_dsp = "yes" *)
module vrm_dsp_core #(
    parameter A_WIDTH = 27,  // Width of A input
    parameter B_WIDTH = 18,  // Width of B input
    parameter P_WIDTH = 48   // Width of output and C input
)(
    input wire clk,
    input wire rstn,

    // =========================================================================
    // CONTROL AND CONFIGURATION
    // =========================================================================

    // Runtime operation mode selection:
    // 2'b00 = MUL
    // 2'b01 = MADD
    // 2'b10 = MAC
    // 2'b11 = ADD
    input wire [1:0] mode_sel,

    // Accumulator clear control for MAC mode.
    // When asserted during a valid MAC operation, the current multiplication
    // result becomes the new accumulator value instead of being added to the
    // previous accumulator contents.
    input wire acc_clr,

    // =========================================================================
    // HANDSHAKE AND FLOW CONTROL
    // =========================================================================

    // Clock enable for pipeline advancement.
    input wire ce,

    // Indicates that the input operands and control information are valid.
    input wire valid_in,

    // =========================================================================
    // DATA INPUTS
    // =========================================================================

    input wire signed [A_WIDTH-1:0] a_in,
    input wire signed [B_WIDTH-1:0] b_in,
    input wire signed [P_WIDTH-1:0] c_in,

    // =========================================================================
    // DATA OUTPUTS
    // =========================================================================

    // Indicates that p_out contains the result associated with a valid input.
    output wire valid_out,

    // Arithmetic result output.
    output wire signed [P_WIDTH-1:0] p_out
);

    // =========================================================================
    // 1. VALID PIPELINE
    // -------------------------------------------------------------------------
    // Tracks the validity of input data through the fixed three-stage
    // processing pipeline.
    //
    // valid_in is shifted through the pipeline only while ce is asserted.
    // The final valid bit is exposed as valid_out.
    // =========================================================================

    localparam LATENCY = 3;

    reg [LATENCY-1:0] valid_sr = 0;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_sr <= 0;
        end else if (ce) begin
            valid_sr <= {valid_sr[LATENCY-2:0], valid_in};
        end
    end

    assign valid_out = valid_sr[LATENCY-1];

    // =========================================================================
    // 2. PIPELINED MODE CONTROL
    // -------------------------------------------------------------------------
    // The selected operation mode is delayed through two pipeline registers
    // so that it remains aligned with the corresponding data operands when
    // they reach the final arithmetic stage.
    // =========================================================================

    reg [1:0] mode_stage1 = 2'd0;
    reg [1:0] mode_stage2 = 2'd0;

    always @(posedge clk) begin
        if (!rstn) begin
            mode_stage1 <= 2'd0;
            mode_stage2 <= 2'd0;
        end else if (ce) begin
            mode_stage1 <= mode_sel;
            mode_stage2 <= mode_stage1;
        end
    end

    // =========================================================================
    // 3. PIPELINED DATAPATH REGISTERS
    // -------------------------------------------------------------------------
    // These registers preserve input operands, multiplication results, and
    // delayed operands across the three processing stages.
    //
    // All registers are explicitly initialized to zero to provide deterministic
    // startup behavior in simulation and FPGA initialization contexts supported
    // by the target synthesis flow.
    // =========================================================================

    // Stage 1: Captured input operands.
    reg signed [A_WIDTH-1:0] a_reg1 = 0;
    reg signed [B_WIDTH-1:0] b_reg1 = 0;
    reg signed [P_WIDTH-1:0] c_reg1 = 0;

    // Stage 2: Aligned multiplication and addition operands.
    reg signed [A_WIDTH-1:0]        a_reg2 = 0;
    reg signed [P_WIDTH-1:0]        c_reg2 = 0;
    reg signed [A_WIDTH+B_WIDTH-1:0] m_reg2 = 0;

    // Stage 3: Output register and MAC accumulator.
    reg signed [P_WIDTH-1:0] p_reg = 0;

    // =========================================================================
    // MAIN PIPELINED DATAPATH
    // =========================================================================

    always @(posedge clk) begin
        if (!rstn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------
            // Clear all pipeline registers and the MAC accumulator.
            a_reg1 <= 0;
            b_reg1 <= 0;
            c_reg1 <= 0;

            a_reg2 <= 0;
            c_reg2 <= 0;
            m_reg2 <= 0;

            p_reg <= 0;

        end else if (ce) begin

            // -----------------------------------------------------------------
            // STAGE 1: INPUT CAPTURE
            // -----------------------------------------------------------------
            // Capture input operands when valid_in is asserted.
            //
            // When valid_in is low, the input registers are cleared to zero.
            // This keeps invalid pipeline stages clean and prevents stale input
            // values from propagating through subsequent stages.
            if (valid_in) begin
                a_reg1 <= a_in;
                b_reg1 <= b_in;
                c_reg1 <= c_in;
            end else begin
                a_reg1 <= 0;
                b_reg1 <= 0;
                c_reg1 <= 0;
            end

            // -----------------------------------------------------------------
            // STAGE 2: PARALLEL MULTIPLICATION AND OPERAND ALIGNMENT
            // -----------------------------------------------------------------
            // Perform the A x B multiplication while simultaneously delaying
            // the A and C operands required by the ADD operation.
            //
            // The valid_sr[0] flag indicates that the Stage 1 operands contain
            // valid data for this pipeline stage.
            if (valid_sr[0]) begin
                m_reg2 <= a_reg1 * b_reg1;
                a_reg2 <= a_reg1;
                c_reg2 <= c_reg1;
            end else begin
                // Clear intermediate registers when the pipeline stage is
                // invalid to avoid retaining stale arithmetic data.
                m_reg2 <= 0;
                a_reg2 <= 0;
                c_reg2 <= 0;
            end

            // -----------------------------------------------------------------
            // STAGE 3: ALU MODE SELECTION AND ACCUMULATOR UPDATE
            // -----------------------------------------------------------------
            // Select the requested arithmetic operation using the mode value
            // aligned to the current data pipeline stage.
            //
            // mode_stage2:
            //   2'b00 -> MUL
            //   2'b01 -> MADD
            //   2'b10 -> MAC
            //   2'b11 -> ADD
            if (valid_sr[1]) begin
                case (mode_stage2)

                    // ---------------------------------------------------------
                    // MUL: Multiply only
                    // ---------------------------------------------------------
                    2'd0: begin
                        p_reg <= m_reg2;
                    end

                    // ---------------------------------------------------------
                    // MADD: Multiply + Add
                    // ---------------------------------------------------------
                    2'd1: begin
                        p_reg <= c_reg2 + m_reg2;
                    end

                    // ---------------------------------------------------------
                    // MAC: Multiply-Accumulate
                    //
                    // When acc_clr is asserted, the current multiplication
                    // result becomes the starting value of a new accumulation.
                    //
                    // Otherwise, the new multiplication result is added to
                    // the existing accumulator value.
                    // ---------------------------------------------------------
                    2'd2: begin
                        if (acc_clr)
                            p_reg <= m_reg2;
                        else
                            p_reg <= p_reg + m_reg2;
                    end

                    // ---------------------------------------------------------
                    // ADD: Direct addition of A and C operands
                    // ---------------------------------------------------------
                    2'd3: begin
                        p_reg <= a_reg2 + c_reg2;
                    end

                    // ---------------------------------------------------------
                    // DEFAULT: Fall back to multiplication result
                    // ---------------------------------------------------------
                    default: begin
                        p_reg <= m_reg2;
                    end
                endcase

            end else begin
                // Clear the output register when the current pipeline stage
                // does not contain valid data.
                p_reg <= 0;
            end
        end
    end

    // =========================================================================
    // OUTPUT ASSIGNMENT
    // =========================================================================

    assign p_out = p_reg;

endmodule
