`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_pingpong_ram_core
// Description : Double-buffered (ping-pong) RAM wrapper using two instances
//               of vrm_ram_core.
//
// Architecture:
// - Two independent RAM banks are used as alternating producer/consumer
//   buffers.
// - The active read bank is accessed by the consumer / DSP engine.
// - The inactive bank is available to the producer for writing new data.
// - switch_bank toggles the active read bank.
// - The output bank selector is delayed by one clock cycle to match the
//   one-cycle read latency of vrm_ram_core.
//
// Bank Assignment:
// - active_read_bank = 0:
//     Bank 0 -> Consumer / Read
//     Bank 1 -> Producer / Write
//
// - active_read_bank = 1:
//     Bank 1 -> Consumer / Read
//     Bank 0 -> Producer / Write
//
// Features:
// - Parameterized data width
// - Parameterized address width
// - Configurable RAM inference style
// - Double-buffered memory architecture
// - Shared producer and consumer address interfaces
// - One-cycle latency-aware output bank selection
//
// Control:
// - switch_bank is intended as a one-cycle pulse.
// - active_read_bank indicates which RAM bank is currently assigned to the
//   consumer.
//
// Dependency:
// - Requires vrm_ram_core.
// ============================================================================

module vrm_pingpong_ram_core #(
    parameter DATA_WIDTH = 32,      // User data width in bits
    parameter ADDR_WIDTH = 10,      // Address width
    parameter RAM_STYLE  = "block"  // Vivado RAM inference:
                                   // "ultra", "block", "distributed", or "auto"
)(
    input  wire                  clk,
    input  wire                  rstn,

    // =========================================================================
    // CONTROL INTERFACE
    // =========================================================================

    // One-cycle pulse used to toggle the active read bank.
    input  wire                  switch_bank,

    // Currently active consumer/read bank:
    //   0 = Bank 0 is being read
    //   1 = Bank 1 is being read
    output wire                  active_read_bank,

    // =========================================================================
    // WRITE PORT
    // -------------------------------------------------------------------------
    // Intended for the producer side, such as a streaming input or data
    // generation pipeline.
    // =========================================================================

    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,

    // =========================================================================
    // READ PORT
    // -------------------------------------------------------------------------
    // Intended for the consumer side, such as a DSP processing engine.
    // =========================================================================

    input  wire                  re,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [DATA_WIDTH-1:0] rd_data
);

    // =========================================================================
    // 1. ACTIVE READ BANK CONTROL
    // =========================================================================

    // Selects which RAM bank is currently assigned to the consumer.
    //
    // After reset:
    //   read_bank = 0
    //   Bank 0 -> Consumer / Read
    //   Bank 1 -> Producer / Write
    reg read_bank;

    always @(posedge clk) begin
        if (!rstn) begin
            read_bank <= 1'b0;
        end else if (switch_bank) begin
            read_bank <= ~read_bank;
        end
    end

    // Expose the currently active consumer/read bank.
    assign active_read_bank = read_bank;

    // =========================================================================
    // 2. BANK SIGNAL ROUTING
    // =========================================================================
    // The active bank is reserved for the consumer, while the inactive bank
    // is reserved for producer writes.
    //
    // This allows the producer and consumer to operate on separate buffers
    // without accessing the same RAM bank during normal ping-pong operation.
    // =========================================================================

    // -------------------------------------------------------------------------
    // Bank 0 Routing
    // -------------------------------------------------------------------------

    // Write to Bank 0 only when Bank 1 is currently being read.
    wire we_0 = we && (read_bank == 1'b1);

    // Read from Bank 0 only when Bank 0 is currently active.
    wire re_0 = re && (read_bank == 1'b0);

    // Bank 0 read output.
    wire [DATA_WIDTH-1:0] dout_0;

    // -------------------------------------------------------------------------
    // Bank 1 Routing
    // -------------------------------------------------------------------------

    // Write to Bank 1 only when Bank 0 is currently being read.
    wire we_1 = we && (read_bank == 1'b0);

    // Read from Bank 1 only when Bank 1 is currently active.
    wire re_1 = re && (read_bank == 1'b1);

    // Bank 1 read output.
    wire [DATA_WIDTH-1:0] dout_1;

    // =========================================================================
    // 3. RAM BANK INSTANTIATIONS
    // =========================================================================

    // -------------------------------------------------------------------------
    // Bank 0
    // -------------------------------------------------------------------------

    vrm_ram_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_STYLE(RAM_STYLE)
    ) bank0_inst (
        .clk(clk),
        .rstn(rstn),
        .we(we_0),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .re(re_0),
        .rd_addr(rd_addr),
        .rd_data(dout_0)
    );

    // -------------------------------------------------------------------------
    // Bank 1
    // -------------------------------------------------------------------------

    vrm_ram_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_STYLE(RAM_STYLE)
    ) bank1_inst (
        .clk(clk),
        .rstn(rstn),
        .we(we_1),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .re(re_1),
        .rd_addr(rd_addr),
        .rd_data(dout_1)
    );

    // =========================================================================
    // 4. LATENCY-ALIGNED OUTPUT BANK SELECTOR
    // =========================================================================
    // vrm_ram_core provides registered read data with one clock cycle of
    // read latency.
    //
    // The active bank selector therefore cannot be used directly for the
    // output multiplexer. If read_bank changed immediately after a bank
    // switch, the selector could point to the new bank before its corresponding
    // read data had propagated to the output register.
    //
    // read_bank_q delays the bank selection by one clock cycle so that the
    // output multiplexer remains aligned with the corresponding RAM data.
    // =========================================================================

    reg read_bank_q;

    always @(posedge clk) begin
        if (!rstn) begin
            read_bank_q <= 1'b0;
        end else if (re) begin
            // Capture the bank selection corresponding to the active read
            // transaction and align it with the one-cycle RAM read latency.
            read_bank_q <= read_bank;
        end
    end

    // =========================================================================
    // 5. OUTPUT MULTIPLEXER
    // =========================================================================
    // Select the RAM output corresponding to the bank associated with the
    // current registered read transaction.
    // =========================================================================

    assign rd_data =
        (read_bank_q == 1'b0) ? dout_0 : dout_1;

endmodule
