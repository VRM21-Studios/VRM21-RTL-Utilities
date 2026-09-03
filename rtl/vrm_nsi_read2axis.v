`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_nsi_read2axis
// Description : NSI read-to-AXI4-Stream bridge.
//
// This module provides a simple read engine that retrieves sequential data
// from an NSI memory-mapped read interface and forwards the retrieved data
// through an AXI4-Stream master interface.
//
// The read operation is controlled externally through a start signal and a
// maximum read address. Data retrieved from the NSI read port is buffered
// internally using the VRM AXI4-Stream FIFO to decouple the NSI read side
// from downstream AXI4-Stream backpressure.
//
// Features:
//   - Parameterized data width
//   - Parameterized address width
//   - Parameterized internal FIFO depth
//   - Sequential NSI read-address generation
//   - Configurable maximum read address
//   - AXI4-Stream master output
//   - AXI4-Stream TVALID/TREADY flow control
//   - TLAST generation for the final requested sample
//   - FIFO-based buffering between NSI and AXI4-Stream interfaces
//   - FIFO almost-full protection to prevent excessive NSI reads
//   - One-cycle synchronization pipeline for NSI read data
//   - Simple FSM-based read control
//
// Operation:
//   1. The controller remains in IDLE until ctrl_start_read is asserted.
//   2. Sequential NSI reads begin from address zero.
//   3. Read requests continue until ctrl_max_addr is reached.
//   4. The final requested read is marked with TLAST after the NSI read
//      latency pipeline.
//   5. Retrieved data is pushed into the internal FIFO.
//   6. AXI4-Stream output is governed by the standard TVALID/TREADY
//      handshake.
//   7. The controller returns to IDLE after the final read request has been
//      issued.
//
// NSI Read Interface:
//   - o_nsi_rd_en   : Read request enable.
//   - o_nsi_rd_addr : Sequential read address.
//   - i_nsi_rd_data : Returned read data.
//
// AXI4-Stream Interface:
//   - m_axis_tdata  : Read data payload.
//   - m_axis_tlast  : Asserted for the final requested sample.
//   - m_axis_tvalid: Indicates valid output data.
//   - m_axis_tready: Downstream ready signal.
//
// Control and Status:
//   - ctrl_start_read : Starts a new sequential read transaction.
//   - ctrl_max_addr   : Last NSI address included in the transaction.
//   - status_busy     : Indicates that the read controller is active.
//
// Notes:
//   - The NSI read path is treated as having a one-clock data latency.
//   - The internal FIFO absorbs AXI4-Stream backpressure so the NSI read
//     engine does not directly depend on m_axis_tready.
//   - NSI read requests are paused when the internal FIFO asserts its
//     almost-full indication.
//   - The final read request is tracked through a one-cycle pipeline so that
//     TLAST remains aligned with the corresponding returned data.
//   - ctrl_max_addr is interpreted as an inclusive final read address.
//   - The internal FIFO is implemented using the reusable vrm_fifo module.
//
// Intended Use:
//   This bridge is intended for moving sequential memory or DSP data from an
//   NSI-based processing core toward AXI4-Stream infrastructure such as DMA,
//   streaming processors, or other FPGA processing pipelines.
// ============================================================================

module vrm_nsi_read2axis #(
    parameter DATA_W = 32,
    parameter ADDR_W = 12,
    parameter FIFO_DEPTH = 4096
)(
    input  wire aclk,
    input  wire aresetn,

    // --- External MMIO Control ---
    input  wire              ctrl_start_read,
    input  wire [ADDR_W-1:0] ctrl_max_addr,
    output wire              status_busy,

    // --- NSI Read Port ---
    output wire              o_nsi_rd_en,
    output wire [ADDR_W-1:0] o_nsi_rd_addr,
    input  wire [DATA_W-1:0] i_nsi_rd_data,

    // --- AXI4-Stream Master ---
    output wire [DATA_W-1:0] m_axis_tdata,
    output wire              m_axis_tlast,
    output wire              m_axis_tvalid,
    input  wire              m_axis_tready
);
    // =========================================================================
    // FSM and Read Address Generator
    // =========================================================================

    localparam IDLE      = 2'd0,
               READ_SRAM = 2'd1,
               WAIT_LAST = 2'd2;

    reg [1:0] state;
    reg [ADDR_W-1:0] rd_addr_cnt;

    wire fifo_almost_full;

    // Pause NSI read requests when the FIFO approaches its capacity limit.
    wire hold_read = fifo_almost_full;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= IDLE;
            rd_addr_cnt <= 0;
        end else begin
            case (state)

                IDLE: begin
                    if (ctrl_start_read) begin
                        state       <= READ_SRAM;
                        rd_addr_cnt <= 0;
                    end
                end

                READ_SRAM: begin
                    if (!hold_read) begin
                        if (rd_addr_cnt == ctrl_max_addr) begin
                            // Allow one additional cycle for the final
                            // read-data pipeline stage.
                            state <= WAIT_LAST;
                        end else begin
                            rd_addr_cnt <= rd_addr_cnt + 1;
                        end
                    end
                end

                WAIT_LAST: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end


    // =========================================================================
    // NSI Read Request Generation
    // =========================================================================

    // Issue a read request while the controller is active and the FIFO
    // is not approaching its configured capacity limit.
    assign o_nsi_rd_en   = (state == READ_SRAM) && !hold_read;
    assign o_nsi_rd_addr = rd_addr_cnt;

    // The controller remains busy until all read requests, including the
    // final pipelined read operation, have completed.
    assign status_busy = (state != IDLE);


    // =========================================================================
    // NSI Read Data Synchronization Pipeline
    // =========================================================================
    //
    // The NSI read interface is modeled as having a one-clock latency.
    // Therefore, each read-enable request is delayed by one clock cycle
    // before the returned data is presented to the FIFO.
    //
    // The final-read indication is propagated through the same pipeline
    // to maintain TLAST alignment with the corresponding data sample.
    // =========================================================================

    reg rd_en_d1;
    reg is_last_d1;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_en_d1   <= 0;
            is_last_d1 <= 0;
        end else begin
            rd_en_d1 <= o_nsi_rd_en;

            // Mark the request associated with the final configured address.
            is_last_d1 <= o_nsi_rd_en &&
                          (rd_addr_cnt == ctrl_max_addr);
        end
    end


    // =========================================================================
    // AXI4-Stream Egress FIFO
    // =========================================================================
    //
    // The FIFO buffers returned NSI read data before forwarding it through
    // the AXI4-Stream master interface.
    //
    // The almost-full indication is fed back to the read controller to
    // temporarily pause additional NSI read requests and prevent excessive
    // FIFO occupancy.
    // =========================================================================

    vrm_fifo #(
        .DATA_WIDTH(DATA_W),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) egress_fifo (
        .aclk(aclk),
        .aresetn(aresetn),

        // Data returned by the NSI interface after the one-clock
        // synchronization pipeline.
        .s_axis_tdata(i_nsi_rd_data),
        .s_axis_tlast(is_last_d1),
        .s_axis_tvalid(rd_en_d1),

        // Backpressure toward the NSI interface is controlled through
        // fifo_almost_full and the hold_read signal.
        .s_axis_tready(),

        .s_axis_almost_full(fifo_almost_full),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready)
    );


endmodule
