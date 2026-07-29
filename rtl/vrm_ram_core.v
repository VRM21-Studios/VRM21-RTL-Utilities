`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_ram_core
// Description : Parameterized synchronous RAM core with automatic data-width
//               packing for efficient FPGA memory utilization.
//
// Features:
// - Parameterized data and address width
// - Configurable Vivado RAM style inference
// - Synchronous write and read enable
// - Automatic packing to common FPGA memory widths
// - Dedicated handling for 72-bit memory organization
// - Supports native wide memories (DATA_WIDTH >= 64)
//
// Memory Organization:
// - DATA_WIDTH >= 64 : Native-width memory
// - DATA_WIDTH = 9, 18, 36 : Packed into 72-bit memory words
// - DATA_WIDTH = 24, 48    : Packed into 72-bit / 144-bit memory words
// - Other supported widths : Packed into 64-bit memory words
//
// Note:
// The packing strategy is intended to improve memory resource utilization
// when mapping arbitrary user data widths onto FPGA block/distributed/URAM
// primitives supported by the target device.
//
// Read behavior:
// - Read operation is synchronous.
// - rd_data is updated after a registered read operation.
// ============================================================================

module vrm_ram_core #(
    parameter DATA_WIDTH = 24,     // User data width in bits
    parameter ADDR_WIDTH = 12,     // User-side address width
    parameter RAM_STYLE  = "auto"  // Vivado RAM inference: "ultra", "block",
                                   // "distributed", or "auto"
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

        // ====================================================================
        // MODE 1: NATIVE-WIDTH MEMORY
        // --------------------------------------------------------------------
        // Used when DATA_WIDTH >= 64.
        //
        // The user-defined data width is stored directly in the inferred RAM
        // without additional packing or address translation.
        // ====================================================================
        if (DATA_WIDTH >= 64) begin : gen_native_ram

            (* ram_style = RAM_STYLE *)
            reg [DATA_WIDTH-1:0] ram [0:(32'd1<<ADDR_WIDTH)-1];

            integer i;

            // Initialize all memory locations to zero at simulation startup.
            // This is primarily intended for deterministic simulation behavior.
            initial begin
                for (i = 0; i < (32'd1<<ADDR_WIDTH); i = i + 1) begin
                    ram[i] = {DATA_WIDTH{1'b0}};
                end
            end

            // Synchronous RAM read/write process.
            always @(posedge clk) begin
                if (!rstn) begin
                    rd_data <= {DATA_WIDTH{1'b0}};
                end else begin
                    if (we)
                        ram[wr_addr] <= wr_data;

                    if (re)
                        rd_data <= ram[rd_addr];
                end
            end

        // ====================================================================
        // MODE 2: 9-BIT / 18-BIT / 36-BIT DATA PACKED INTO 72-BIT MEMORY
        // --------------------------------------------------------------------
        // The selected data widths are packed into a 72-bit physical memory
        // word to better match FPGA memory primitives.
        //
        // Multiple logical data words share a single physical RAM entry.
        // The lower address bits select the logical data chunk inside the
        // packed memory word.
        // ====================================================================
        end else if (DATA_WIDTH == 9 || DATA_WIDTH == 18 || DATA_WIDTH == 36) begin : gen_packed_ram_72_even

            localparam CORE_DATA_WIDTH = 72;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *)
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            integer i;

            // Initialize packed memory contents to zero at simulation startup.
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            // Convert user-space addresses into:
            // - Physical RAM word address
            // - Logical data chunk index within the packed word
            wire [CORE_ADDR_WIDTH-1:0] core_wr_addr = wr_addr[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        wr_chunk_idx = wr_addr[LSB_BITS-1:0];
            wire [CORE_ADDR_WIDTH-1:0] core_rd_addr = rd_addr[ADDR_WIDTH-1 : LSB_BITS];

            // Registered packed-word read data and selected chunk index.
            reg [CORE_DATA_WIDTH-1:0] core_rd_data;
            reg [LSB_BITS-1:0]        rd_chunk_idx;

            integer j;

            // Synchronous packed RAM access.
            always @(posedge clk) begin
                if (!rstn) begin
                    core_rd_data <= {CORE_DATA_WIDTH{1'b0}};
                    rd_chunk_idx <= {LSB_BITS{1'b0}};
                end else begin

                    // Update only the selected logical chunk during a write.
                    if (we) begin
                        for (j = 0; j < RATIO; j = j + 1) begin
                            if (wr_chunk_idx == j) begin
                                ram[core_wr_addr][j*DATA_WIDTH +: DATA_WIDTH] <= wr_data;
                            end
                        end
                    end

                    // Register the complete packed word and selected chunk
                    // index for the subsequent combinational extraction.
                    if (re) begin
                        core_rd_data <= ram[core_rd_addr];
                        rd_chunk_idx <= rd_addr[LSB_BITS-1:0];
                    end
                end
            end

            // Extract the requested logical data word from the registered
            // packed memory word.
            always @(*) begin
                rd_data = core_rd_data[rd_chunk_idx * DATA_WIDTH +: DATA_WIDTH];
            end

        // ====================================================================
        // MODE 3: 24-BIT / 48-BIT DATA PACKED USING A 3-WORD GROUP
        // --------------------------------------------------------------------
        // DATA_WIDTH = 24:
        //   3 x 24-bit logical words -> 72-bit physical memory word
        //
        // DATA_WIDTH = 48:
        //   3 x 48-bit logical words -> 144-bit physical memory word
        //
        // Unlike the power-of-two packing modes, the logical address is
        // converted using division and modulo by 3.
        // ====================================================================
        end else if (DATA_WIDTH == 24 || DATA_WIDTH == 48) begin : gen_packed_ram_mod3

            localparam CORE_DATA_WIDTH = DATA_WIDTH * 3;
            localparam RATIO           = 3;

            // Convert the user-space address into a physical memory word
            // address and a logical chunk index within that word.
            wire [ADDR_WIDTH-1:0]      core_wr_base = wr_addr / 3;
            wire [1:0]                 wr_chunk_idx = wr_addr % 3;
            wire [ADDR_WIDTH-1:0]      core_rd_base = rd_addr / 3;

            // Ceiling division is used to account for a possible partially
            // utilized final packed memory word.
            localparam DEPTH = ((32'd1 << ADDR_WIDTH) + 2) / 3;

            (* ram_style = RAM_STYLE *)
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            integer i;

            // Initialize packed memory contents to zero at simulation startup.
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            // Registered packed-word read data and logical chunk index.
            reg [CORE_DATA_WIDTH-1:0] core_rd_data;
            reg [1:0]                 rd_chunk_idx;

            integer j;

            // Synchronous packed RAM access.
            always @(posedge clk) begin
                if (!rstn) begin
                    core_rd_data <= {CORE_DATA_WIDTH{1'b0}};
                    rd_chunk_idx <= 2'd0;
                end else begin

                    // Update only the selected 24-bit or 48-bit logical chunk.
                    if (we) begin
                        for (j = 0; j < 3; j = j + 1) begin
                            if (wr_chunk_idx == j) begin
                                ram[core_wr_base][j*DATA_WIDTH +: DATA_WIDTH] <= wr_data;
                            end
                        end
                    end

                    // Register the packed memory word and logical chunk index.
                    if (re) begin
                        core_rd_data <= ram[core_rd_base];
                        rd_chunk_idx <= rd_addr % 3;
                    end
                end
            end

            // Extract the requested logical data word from the registered
            // packed memory word.
            always @(*) begin
                rd_data = core_rd_data[rd_chunk_idx * DATA_WIDTH +: DATA_WIDTH];
            end

        // ====================================================================
        // MODE 4: STANDARD AUTO-PACKING INTO 64-BIT MEMORY WORDS
        // --------------------------------------------------------------------
        // Used for data widths that evenly divide 64 bits, such as:
        //   8-bit  -> 8 logical words per physical word
        //   16-bit -> 4 logical words per physical word
        //   32-bit -> 2 logical words per physical word
        //
        // The lower address bits select the logical chunk within the packed
        // 64-bit memory word.
        // ====================================================================
        end else begin : gen_packed_ram_64

            localparam CORE_DATA_WIDTH = 64;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *)
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            integer i;

            // Initialize packed memory contents to zero at simulation startup.
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            // Convert user-space addresses into:
            // - Physical RAM word address
            // - Logical data chunk index within the packed 64-bit word
            wire [CORE_ADDR_WIDTH-1:0] core_wr_addr = wr_addr[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        wr_chunk_idx = wr_addr[LSB_BITS-1:0];
            wire [CORE_ADDR_WIDTH-1:0] core_rd_addr = rd_addr[ADDR_WIDTH-1 : LSB_BITS];

            // Registered packed-word read data and selected chunk index.
            reg [CORE_DATA_WIDTH-1:0] core_rd_data;
            reg [LSB_BITS-1:0]        rd_chunk_idx;

            integer j;

            // Synchronous packed RAM access.
            always @(posedge clk) begin
                if (!rstn) begin
                    core_rd_data <= {CORE_DATA_WIDTH{1'b0}};
                    rd_chunk_idx <= {LSB_BITS{1'b0}};
                end else begin

                    // Update only the selected logical chunk during a write.
                    if (we) begin
                        for (j = 0; j < RATIO; j = j + 1) begin
                            if (wr_chunk_idx == j) begin
                                ram[core_wr_addr][j*DATA_WIDTH +: DATA_WIDTH] <= wr_data;
                            end
                        end
                    end

                    // Register the complete packed word and selected chunk
                    // index for the subsequent combinational extraction.
                    if (re) begin
                        core_rd_data <= ram[core_rd_addr];
                        rd_chunk_idx <= rd_addr[LSB_BITS-1:0];
                    end
                end
            end

            // Extract the requested logical data word from the registered
            // packed memory word.
            always @(*) begin
                rd_data = core_rd_data[rd_chunk_idx * DATA_WIDTH +: DATA_WIDTH];
            end

        end
    endgenerate

endmodule
