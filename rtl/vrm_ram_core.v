`timescale 1ns / 1ps

// ==================================================================================================
// Module      : vrm_ram_core
// Description : Parameterized synchronous RAM core with automatic data-width packing for efficient FPGA memory utilization.
//
// Features:
// - Parameterized data and address width
// - Configurable Vivado RAM style inference
// - Synchronous write and read enable
// - Automatic packing to common FPGA memory widths (8-bit, 9-bit, 16-bit, 24-bit, 32-bit, 33-bit, 48-bit, 64-bit+)
// - Bypass mode for data width >= 64 bits or unusual sizes
//
// Memory Organization:
// - DATA_WIDTH == 8/16/32 : Packed into a 64-bit memory word to avoid parity hazards
// - DATA_WIDTH == 9/18/36 : Packed into a 72-bit memory word for optimal FPGA BRAM utilization
// - DATA_WIDTH >= 64      : Native-width memory without packing
//
// Note:
// The packing strategy is intended to improve memory resource utilization when mapping arbitrary user data widths 
// onto FPGA block/distributed/URAM primitives supported by the target device.
//
// Read behavior:
// - Read operation is synchronous and rd_data is updated after a registered read operation.
// ==================================================================================================

module vrm_ram_core #(
    parameter DATA_WIDTH = 24,     // User data width in bits
    parameter ADDR_WIDTH = 12,     // User-side address width
    parameter RAM_STYLE  = "auto"  // Vivado RAM inference: "ultra", "block", "distributed", or "auto"
)(
    input  wire                  clk,
    input  wire                  rstn,

    // ------------------------------------------------------------------------
    // Write interface
    // ------------------------------------------------------------------------
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,

    // ------------------------------------------------------------------------
    // Read interface
    // ------------------------------------------------------------------------
    input  wire                  re,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    generate

        // ==============================================================
        // MODE 1: AUTO-PACKING STANDAR (8-bit, 16-bit, 32-bit -> 64-bit)
        // Aman dari Parity Hazard karena rasionya genap (8:1, 4:1, 2:1)
        // ==============================================================
        if (DATA_WIDTH == 8 || DATA_WIDTH == 16 || DATA_WIDTH == 32) begin : gen_packed_ram_64
            
            localparam CORE_DATA_WIDTH = 64;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *) 
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            integer i;
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            wire [CORE_ADDR_WIDTH-1:0] core_wr_addr = wr_addr[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        wr_chunk_idx = wr_addr[LSB_BITS-1:0];
            wire [CORE_ADDR_WIDTH-1:0] core_rd_addr = rd_addr[ADDR_WIDTH-1 : LSB_BITS];
            
            reg [CORE_DATA_WIDTH-1:0]  core_rd_data;
            reg [LSB_BITS-1:0]         rd_chunk_idx;

            integer j;
            always @(posedge clk) begin
                if (!rstn) begin
                    core_rd_data <= {CORE_DATA_WIDTH{1'b0}};
                    rd_chunk_idx <= {LSB_BITS{1'b0}};
                end else begin
                    if (we) begin
                        for (j = 0; j < RATIO; j = j + 1) begin
                            if (wr_chunk_idx == j) begin
                                ram[core_wr_addr][j*DATA_WIDTH +: DATA_WIDTH] <= wr_data;
                            end
                        end
                    end
                    if (re) begin
                        core_rd_data <= ram[core_rd_addr];
                        rd_chunk_idx <= rd_addr[LSB_BITS-1:0];
                    end
                end
            end

            always @(*) begin
                rd_data = core_rd_data[rd_chunk_idx * DATA_WIDTH +: DATA_WIDTH];
            end

        // ==============================================================
        // MODE 2: SPECIAL CASE (9-bit, 18-bit, 36-bit -> 72-bit)
        // Memanfaatkan bit parity BRAM secara native (Rasio 8:1, 4:1, 2:1)
        // ==============================================================
        end else if (DATA_WIDTH == 9 || DATA_WIDTH == 18 || DATA_WIDTH == 36) begin : gen_packed_ram_72_even
            
            localparam CORE_DATA_WIDTH = 72;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *) 
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            integer i;
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            wire [CORE_ADDR_WIDTH-1:0] core_wr_addr = wr_addr[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        wr_chunk_idx = wr_addr[LSB_BITS-1:0];
            wire [CORE_ADDR_WIDTH-1:0] core_rd_addr = rd_addr[ADDR_WIDTH-1 : LSB_BITS];
            
            reg [CORE_DATA_WIDTH-1:0]  core_rd_data;
            reg [LSB_BITS-1:0]         rd_chunk_idx;

            integer j;
            always @(posedge clk) begin
                if (!rstn) begin
                    core_rd_data <= {CORE_DATA_WIDTH{1'b0}};
                    rd_chunk_idx <= {LSB_BITS{1'b0}};
                end else begin
                    if (we) begin
                        for (j = 0; j < RATIO; j = j + 1) begin
                            if (wr_chunk_idx == j) begin
                                ram[core_wr_addr][j*DATA_WIDTH +: DATA_WIDTH] <= wr_data;
                            end
                        end
                    end
                    if (re) begin
                        core_rd_data <= ram[core_rd_addr];
                        rd_chunk_idx <= rd_addr[LSB_BITS-1:0];
                    end
                end
            end

            always @(*) begin
                rd_data = core_rd_data[rd_chunk_idx * DATA_WIDTH +: DATA_WIDTH];
            end

        // ==============================================================
        // MODE 3: BYPASS (Data >= 64-bit ATAU ukuran aneh spt 12, 17, 33-bit)
        // Sebagai Jaring Pengaman (Catch-All). Daripada error sintesis LSB_BITS, 
        // biarkan Vivado memetakan langsung (waste bandwidth sedikit tidak apa-apa).
        // ==============================================================
        end else begin : gen_native_ram
            
            (* ram_style = RAM_STYLE *) 
            reg [DATA_WIDTH-1:0] ram [0:(32'd1<<ADDR_WIDTH)-1];

            integer i;
            initial begin
                for (i = 0; i < (32'd1<<ADDR_WIDTH); i = i + 1) begin
                    ram[i] = {DATA_WIDTH{1'b0}};
                end
            end

            always @(posedge clk) begin
                if (!rstn) begin
                    rd_data <= {DATA_WIDTH{1'b0}};
                end else begin
                    if (we) ram[wr_addr] <= wr_data;
                    if (re) rd_data <= ram[rd_addr];
                end
            end

        end
    endgenerate

endmodule
