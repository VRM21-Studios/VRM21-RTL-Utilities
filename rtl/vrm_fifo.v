`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_fifo
// Description : Parameterized AXI4-Stream FIFO with First-Word Fall-Through
//               (FWFT) behavior.
//
// Features:
// - Parameterized data width
// - Parameterized FIFO depth
// - AXI4-Stream slave input interface
// - AXI4-Stream master output interface
// - First-Word Fall-Through (FWFT) output behavior
// - TLAST stored together with payload data
// - Almost-full indication for upstream pipeline control
// - Distributed RAM / LUTRAM inference
//
// Data Storage:
// - FIFO memory width = DATA_WIDTH + 1 bit
// - [DATA_WIDTH-1:0] : AXI4-Stream TDATA
// - [DATA_WIDTH]     : AXI4-Stream TLAST
//
// Flow Control:
// - A write (push) occurs when S_AXIS_TVALID and S_AXIS_TREADY are both high.
// - A read (pop) occurs when M_AXIS_TVALID and M_AXIS_TREADY are both high.
// - S_AXIS_TREADY is deasserted when the FIFO is full.
// - S_AXIS_ALMOST_FULL is asserted when only two or fewer entries remain.
//
// Read Behavior:
// - The FIFO uses combinational memory read for FWFT behavior.
// - The first available FIFO word is directly visible at the AXI4-Stream
//   master interface without requiring a separate read request.
//
// Reset:
// - Active-low synchronous reset.
// - FIFO pointers and occupancy counter are cleared during reset.
//
// Note:
// The FIFO memory is explicitly marked for Distributed RAM / LUTRAM inference.
// ============================================================================

module vrm_fifo #(
    parameter integer DATA_WIDTH = 32,   // AXI4-Stream payload width in bits
    parameter integer FIFO_DEPTH = 4096  // Number of entries in the FIFO
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface
    // ------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Asserted when the FIFO occupancy reaches the configured almost-full
    // threshold. Intended to provide upstream pipeline flow-control warning.
    output wire                   s_axis_almost_full,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface
    // ------------------------------------------------------------------------
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready
);

    // =========================================================================
    // FIFO MEMORY
    // =========================================================================

    // Store AXI4-Stream payload and TLAST flag in a single memory word.
    //
    // Memory layout:
    // [DATA_WIDTH-1:0] : TDATA
    // [DATA_WIDTH]     : TLAST
    //
    // Distributed RAM inference is requested to support fast combinational
    // memory reads for the FWFT output path.
    (* ram_style = "distributed" *)
    reg [DATA_WIDTH:0] fifo_mem [0:FIFO_DEPTH-1];

    // =========================================================================
    // FIFO STATE
    // =========================================================================

    // Write pointer selecting the next FIFO entry to be written.
    reg [$clog2(FIFO_DEPTH)-1:0] wr_ptr;

    // Read pointer selecting the current FIFO entry presented at the output.
    reg [$clog2(FIFO_DEPTH)-1:0] rd_ptr;

    // Number of currently occupied FIFO entries.
    reg [$clog2(FIFO_DEPTH):0] fifo_count;

    // =========================================================================
    // SIMULATION INITIALIZATION
    // =========================================================================

    // Initialize FIFO memory and state for deterministic simulation startup.
    integer i;
    initial begin
        for (i = 0; i < FIFO_DEPTH; i = i + 1)
            fifo_mem[i] = 0;

        wr_ptr     = 0;
        rd_ptr     = 0;
        fifo_count = 0;
    end

    // =========================================================================
    // AXI4-STREAM HANDSHAKE EVENTS
    // =========================================================================

    // A push occurs when a valid input transfer is accepted by the FIFO.
    wire push = s_axis_tvalid && s_axis_tready;

    // A pop occurs when the current FIFO output is accepted by the downstream
    // AXI4-Stream receiver.
    wire pop  = m_axis_tvalid && m_axis_tready;

    // =========================================================================
    // FLOW CONTROL
    // =========================================================================

    // Accept new input data while at least one FIFO slot remains available.
    assign s_axis_tready = (fifo_count < FIFO_DEPTH);

    // Assert the almost-full warning when two or fewer FIFO slots remain.
    // This provides upstream logic with early indication to slow or stop
    // producing data before the FIFO becomes completely full.
    assign s_axis_almost_full = (fifo_count >= FIFO_DEPTH - 2);

    // Data is valid whenever at least one FIFO entry is available.
    assign m_axis_tvalid = (fifo_count > 0);

    // =========================================================================
    // FIRST-WORD FALL-THROUGH (FWFT) OUTPUT
    // =========================================================================

    // The current FIFO entry is directly exposed through the output interface.
    //
    // TDATA is driven to zero when the FIFO is empty.
    // TLAST is stored in the most-significant bit of the FIFO memory word.
    assign m_axis_tdata = m_axis_tvalid
                        ? fifo_mem[rd_ptr][DATA_WIDTH-1:0]
                        : {DATA_WIDTH{1'b0}};

    assign m_axis_tlast = fifo_mem[rd_ptr][DATA_WIDTH];

    // =========================================================================
    // FIFO SEQUENTIAL CONTROL
    // =========================================================================

    always @(posedge aclk) begin
        if (!aresetn) begin

            // Clear FIFO pointers and occupancy counter.
            wr_ptr     <= 0;
            rd_ptr     <= 0;
            fifo_count <= 0;

        end else begin

            // -----------------------------------------------------------------
            // WRITE OPERATION
            // -----------------------------------------------------------------
            // Store payload and TLAST flag together, then advance the write
            // pointer to the next FIFO entry.
            if (push) begin
                fifo_mem[wr_ptr] <= {s_axis_tlast, s_axis_tdata};
                wr_ptr <= wr_ptr + 1;
            end

            // -----------------------------------------------------------------
            // READ OPERATION
            // -----------------------------------------------------------------
            // Advance the read pointer when the downstream logic accepts the
            // current FIFO output.
            if (pop) begin
                rd_ptr <= rd_ptr + 1;
            end

            // -----------------------------------------------------------------
            // FIFO OCCUPANCY UPDATE
            // -----------------------------------------------------------------
            // Update the number of stored entries according to the current
            // push/pop combination.
            //
            // push = 1, pop = 0 : FIFO occupancy increases by one
            // push = 0, pop = 1 : FIFO occupancy decreases by one
            // push = 1, pop = 1 : Occupancy remains unchanged
            // push = 0, pop = 0 : Occupancy remains unchanged
            case ({push, pop})
                2'b10 : fifo_count <= fifo_count + 1;
                2'b01 : fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

endmodule
