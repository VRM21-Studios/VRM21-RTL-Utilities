`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_axis2nsi_write
// Description : AXI4-Stream to Native SRAM Interface (NSI) write bridge with
//               internal FIFO buffering and sequential address generation.
//
// Features:
// - Parameterized data width
// - Parameterized native address width
// - Parameterized ingress FIFO depth
// - AXI4-Stream slave input interface
// - Native write output interface
// - Internal FIFO buffering
// - Downstream backpressure support
// - Sequential native address generation
// - Automatic address reset after TLAST
// - External address-counter reset control
//
// Data Flow:
//   AXI4-Stream Input
//          |
//          v
//   Ingress FIFO
//          |
//          | Pop only when i_nsi_ready is asserted
//          v
//   NSI Write Interface
//
// Backpressure:
// - The internal FIFO absorbs temporary differences between the AXI4-Stream
//   source rate and the native-interface consumption rate.
// - FIFO data is consumed only when both fifo_rvalid and i_nsi_ready are high.
// - AXI4-Stream input readiness is provided by the internal FIFO.
//
// Address Generation:
// - Native addresses begin at zero.
// - The address increments after each accepted FIFO word.
// - The address resets to zero after a word marked with TLAST.
// - ctrl_reset_addr can reset the address counter independently.
//
// Native Interface:
// - o_nsi_wr_en and o_nsi_wr_valid are asserted for each accepted FIFO word.
// - o_nsi_wr_addr contains the current sequential write address.
// - o_nsi_wr_data contains the buffered payload.
// - o_nsi_wr_last preserves the AXI4-Stream TLAST indication.
//
// Dependency:
// - Requires vrm_fifo.
// ============================================================================

module vrm_axis2nsi_write #(
    parameter DATA_W     = 32,   // AXI4-Stream and NSI data width
    parameter ADDR_W     = 12,   // Native write-address width
    parameter FIFO_DEPTH = 4096  // Number of entries in the ingress FIFO
)(
    input  wire              aclk,
    input  wire              aresetn,

    // =========================================================================
    // CONTROL INTERFACE
    // =========================================================================

    // Resets the native write-address counter to zero.
    input  wire              ctrl_reset_addr,

    // =========================================================================
    // AXI4-STREAM SLAVE INTERFACE
    // =========================================================================

    input  wire [DATA_W-1:0] s_axis_tdata,
    input  wire              s_axis_tlast,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready,

    // =========================================================================
    // NATIVE SRAM INTERFACE WRITE PORT
    // =========================================================================

    // Native write-enable pulse.
    output wire              o_nsi_wr_en,

    // Sequential native write address.
    output wire [ADDR_W-1:0] o_nsi_wr_addr,

    // Native write data.
    output wire [DATA_W-1:0] o_nsi_wr_data,

    // Native write-data validity indication.
    output wire              o_nsi_wr_valid,

    // End-of-frame or end-of-buffer indication.
    output wire              o_nsi_wr_last,

    // =========================================================================
    // DOWNSTREAM FLOW CONTROL
    // =========================================================================

    // Indicates that the downstream NSI consumer is ready to accept the
    // currently presented FIFO word.
    input  wire              i_nsi_ready
);

    // =========================================================================
    // INTERNAL FIFO SIGNALS
    // =========================================================================

    // Current FIFO output payload.
    wire [DATA_W-1:0] fifo_rdata;

    // TLAST flag associated with the current FIFO output.
    wire              fifo_rlast;

    // Indicates that the FIFO contains a valid output word.
    wire              fifo_rvalid;

    // =========================================================================
    // FIFO POP CONTROL
    // =========================================================================
    // Consume one FIFO word only when:
    // - The FIFO output is valid.
    // - The downstream NSI consumer is ready.
    //
    // This condition implements the native-side transfer handshake.
    // =========================================================================

    wire fifo_pop =
        fifo_rvalid && i_nsi_ready;

    // =========================================================================
    // INGRESS FIFO
    // =========================================================================
    // Buffers incoming AXI4-Stream data and preserves TLAST alongside each
    // payload word.
    //
    // The FIFO master-side ready input is driven by fifo_pop so that the
    // output pointer advances only after the downstream NSI interface accepts
    // the current word.
    // =========================================================================

    vrm_fifo #(
        .DATA_WIDTH(DATA_W),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) ingress_fifo (
        .aclk               (aclk),
        .aresetn            (aresetn),

        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_almost_full (),

        .m_axis_tdata       (fifo_rdata),
        .m_axis_tlast       (fifo_rlast),
        .m_axis_tvalid      (fifo_rvalid),
        .m_axis_tready      (fifo_pop)
    );

    // =========================================================================
    // NATIVE WRITE ADDRESS GENERATOR
    // =========================================================================
    // The address counter advances after each accepted FIFO transfer.
    //
    // Counter behavior:
    // - Reset or ctrl_reset_addr -> address becomes zero
    // - Accepted non-TLAST word  -> address increments by one
    // - Accepted TLAST word      -> address returns to zero
    // =========================================================================

    reg [ADDR_W-1:0] wr_addr_cnt;

    always @(posedge aclk) begin
        if (!aresetn || ctrl_reset_addr) begin
            wr_addr_cnt <= 0;

        end else if (fifo_pop) begin
            if (fifo_rlast)
                wr_addr_cnt <= 0;
            else
                wr_addr_cnt <= wr_addr_cnt + 1;
        end
    end

    // =========================================================================
    // NATIVE WRITE INTERFACE MAPPING
    // =========================================================================
    // A native write transaction is generated for every FIFO word accepted by
    // the downstream consumer.
    // =========================================================================

    assign o_nsi_wr_en    = fifo_pop;
    assign o_nsi_wr_valid = fifo_pop;

    assign o_nsi_wr_addr  = wr_addr_cnt;
    assign o_nsi_wr_data  = fifo_rdata;
    assign o_nsi_wr_last  = fifo_rlast;

endmodule
