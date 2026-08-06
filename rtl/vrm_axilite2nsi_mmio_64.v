`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_axilite2nsi_mmio_64
// Description : AXI4-Lite to Native SRAM Interface (NSI) MMIO bridge.
//
// Features:
// - Parameterized AXI4-Lite data width
// - Parameterized AXI4-Lite address width
// - Independent AXI4-Lite read and write state machines
// - Captures AW and W channels independently
// - Generates a single-cycle native write-enable pulse
// - Supports a one-cycle native read wait stage
// - Returns AXI4-Lite OKAY responses
//
// Native Interface:
// - mmio_we    : Single-cycle write-enable pulse
// - mmio_addr  : Native MMIO address
// - mmio_wdata : Native write data
// - mmio_rdata : Native read data
//
// Write Transaction Flow:
//   W_IDLE
//     |
//     | Capture AXI AW and W channels
//     v
//   W_ACCEPT
//     |
//     | Assert mmio_we for one clock cycle
//     v
//   W_RESP
//     |
//     | Return AXI write response
//     v
//   W_IDLE
//
// Read Transaction Flow:
//   R_IDLE
//     |
//     | Capture AXI read address
//     v
//   R_WAIT
//     |
//     | Present address and wait one clock cycle
//     v
//   R_SEND
//     |
//     | Capture native read data and return AXI response
//     v
//   R_IDLE
//
// Assumptions:
// - The native read interface provides valid read data after the R_WAIT stage.
// - The native interface does not provide ready, valid, or error signals.
// - AXI4-Lite responses are always returned as OKAY.
// - Write strobes are accepted by the AXI interface but are not currently
//   applied to mmio_wdata.
//
// Reset:
// - Active-low synchronous reset.
// ============================================================================

module vrm_axilite2nsi_mmio_64 #(
    parameter integer C_S_AXI_DATA_WIDTH = 64, // AXI4-Lite data width
    parameter integer C_S_AXI_ADDR_WIDTH = 64  // AXI4-Lite address width
)(
    input  wire                                  s_axi_aclk,
    input  wire                                  s_axi_aresetn,

    // =========================================================================
    // AXI4-LITE WRITE ADDRESS CHANNEL
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr,
    input  wire                                  s_axi_awvalid,
    output reg                                   s_axi_awready,

    // =========================================================================
    // AXI4-LITE WRITE DATA CHANNEL
    // =========================================================================

    input  wire [C_S_AXI_DATA_WIDTH-1:0]         s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb,
    input  wire                                  s_axi_wvalid,
    output reg                                   s_axi_wready,

    // =========================================================================
    // AXI4-LITE WRITE RESPONSE CHANNEL
    // =========================================================================

    output wire [1:0]                            s_axi_bresp,
    output reg                                   s_axi_bvalid,
    input  wire                                  s_axi_bready,

    // =========================================================================
    // AXI4-LITE READ ADDRESS CHANNEL
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr,
    input  wire                                  s_axi_arvalid,
    output reg                                   s_axi_arready,

    // =========================================================================
    // AXI4-LITE READ DATA CHANNEL
    // =========================================================================

    output reg  [C_S_AXI_DATA_WIDTH-1:0]         s_axi_rdata,
    output wire [1:0]                            s_axi_rresp,
    output reg                                   s_axi_rvalid,
    input  wire                                  s_axi_rready,

    // =========================================================================
    // NATIVE SRAM INTERFACE (NSI)
    // =========================================================================

    // Native write-enable pulse.
    output wire                                  mmio_we,

    // Shared native read/write address.
    output wire [C_S_AXI_ADDR_WIDTH-1:0]         mmio_addr,

    // Native write data.
    output wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_wdata,

    // Native read data.
    input  wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_rdata
);

    // =========================================================================
    // AXI4-LITE RESPONSE VALUES
    // =========================================================================
    // Both read and write transactions always return an OKAY response.
    // =========================================================================

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    // =========================================================================
    // WRITE STATE ENCODING
    // =========================================================================

    localparam W_IDLE   = 2'd0;
    localparam W_ACCEPT = 2'd1;
    localparam W_RESP   = 2'd2;

    // =========================================================================
    // READ STATE ENCODING
    // =========================================================================

    localparam R_IDLE = 2'd0;
    localparam R_WAIT = 2'd1;
    localparam R_SEND = 2'd2;

    // =========================================================================
    // WRITE CHANNEL STATE
    // =========================================================================

    // Current write state.
    reg [1:0] w_state;

    // Captured AXI4-Lite write address.
    reg [C_S_AXI_ADDR_WIDTH-1:0] w_addr;

    // Captured AXI4-Lite write data.
    reg [C_S_AXI_DATA_WIDTH-1:0] w_data;

    // =========================================================================
    // READ CHANNEL STATE
    // =========================================================================

    // Current read state.
    reg [1:0] r_state;

    // Captured AXI4-Lite read address.
    reg [C_S_AXI_ADDR_WIDTH-1:0] r_addr;

    // =========================================================================
    // NATIVE INTERFACE DRIVER
    // -------------------------------------------------------------------------
    // The native MMIO signals are generated combinationally from the captured
    // AXI transaction state.
    // =========================================================================

    // Assert the native write-enable signal only during W_ACCEPT.
    //
    // This produces a single-cycle write pulse after both the AXI write address
    // and write data channels have been accepted.
    assign mmio_we = (w_state == W_ACCEPT);

    // Drive native write data from the captured AXI write-data register.
    assign mmio_wdata = w_data;

    // Select the native address source.
    //
    // During W_ACCEPT, the captured write address is presented.
    // During all other states, the captured read address is presented.
    assign mmio_addr =
        (w_state == W_ACCEPT) ? w_addr : r_addr;

    // =========================================================================
    // WRITE STATE MACHINE
    // =========================================================================
    // AXI4-Lite write address and write data channels are accepted
    // independently.
    //
    // The state machine advances to W_ACCEPT once both channels have been
    // captured. W_ACCEPT generates the native write pulse, followed by the AXI
    // write response in W_RESP.
    // =========================================================================

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------

            w_state       <= W_IDLE;

            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;

            w_addr        <= 0;
            w_data        <= 0;

        end else begin

            case (w_state)

                // =============================================================
                // W_IDLE: CAPTURE AXI WRITE ADDRESS AND DATA
                // =============================================================
                W_IDLE: begin

                    // Capture the AXI write address when the AW handshake
                    // completes.
                    if (s_axi_awvalid && s_axi_awready) begin
                        w_addr        <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                    end

                    // Capture the AXI write data when the W handshake
                    // completes.
                    if (s_axi_wvalid && s_axi_wready) begin
                        w_data       <= s_axi_wdata;
                        s_axi_wready <= 1'b0;
                    end

                    // Advance after both address and data have either already
                    // been captured or are valid in the current cycle.
                    if (
                        (!s_axi_awready || s_axi_awvalid) &&
                        (!s_axi_wready  || s_axi_wvalid)
                    ) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        w_state       <= W_ACCEPT;
                    end
                end

                // =============================================================
                // W_ACCEPT: ISSUE NATIVE WRITE
                // =============================================================
                // mmio_we is asserted combinationally throughout this state.
                // The captured write address and data are presented to the
                // native interface for one clock cycle.
                W_ACCEPT: begin
                    w_state <= W_RESP;
                end

                // =============================================================
                // W_RESP: RETURN AXI WRITE RESPONSE
                // =============================================================
                W_RESP: begin

                    s_axi_bvalid <= 1'b1;

                    // Complete the AXI write-response handshake.
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        w_state       <= W_IDLE;
                    end
                end

                // =============================================================
                // DEFAULT RECOVERY
                // =============================================================
                default: begin
                    w_state <= W_IDLE;
                end

            endcase
        end
    end

    // =========================================================================
    // READ STATE MACHINE
    // =========================================================================
    // The read address is captured in R_IDLE.
    //
    // R_WAIT provides one clock cycle for the native memory interface to
    // produce read data.
    //
    // R_SEND captures mmio_rdata and returns it through the AXI4-Lite read-data
    // channel.
    // =========================================================================

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------

            r_state       <= R_IDLE;

            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 0;

            r_addr        <= 0;

        end else begin

            case (r_state)

                // =============================================================
                // R_IDLE: CAPTURE AXI READ ADDRESS
                // =============================================================
                R_IDLE: begin

                    // Capture the AXI read address when the AR handshake
                    // completes.
                    if (s_axi_arvalid && s_axi_arready) begin
                        r_addr        <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        r_state       <= R_WAIT;
                    end
                end

                // =============================================================
                // R_WAIT: WAIT FOR NATIVE READ DATA
                // =============================================================
                // The captured read address is already presented through
                // mmio_addr. This state provides one clock cycle for the native
                // memory or register interface to update mmio_rdata.
                R_WAIT: begin
                    r_state <= R_SEND;
                end

                // =============================================================
                // R_SEND: RETURN AXI READ DATA
                // =============================================================
                R_SEND: begin

                    // Capture native read data and assert the AXI read-valid
                    // response.
                    s_axi_rvalid <= 1'b1;
                    s_axi_rdata  <= mmio_rdata;

                    // Complete the AXI read-data handshake.
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid  <= 1'b0;
                        s_axi_arready <= 1'b1;
                        r_state       <= R_IDLE;
                    end
                end

                // =============================================================
                // DEFAULT RECOVERY
                // =============================================================
                default: begin
                    r_state <= R_IDLE;
                end

            endcase
        end
    end

endmodule
