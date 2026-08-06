`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_tdp_ram_core
// Description : Parameterized true dual-port RAM core with automatic data-width
//               packing for selected FPGA-friendly memory organizations.
//
// Features:
// - Independent Port A and Port B
// - Independent clocks for each port
// - Independent write enables
// - Synchronous read output on both ports
// - Parameterized data and address width
// - Configurable Vivado RAM style inference
// - Automatic packing using power-of-two packing ratios
// - Native-width memory mode for wide or non-standard data widths
//
// Port Operation:
// - Port A and Port B share the same physical memory array.
// - Each port has an independent clock, address, write enable, and data path.
// - Both ports can access the memory concurrently.
//
// Memory Organization:
// - DATA_WIDTH = 9, 18, 36 : Packed into 72-bit memory words
// - DATA_WIDTH = 8, 16, 32 : Packed into 64-bit memory words
// - Other widths           : Native-width memory
//
// Read Behavior:
// - Both ports use synchronous read operations.
// - The requested memory word is captured into an internal register on the
//   corresponding port clock edge.
// - For packed modes, the selected logical data chunk is extracted from the
//   registered physical memory word.
//
// Packing Policy:
// - Automatic packing is limited to configurations with power-of-two packing
//   ratios.
// - Non-standard widths, including 24-bit and 48-bit data, use native-width
//   memory organization.
//
// Collision Behavior:
// - Simultaneous accesses from both ports are supported.
// - Simultaneous writes to the same physical memory location may produce
//   device-dependent behavior and should be avoided unless explicitly
//   supported by the target FPGA memory primitive.
//
// Note:
// The RAM style attribute guides Vivado memory inference toward Block RAM,
// UltraRAM, or Distributed RAM according to the selected parameter.
// ============================================================================

module vrm_tdp_ram_core #(
    parameter DATA_WIDTH = 24,      // User data width in bits
    parameter ADDR_WIDTH = 10,      // User-side address width
    parameter RAM_STYLE  = "block"  // Vivado RAM inference:
                                    // "block", "ultra", or "distributed"
)(
    // =========================================================================
    // PORT A
    // =========================================================================
    input  wire                  clka,
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,

    // =========================================================================
    // PORT B
    // =========================================================================
    input  wire                  clkb,
    input  wire                  web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb
);

    generate

        // ====================================================================
        // MODE 1: 9-BIT / 18-BIT / 36-BIT DATA PACKED INTO 72-BIT MEMORY
        // --------------------------------------------------------------------
        // Multiple logical data words are packed into one 72-bit physical
        // memory word.
        //
        // DATA_WIDTH = 9  -> 8 logical words per physical word
        // DATA_WIDTH = 18 -> 4 logical words per physical word
        // DATA_WIDTH = 36 -> 2 logical words per physical word
        //
        // The lower address bits select the logical chunk within the physical
        // memory word. The remaining address bits select the physical entry.
        // ====================================================================
        if (
            DATA_WIDTH == 9  ||
            DATA_WIDTH == 18 ||
            DATA_WIDTH == 36
        ) begin : gen_packed_ram_72

            localparam CORE_DATA_WIDTH = 72;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *)
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            // ----------------------------------------------------------------
            // Simulation Initialization
            // ----------------------------------------------------------------
            integer i;

            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            // =================================================================
            // PORT A ADDRESS MAPPING
            // =================================================================

            // Physical RAM address.
            wire [CORE_ADDR_WIDTH-1:0] core_addra =
                addra[ADDR_WIDTH-1:LSB_BITS];

            // Logical chunk index within the packed word.
            wire [LSB_BITS-1:0] chunk_idx_a =
                addra[LSB_BITS-1:0];

            // Registered physical-word read data.
            reg [CORE_DATA_WIDTH-1:0] core_douta;

            // Registered chunk index aligned with core_douta.
            reg [LSB_BITS-1:0] rd_chunk_idx_a;

            integer ja;

            // Port A synchronous read/write process.
            always @(posedge clka) begin

                // Update only the selected logical chunk.
                if (wea) begin
                    for (ja = 0; ja < RATIO; ja = ja + 1) begin
                        if (chunk_idx_a == ja) begin
                            ram[core_addra]
                               [ja*DATA_WIDTH +: DATA_WIDTH] <= dina;
                        end
                    end
                end

                // Register the complete physical memory word.
                core_douta <= ram[core_addra];

                // Register the corresponding logical chunk index.
                rd_chunk_idx_a <= chunk_idx_a;
            end

            // Extract the requested logical word from the registered physical
            // memory word.
            always @(*) begin
                douta =
                    core_douta[
                        rd_chunk_idx_a * DATA_WIDTH +: DATA_WIDTH
                    ];
            end

            // =================================================================
            // PORT B ADDRESS MAPPING
            // =================================================================

            // Physical RAM address.
            wire [CORE_ADDR_WIDTH-1:0] core_addrb =
                addrb[ADDR_WIDTH-1:LSB_BITS];

            // Logical chunk index within the packed word.
            wire [LSB_BITS-1:0] chunk_idx_b =
                addrb[LSB_BITS-1:0];

            // Registered physical-word read data.
            reg [CORE_DATA_WIDTH-1:0] core_doutb;

            // Registered chunk index aligned with core_doutb.
            reg [LSB_BITS-1:0] rd_chunk_idx_b;

            integer jb;

            // Port B synchronous read/write process.
            always @(posedge clkb) begin

                // Update only the selected logical chunk.
                if (web) begin
                    for (jb = 0; jb < RATIO; jb = jb + 1) begin
                        if (chunk_idx_b == jb) begin
                            ram[core_addrb]
                               [jb*DATA_WIDTH +: DATA_WIDTH] <= dinb;
                        end
                    end
                end

                // Register the complete physical memory word.
                core_doutb <= ram[core_addrb];

                // Register the corresponding logical chunk index.
                rd_chunk_idx_b <= chunk_idx_b;
            end

            // Extract the requested logical word from the registered physical
            // memory word.
            always @(*) begin
                doutb =
                    core_doutb[
                        rd_chunk_idx_b * DATA_WIDTH +: DATA_WIDTH
                    ];
            end

        // ====================================================================
        // MODE 2: 8-BIT / 16-BIT / 32-BIT DATA PACKED INTO 64-BIT MEMORY
        // --------------------------------------------------------------------
        // Multiple logical data words are packed into one 64-bit physical
        // memory word.
        //
        // DATA_WIDTH = 8  -> 8 logical words per physical word
        // DATA_WIDTH = 16 -> 4 logical words per physical word
        // DATA_WIDTH = 32 -> 2 logical words per physical word
        //
        // The lower address bits select the logical chunk within the physical
        // memory word. The remaining address bits select the physical entry.
        // ====================================================================
        end else if (
            DATA_WIDTH == 8  ||
            DATA_WIDTH == 16 ||
            DATA_WIDTH == 32
        ) begin : gen_packed_ram_64

            localparam CORE_DATA_WIDTH = 64;
            localparam RATIO           = CORE_DATA_WIDTH / DATA_WIDTH;
            localparam LSB_BITS        = $clog2(RATIO);
            localparam CORE_ADDR_WIDTH = ADDR_WIDTH - LSB_BITS;
            localparam DEPTH           = 32'd1 << CORE_ADDR_WIDTH;

            (* ram_style = RAM_STYLE *)
            reg [CORE_DATA_WIDTH-1:0] ram [0:DEPTH-1];

            // ----------------------------------------------------------------
            // Simulation Initialization
            // ----------------------------------------------------------------
            integer i;

            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {CORE_DATA_WIDTH{1'b0}};
                end
            end

            // =================================================================
            // PORT A ADDRESS MAPPING
            // =================================================================

            // Physical RAM address.
            wire [CORE_ADDR_WIDTH-1:0] core_addra =
                addra[ADDR_WIDTH-1:LSB_BITS];

            // Logical chunk index within the packed word.
            wire [LSB_BITS-1:0] chunk_idx_a =
                addra[LSB_BITS-1:0];

            // Registered physical-word read data.
            reg [CORE_DATA_WIDTH-1:0] core_douta;

            // Registered chunk index aligned with core_douta.
            reg [LSB_BITS-1:0] rd_chunk_idx_a;

            integer ja;

            // Port A synchronous read/write process.
            always @(posedge clka) begin

                // Update only the selected logical chunk.
                if (wea) begin
                    for (ja = 0; ja < RATIO; ja = ja + 1) begin
                        if (chunk_idx_a == ja) begin
                            ram[core_addra]
                               [ja*DATA_WIDTH +: DATA_WIDTH] <= dina;
                        end
                    end
                end

                // Register the complete physical memory word.
                core_douta <= ram[core_addra];

                // Register the corresponding logical chunk index.
                rd_chunk_idx_a <= chunk_idx_a;
            end

            // Extract the requested logical word from the registered physical
            // memory word.
            always @(*) begin
                douta =
                    core_douta[
                        rd_chunk_idx_a * DATA_WIDTH +: DATA_WIDTH
                    ];
            end

            // =================================================================
            // PORT B ADDRESS MAPPING
            // =================================================================

            // Physical RAM address.
            wire [CORE_ADDR_WIDTH-1:0] core_addrb =
                addrb[ADDR_WIDTH-1:LSB_BITS];

            // Logical chunk index within the packed word.
            wire [LSB_BITS-1:0] chunk_idx_b =
                addrb[LSB_BITS-1:0];

            // Registered physical-word read data.
            reg [CORE_DATA_WIDTH-1:0] core_doutb;

            // Registered chunk index aligned with core_doutb.
            reg [LSB_BITS-1:0] rd_chunk_idx_b;

            integer jb;

            // Port B synchronous read/write process.
            always @(posedge clkb) begin

                // Update only the selected logical chunk.
                if (web) begin
                    for (jb = 0; jb < RATIO; jb = jb + 1) begin
                        if (chunk_idx_b == jb) begin
                            ram[core_addrb]
                               [jb*DATA_WIDTH +: DATA_WIDTH] <= dinb;
                        end
                    end
                end

                // Register the complete physical memory word.
                core_doutb <= ram[core_addrb];

                // Register the corresponding logical chunk index.
                rd_chunk_idx_b <= chunk_idx_b;
            end

            // Extract the requested logical word from the registered physical
            // memory word.
            always @(*) begin
                doutb =
                    core_doutb[
                        rd_chunk_idx_b * DATA_WIDTH +: DATA_WIDTH
                    ];
            end

        // ====================================================================
        // MODE 3: NATIVE-WIDTH MEMORY
        // --------------------------------------------------------------------
        // Used for all data widths not handled by the packed modes above.
        //
        // Examples:
        // - 24-bit
        // - 48-bit
        // - DATA_WIDTH >= 64
        // - Other non-standard widths
        //
        // Each logical data word occupies one physical RAM entry.
        // No address translation or logical chunk extraction is performed.
        // ====================================================================
        end else begin : gen_native_ram

            localparam DEPTH = 32'd1 << ADDR_WIDTH;

            (* ram_style = RAM_STYLE *)
            reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

            // ----------------------------------------------------------------
            // Simulation Initialization
            // ----------------------------------------------------------------
            integer i;

            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = {DATA_WIDTH{1'b0}};
                end
            end

            // =================================================================
            // PORT A
            // =================================================================

            // Port A synchronous read/write process.
            always @(posedge clka) begin
                if (wea) begin
                    ram[addra] <= dina;
                end

                douta <= ram[addra];
            end

            // =================================================================
            // PORT B
            // =================================================================

            // Port B synchronous read/write process.
            always @(posedge clkb) begin
                if (web) begin
                    ram[addrb] <= dinb;
                end

                doutb <= ram[addrb];
            end

        end
    endgenerate

endmodule
