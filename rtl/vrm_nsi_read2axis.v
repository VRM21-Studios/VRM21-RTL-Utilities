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
