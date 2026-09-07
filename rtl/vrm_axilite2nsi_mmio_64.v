`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_axilite2nsi_mmio_64
// Description : AXI4-Lite to Native SRAM Interface (NSI) MMIO bridge.
//
// This module bridges AXI4-Lite read and write transactions to a simple
// native memory-mapped interface.
//
// A shared native address bus is used for both read and write operations.
// The internal read and write controllers therefore include transaction
// arbitration to prevent overlapping access to the native interface.
//
// Features:
//   - Parameterized AXI4-Lite data width
//   - Parameterized AXI4-Lite address width
//   - Independent AXI4-Lite read and write state machines
//   - Shared native MMIO address interface
//   - Read/write transaction arbitration
//   - Protection against simultaneous native address ownership
//   - Single-cycle native write-enable pulse
//   - One-cycle native read wait stage
//   - AXI4-Lite OKAY responses
//
// Write Operation:
//
//   1. The controller waits for both AXI write address and write data.
//   2. A write transaction is accepted only while the read controller is idle.
//   3. The address and data are captured internally.
//   4. A single-cycle native write-enable pulse is generated.
//   5. An AXI4-Lite write response is returned.
//
// Read Operation:
//
//   1. The controller waits for an AXI read-address transaction.
//   2. A read transaction is accepted only while the write controller is idle.
//   3. The read address is captured internally.
//   4. A one-cycle wait stage allows the native interface to produce data.
//   5. The returned native data is forwarded through the AXI4-Lite read channel.
//
// Native Interface:
//   - mmio_we    : Single-cycle native write-enable pulse.
//   - mmio_addr  : Shared native read/write address.
//   - mmio_wdata : Native write data.
//   - mmio_rdata : Native read data.
//
// Assumptions:
//   - The native interface does not provide ready, valid, or error signals.
//   - Native read data becomes valid after the configured one-cycle read wait.
//   - AXI4-Lite write transactions require AWVALID and WVALID to be asserted
//     simultaneously before they are accepted.
//   - AXI4-Lite responses are always returned as OKAY.
//   - Write strobes are present at the AXI4-Lite interface but are not
//     currently applied to the native write data.
//
// Reset:
//   - Active-low synchronous reset.
//
// Notes:
//   - Read and write transactions are intentionally serialized before reaching
//     the shared native interface.
//   - The arbitration mechanism prevents simultaneous ownership of mmio_addr
//     by independent read and write transactions.
// ============================================================================

module vrm_axilite2nsi_mmio_64 #(
    parameter integer C_S_AXI_DATA_WIDTH = 64,
    parameter integer C_S_AXI_ADDR_WIDTH = 64
)(
    input  wire                                  s_axi_aclk,
    input  wire                                  s_axi_aresetn,

    // =========================================================================
    // AXI4-Lite Write Channels
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr,
    input  wire                                  s_axi_awvalid,
    output reg                                   s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]         s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb,
    input  wire                                  s_axi_wvalid,
    output reg                                   s_axi_wready,

    output wire [1:0]                            s_axi_bresp,
    output reg                                   s_axi_bvalid,
    input  wire                                  s_axi_bready,

    // =========================================================================
    // AXI4-Lite Read Channels
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr,
    input  wire                                  s_axi_arvalid,
    output reg                                   s_axi_arready,

    output reg  [C_S_AXI_DATA_WIDTH-1:0]         s_axi_rdata,
    output wire [1:0]                            s_axi_rresp,
    output reg                                   s_axi_rvalid,
    input  wire                                  s_axi_rready,

    // =========================================================================
    // Native SRAM Interface
    // =========================================================================

    // Native write-enable pulse.
    output wire                                  mmio_we,

    // Shared native address for read and write operations.
    output wire [C_S_AXI_ADDR_WIDTH-1:0]         mmio_addr,

    // Native write data.
    output wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_wdata,

    // Native read data.
    input  wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_rdata
);

    // =========================================================================
    // AXI4-Lite Response Values
    // =========================================================================
    //
    // Both read and write transactions always return an OKAY response.
    // =========================================================================

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;


    // =========================================================================
    // State Encoding
    // =========================================================================

    // Write controller states.
    localparam W_IDLE = 2'd0,
               W_WE   = 2'd1,
               W_RESP = 2'd2;

    // Read controller states.
    localparam R_IDLE  = 2'd0,
               R_WAIT  = 2'd1,
               R_VALID = 2'd2;


    // =========================================================================
    // Internal Transaction State
    // =========================================================================

    reg [1:0] w_state;
    reg [1:0] r_state;

    // Captured AXI4-Lite write address.
    reg [C_S_AXI_ADDR_WIDTH-1:0] w_addr;

    // Captured AXI4-Lite write data.
    reg [C_S_AXI_DATA_WIDTH-1:0] w_data;

    // Captured AXI4-Lite read address.
    reg [C_S_AXI_ADDR_WIDTH-1:0] r_addr;

    // Registered native write-enable signal.
    reg mmio_we_reg;


    // =========================================================================
    // AXI4-Lite Write Controller
    // =========================================================================
    //
    // The write controller accepts a transaction only when both the AXI write
    // address and write data are available and the read controller is idle.
    //
    // This prevents concurrent read and write transactions from competing for
    // ownership of the shared native address interface.
    // =========================================================================

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------

            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;

            mmio_we_reg   <= 1'b0;
            w_state       <= W_IDLE;

        end else begin

            // Default inactive state ensures that mmio_we is asserted for
            // exactly one clock cycle.
            mmio_we_reg <= 1'b0;

            case (w_state)

                // =============================================================
                // W_IDLE: Wait for a Complete Write Transaction
                // =============================================================
                W_IDLE: begin

                    // Accept the write address and write data only when both
                    // channels are valid and the read controller is inactive.
                    if (s_axi_awvalid &&
                        s_axi_wvalid  &&
                        r_state == R_IDLE) begin

                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;

                        w_addr        <= s_axi_awaddr;
                        w_data        <= s_axi_wdata;

                        w_state       <= W_WE;
                    end
                end


                // =============================================================
                // W_WE: Issue Native Write Operation
                // =============================================================
                W_WE: begin

                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;

                    // Generate a single-cycle write-enable pulse toward the
                    // native MMIO interface.
                    mmio_we_reg <= 1'b1;

                    w_state <= W_RESP;
                end


                // =============================================================
                // W_RESP: Return AXI4-Lite Write Response
                // =============================================================
                W_RESP: begin

                    s_axi_bvalid <= 1'b1;

                    // Complete the AXI4-Lite write-response handshake.
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end

            endcase
        end
    end


    // =========================================================================
    // AXI4-Lite Read Controller
    // =========================================================================
    //
    // The read controller accepts a transaction only while the write
    // controller is idle.
    //
    // Once the read address has been captured, the controller reserves the
    // shared native address interface for the read operation until the native
    // read data has been captured and returned through AXI4-Lite.
    // =========================================================================

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------

            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 0;

            r_state       <= R_IDLE;

        end else begin

            case (r_state)

                // =============================================================
                // R_IDLE: Wait for an AXI4-Lite Read Address
                // =============================================================
                R_IDLE: begin

                    // Accept a new read address only when the write controller
                    // is inactive, ensuring exclusive ownership of the shared
                    // native address interface.
                    if (s_axi_arvalid && w_state == W_IDLE) begin
                        s_axi_arready <= 1'b1;

                        r_addr        <= s_axi_araddr;

                        r_state       <= R_WAIT;
                    end
                end


                // =============================================================
                // R_WAIT: Wait for Native Read Data
                // =============================================================
                R_WAIT: begin

                    s_axi_arready <= 1'b0;

                    // The captured read address is presented through
                    // mmio_addr during this stage.
                    //
                    // This state provides one clock cycle for the native
                    // memory or register interface to produce valid data.
                    r_state <= R_VALID;
                end


                // =============================================================
                // R_VALID: Return AXI4-Lite Read Data
                // =============================================================
                R_VALID: begin

                    // Capture native read data and assert AXI read valid.
                    s_axi_rvalid <= 1'b1;
                    s_axi_rdata  <= mmio_rdata;

                    // Complete the AXI4-Lite read-data handshake.
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end

            endcase
        end
    end


    // =========================================================================
    // Native Interface Multiplexer
    // =========================================================================
    //
    // The shared native address bus is driven by the write address only during
    // the active native write operation.
    //
    // During all other cycles, the captured read address is presented.
    //
    // Read/write arbitration in the two controllers prevents overlapping
    // transactions from competing for ownership of this interface.
    // =========================================================================

    assign mmio_we    = mmio_we_reg;
    assign mmio_wdata = w_data;

    assign mmio_addr =
        mmio_we_reg ? w_addr : r_addr;

endmodule