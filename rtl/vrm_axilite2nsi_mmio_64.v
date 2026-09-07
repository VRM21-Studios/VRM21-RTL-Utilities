`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_axilite2nsi_mmio_64
// Description : AXI4-Lite to Native SRAM Interface (NSI) MMIO bridge.
//
// The bridge accepts AXI4-Lite write address and write data independently,
// then serializes the resulting write transaction with AXI4-Lite reads before
// accessing the shared native MMIO interface.
//
// Features:
//   - Parameterized AXI4-Lite data width
//   - Parameterized AXI4-Lite address width
//   - Independent AW/W channel capture
//   - Serialized read/write transaction ownership
//   - Write priority when read/write requests arrive simultaneously
//   - Single-cycle native write-enable pulse
//   - One-cycle native read wait
//   - Registered native transaction address
//   - AXI4-Lite OKAY responses
//
// Assumptions:
//   - Native interface has no ready/valid/error signals.
//   - Native read data becomes valid after one clock of read latency.
//   - AXI write strobes are currently not applied to native write data.
//   - Reset is active-low synchronous.
// ============================================================================

module vrm_axilite2nsi_mmio_64 #(
    parameter integer C_S_AXI_DATA_WIDTH = 64,
    parameter integer C_S_AXI_ADDR_WIDTH = 64
)(
    input  wire                                  s_axi_aclk,
    input  wire                                  s_axi_aresetn,

    // =========================================================================
    // AXI4-Lite Write Address Channel
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr,
    input  wire                                  s_axi_awvalid,
    output wire                                  s_axi_awready,

    // =========================================================================
    // AXI4-Lite Write Data Channel
    // =========================================================================

    input  wire [C_S_AXI_DATA_WIDTH-1:0]         s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb,
    input  wire                                  s_axi_wvalid,
    output wire                                  s_axi_wready,

    // =========================================================================
    // AXI4-Lite Write Response Channel
    // =========================================================================

    output wire [1:0]                            s_axi_bresp,
    output reg                                   s_axi_bvalid,
    input  wire                                  s_axi_bready,

    // =========================================================================
    // AXI4-Lite Read Address Channel
    // =========================================================================

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr,
    input  wire                                  s_axi_arvalid,
    output wire                                  s_axi_arready,

    // =========================================================================
    // AXI4-Lite Read Data Channel
    // =========================================================================

    output reg [C_S_AXI_DATA_WIDTH-1:0]          s_axi_rdata,
    output wire [1:0]                            s_axi_rresp,
    output reg                                   s_axi_rvalid,
    input  wire                                  s_axi_rready,

    // =========================================================================
    // Native MMIO Interface
    // =========================================================================

    output wire                                  mmio_we,
    output wire [C_S_AXI_ADDR_WIDTH-1:0]         mmio_addr,
    output wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_wdata,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]         mmio_rdata
);

    // =========================================================================
    // AXI4-Lite Response Values
    // =========================================================================

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;


    // =========================================================================
    // State Encoding
    // =========================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_WRITE_WAIT = 3'd1;
    localparam STATE_WRITE_EXEC = 3'd2;
    localparam STATE_WRITE_RESP = 3'd3;
    localparam STATE_READ_WAIT  = 3'd4;
    localparam STATE_READ_RESP  = 3'd5;

    reg [2:0] state;


    // =========================================================================
    // AXI Write Capture State
    // =========================================================================

    reg aw_captured;
    reg w_captured;

    reg [C_S_AXI_ADDR_WIDTH-1:0] w_addr;
    reg [C_S_AXI_DATA_WIDTH-1:0] w_data;


    // =========================================================================
    // AXI Read Capture State
    // =========================================================================

    reg [C_S_AXI_ADDR_WIDTH-1:0] r_addr;


    // =========================================================================
    // Native Interface State
    // =========================================================================

    reg mmio_we_reg;

    reg [C_S_AXI_ADDR_WIDTH-1:0] mmio_addr_reg;


    // =========================================================================
    // AXI Handshake Signals
    // =========================================================================

    wire aw_fire;
    wire w_fire;
    wire ar_fire;

    assign aw_fire = s_axi_awvalid && s_axi_awready;
    assign w_fire  = s_axi_wvalid  && s_axi_wready;
    assign ar_fire = s_axi_arvalid && s_axi_arready;


    // =========================================================================
    // AXI Ready Logic
    // =========================================================================
    //
    // Write traffic has priority whenever a write request is visible.
    //
    // In IDLE:
    //
    //   - AWREADY and WREADY are asserted.
    //   - ARREADY is asserted only when no write VALID is present.
    //
    // In WRITE_WAIT:
    //
    //   - Only missing write channels are accepted.
    //   - Read traffic is blocked.
    // =========================================================================

    assign s_axi_awready =
        (state == STATE_IDLE)       ? 1'b1 :
        (state == STATE_WRITE_WAIT) ? ~aw_captured :
                                      1'b0;

    assign s_axi_wready =
        (state == STATE_IDLE)       ? 1'b1 :
        (state == STATE_WRITE_WAIT) ? ~w_captured :
                                      1'b0;

    assign s_axi_arready =
        (state == STATE_IDLE) &&
        !s_axi_awvalid &&
        !s_axi_wvalid;


    // =========================================================================
    // Native Interface Outputs
    // =========================================================================

    assign mmio_we    = mmio_we_reg;
    assign mmio_addr  = mmio_addr_reg;
    assign mmio_wdata = w_data;


    // =========================================================================
    // Main Transaction Controller
    // =========================================================================

    always @(posedge s_axi_aclk) begin

        if (!s_axi_aresetn) begin

            // -----------------------------------------------------------------
            // Synchronous Reset
            // -----------------------------------------------------------------

            state         <= STATE_IDLE;

            aw_captured   <= 1'b0;
            w_captured    <= 1'b0;

            w_addr        <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            w_data        <= {C_S_AXI_DATA_WIDTH{1'b0}};
            r_addr        <= {C_S_AXI_ADDR_WIDTH{1'b0}};

            mmio_we_reg   <= 1'b0;
            mmio_addr_reg <= {C_S_AXI_ADDR_WIDTH{1'b0}};

            s_axi_bvalid  <= 1'b0;

            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};

        end else begin

            // -----------------------------------------------------------------
            // Default Native Write Enable
            // -----------------------------------------------------------------

            mmio_we_reg <= 1'b0;


            case (state)

                // =============================================================
                // IDLE
                // =============================================================

                STATE_IDLE: begin

                    s_axi_bvalid <= 1'b0;
                    s_axi_rvalid <= 1'b0;


                    // ---------------------------------------------------------
                    // Capture AW independently.
                    // ---------------------------------------------------------

                    if (aw_fire) begin

                        w_addr      <= s_axi_awaddr;
                        aw_captured <= 1'b1;

                    end


                    // ---------------------------------------------------------
                    // Capture W independently.
                    // ---------------------------------------------------------

                    if (w_fire) begin

                        w_data     <= s_axi_wdata;
                        w_captured <= 1'b1;

                    end


                    // ---------------------------------------------------------
                    // If both write channels are available now or were already
                    // captured, start the native write.
                    // ---------------------------------------------------------

                    if (
                        (aw_captured || aw_fire) &&
                        (w_captured  || w_fire)
                    ) begin

                        state <= STATE_WRITE_EXEC;

                    end

                    // ---------------------------------------------------------
                    // Otherwise, if only one write channel was accepted,
                    // wait for the remaining channel.
                    // ---------------------------------------------------------

                    else if (aw_fire || w_fire) begin

                        state <= STATE_WRITE_WAIT;

                    end

                    // ---------------------------------------------------------
                    // Accept read only when no write request is present.
                    // ---------------------------------------------------------

                    else if (ar_fire) begin

                        r_addr        <= s_axi_araddr;
                        mmio_addr_reg <= s_axi_araddr;

                        state <= STATE_READ_WAIT;

                    end

                end


                // =============================================================
                // WRITE_WAIT
                // =============================================================

                STATE_WRITE_WAIT: begin

                    // ---------------------------------------------------------
                    // Capture missing AW channel.
                    // ---------------------------------------------------------

                    if (aw_fire) begin

                        w_addr      <= s_axi_awaddr;
                        aw_captured <= 1'b1;

                    end


                    // ---------------------------------------------------------
                    // Capture missing W channel.
                    // ---------------------------------------------------------

                    if (w_fire) begin

                        w_data     <= s_axi_wdata;
                        w_captured <= 1'b1;

                    end


                    // ---------------------------------------------------------
                    // Start write when both pieces are available.
                    // ---------------------------------------------------------

                    if (
                        (aw_captured || aw_fire) &&
                        (w_captured  || w_fire)
                    ) begin

                        state <= STATE_WRITE_EXEC;

                    end

                end


                // =============================================================
                // WRITE_EXEC
                // =============================================================

                STATE_WRITE_EXEC: begin

                    // ---------------------------------------------------------
                    // Register native address.
                    // ---------------------------------------------------------

                    mmio_addr_reg <= w_addr;

                    // ---------------------------------------------------------
                    // Generate exactly one native write-enable cycle.
                    // ---------------------------------------------------------

                    mmio_we_reg <= 1'b1;

                    state <= STATE_WRITE_RESP;

                end


                // =============================================================
                // WRITE_RESP
                // =============================================================

                STATE_WRITE_RESP: begin

                    s_axi_bvalid <= 1'b1;

                    if (s_axi_bvalid && s_axi_bready) begin

                        s_axi_bvalid <= 1'b0;

                        aw_captured <= 1'b0;
                        w_captured  <= 1'b0;

                        state <= STATE_IDLE;

                    end

                end


                // =============================================================
                // READ_WAIT
                // =============================================================

                STATE_READ_WAIT: begin

                    state <= STATE_READ_RESP;

                end


                // =============================================================
                // READ_RESP
                // =============================================================

                STATE_READ_RESP: begin

                    s_axi_rdata  <= mmio_rdata;
                    s_axi_rvalid <= 1'b1;

                    if (s_axi_rvalid && s_axi_rready) begin

                        s_axi_rvalid <= 1'b0;

                        state <= STATE_IDLE;

                    end

                end


                // =============================================================
                // Default Recovery
                // =============================================================

                default: begin

                    state        <= STATE_IDLE;

                    aw_captured  <= 1'b0;
                    w_captured   <= 1'b0;

                    mmio_we_reg  <= 1'b0;

                    s_axi_bvalid <= 1'b0;
                    s_axi_rvalid <= 1'b0;

                end

            endcase
        end
    end

endmodule
