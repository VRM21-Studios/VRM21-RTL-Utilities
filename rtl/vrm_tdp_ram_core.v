`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_tdp_ram_core
// Description : Parameterized true dual-port RAM core with automatic data-width
//               packing for efficient FPGA memory utilization.
//
// Features:
// - Independent Port A and Port B
// - Independent clocks for each port
// - Independent write enables
// - Synchronous read output on both ports
// - Parameterized data and address width
// - Configurable Vivado RAM style inference
// - Automatic packing for common FPGA memory widths
// - Dedicated handling for 72-bit and 144-bit memory organizations
// - Native-width memory mode for wide or non-standard data widths
//
// Port Operation:
// - Port A and Port B share the same physical memory array.
// - Each port has an independent clock, address, write enable, and data path.
// - Both ports can access the memory concurrently.
//
// Memory Organization:
// - DATA_WIDTH = 9, 18, 36 : Packed into 72-bit memory words
// - DATA_WIDTH = 24, 48    : Packed into 72-bit / 144-bit memory words
// - DATA_WIDTH = 8, 16, 32 : Packed into 64-bit memory words
// - Other widths             : Native-width memory
//
// Read Behavior:
// - Both ports use synchronous read operations.
// - The requested memory word is captured into an internal register on the
//   corresponding port clock edge.
// - For packed modes, the selected logical data chunk is extracted from the
//   registered physical memory word.
//
// Note:
// The RAM style attribute is used to guide Vivado memory inference toward
// Block RAM, UltraRAM, or Distributed RAM depending on the selected parameter.
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
        // Multiple logical data words are packed into a single 72-bit physical
        // memory word.
        //
        // DATA_WIDTH = 9  -> 8 logical words per physical word
        // DATA_WIDTH = 18 -> 4 logical words per physical word
        // DATA_WIDTH = 36 -> 2 logical words per physical word
        //
        // The lower address bits select the logical chunk within the physical
        // memory word, while the remaining address bits select the physical
        // RAM entry.
        //
        // Port A and Port B independently perform read and write operations
        // using their respective clocks.
        // ====================================================================
        if (DATA_WIDTH == 9 || DATA_WIDTH == 18 || DATA_WIDTH == 36) begin : gen_packed_ram_72_even

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

            // Convert the user address into:
            // - Physical memory word address
            // - Logical chunk index inside the packed 72-bit word
            wire [CORE_ADDR_WIDTH-1:0] core_addra  = addra[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        chunk_idx_a = addra[LSB_BITS-1:0];

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_douta;
            reg  [LSB_BITS-1:0]        rd_chunk_idx_a;

            integer ja;

            // Port A synchronous read/write process.
            always @(posedge clka) begin
                if (wea) begin
                    // Update only the selected logical chunk within the
                    // physical 72-bit memory word.
                    for (ja = 0; ja < RATIO; ja = ja + 1) begin
                        if (chunk_idx_a == ja) begin
                            ram[core_addra][ja*DATA_WIDTH +: DATA_WIDTH] <= dina;
                        end
                    end
                end

                // Capture the complete physical memory word and the selected
                // logical chunk index for output extraction.
                core_douta     <= ram[core_addra];
                rd_chunk_idx_a <= chunk_idx_a;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                douta = core_douta[rd_chunk_idx_a * DATA_WIDTH +: DATA_WIDTH];
            end

            // =================================================================
            // PORT B ADDRESS MAPPING
            // =================================================================

            wire [CORE_ADDR_WIDTH-1:0] core_addrb  = addrb[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        chunk_idx_b = addrb[LSB_BITS-1:0];

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_doutb;
            reg  [LSB_BITS-1:0]        rd_chunk_idx_b;

            integer jb;

            // Port B synchronous read/write process.
            always @(posedge clkb) begin
                if (web) begin
                    // Update only the selected logical chunk within the
                    // physical 72-bit memory word.
                    for (jb = 0; jb < RATIO; jb = jb + 1) begin
                        if (chunk_idx_b == jb) begin
                            ram[core_addrb][jb*DATA_WIDTH +: DATA_WIDTH] <= dinb;
                        end
                    end
                end

                // Capture the complete physical memory word and the selected
                // logical chunk index for output extraction.
                core_doutb     <= ram[core_addrb];
                rd_chunk_idx_b <= chunk_idx_b;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                doutb = core_doutb[rd_chunk_idx_b * DATA_WIDTH +: DATA_WIDTH];
            end

        // ====================================================================
        // MODE 2: 24-BIT / 48-BIT DATA PACKED USING 3-WORD GROUPS
        // --------------------------------------------------------------------
        // DATA_WIDTH = 24 -> 3 x 24-bit logical words = 72-bit physical word
        // DATA_WIDTH = 48 -> 3 x 48-bit logical words = 144-bit physical word
        //
        // Address mapping uses division and modulo by 3 because the packing
        // ratio is not a power of two.
        //
        // Each port independently converts the user address into:
        // - Physical memory word address
        // - Logical chunk index within the physical word
        // ====================================================================
        end else if (DATA_WIDTH == 24 || DATA_WIDTH == 48) begin : gen_packed_ram_mod3

            localparam CORE_DATA_WIDTH = DATA_WIDTH * 3;
            localparam DEPTH           = ((32'd1 << ADDR_WIDTH) + 2) / 3;

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

            // Divide the user address into physical word address and
            // logical chunk index.
            wire [ADDR_WIDTH-1:0] core_addra  = addra / 3;
            wire [1:0]            chunk_idx_a = addra % 3;

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_douta;
            reg  [1:0]                 rd_chunk_idx_a;

            integer ja;

            // Port A synchronous read/write process.
            always @(posedge clka) begin
                if (wea) begin
                    // Update only the selected logical chunk within the
                    // physical memory word.
                    for (ja = 0; ja < 3; ja = ja + 1) begin
                        if (chunk_idx_a == ja) begin
                            ram[core_addra][ja*DATA_WIDTH +: DATA_WIDTH] <= dina;
                        end
                    end
                end

                // Capture the physical memory word and selected chunk index.
                core_douta     <= ram[core_addra];
                rd_chunk_idx_a <= chunk_idx_a;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                douta = core_douta[rd_chunk_idx_a * DATA_WIDTH +: DATA_WIDTH];
            end

            // =================================================================
            // PORT B ADDRESS MAPPING
            // =================================================================

            wire [ADDR_WIDTH-1:0] core_addrb  = addrb / 3;
            wire [1:0]            chunk_idx_b = addrb % 3;

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_doutb;
            reg  [1:0]                 rd_chunk_idx_b;

            integer jb;

            // Port B synchronous read/write process.
            always @(posedge clkb) begin
                if (web) begin
                    // Update only the selected logical chunk within the
                    // physical memory word.
                    for (jb = 0; jb < 3; jb = jb + 1) begin
                        if (chunk_idx_b == jb) begin
                            ram[core_addrb][jb*DATA_WIDTH +: DATA_WIDTH] <= dinb;
                        end
                    end
                end

                // Capture the physical memory word and selected chunk index.
                core_doutb     <= ram[core_addrb];
                rd_chunk_idx_b <= chunk_idx_b;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                doutb = core_doutb[rd_chunk_idx_b * DATA_WIDTH +: DATA_WIDTH];
            end

        // ====================================================================
        // MODE 3: STANDARD AUTO-PACKING INTO 64-BIT MEMORY WORDS
        // --------------------------------------------------------------------
        // Supported configurations:
        // DATA_WIDTH = 8  -> 8 logical words per physical word
        // DATA_WIDTH = 16 -> 4 logical words per physical word
        // DATA_WIDTH = 32 -> 2 logical words per physical word
        //
        // The lower address bits select the logical chunk within the packed
        // 64-bit memory word.
        // ====================================================================
        end else if (DATA_WIDTH == 8 || DATA_WIDTH == 16 || DATA_WIDTH == 32) begin : gen_packed_ram_64

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

            // Convert the user address into:
            // - Physical memory word address
            // - Logical chunk index inside the packed 64-bit word
            wire [CORE_ADDR_WIDTH-1:0] core_addra  = addra[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        chunk_idx_a = addra[LSB_BITS-1:0];

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_douta;
            reg  [LSB_BITS-1:0]        rd_chunk_idx_a;

            integer ja;

            // Port A synchronous read/write process.
            always @(posedge clka) begin
                if (wea) begin
                    // Update only the selected logical chunk within the
                    // physical 64-bit memory word.
                    for (ja = 0; ja < RATIO; ja = ja + 1) begin
                        if (chunk_idx_a == ja) begin
                            ram[core_addra][ja*DATA_WIDTH +: DATA_WIDTH] <= dina;
                        end
                    end
                end

                // Capture the physical memory word and selected chunk index.
                core_douta     <= ram[core_addra];
                rd_chunk_idx_a <= chunk_idx_a;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                douta = core_douta[rd_chunk_idx_a * DATA_WIDTH +: DATA_WIDTH];
            end

            // =================================================================
            // PORT B ADDRESS MAPPING
            // =================================================================

            wire [CORE_ADDR_WIDTH-1:0] core_addrb  = addrb[ADDR_WIDTH-1 : LSB_BITS];
            wire [LSB_BITS-1:0]        chunk_idx_b = addrb[LSB_BITS-1:0];

            // Registered physical memory read data and logical chunk index.
            reg  [CORE_DATA_WIDTH-1:0] core_doutb;
            reg  [LSB_BITS-1:0]        rd_chunk_idx_b;

            integer jb;

            // Port B synchronous read/write process.
            always @(posedge clkb) begin
                if (web) begin
                    // Update only the selected logical chunk within the
                    // physical 64-bit memory word.
                    for (jb = 0; jb < RATIO; jb = jb + 1) begin
                        if (chunk_idx_b == jb) begin
                            ram[core_addrb][jb*DATA_WIDTH +: DATA_WIDTH] <= dinb;
                        end
                    end
                end

                // Capture the physical memory word and selected chunk index.
                core_doutb     <= ram[core_addrb];
                rd_chunk_idx_b <= chunk_idx_b;
            end

            // Extract the requested logical data word from the registered
            // physical memory word.
            always @(*) begin
                doutb = core_doutb[rd_chunk_idx_b * DATA_WIDTH +: DATA_WIDTH];
            end

        // ====================================================================
        // MODE 4: NATIVE-WIDTH MEMORY
        // --------------------------------------------------------------------
        // Used for:
        // - DATA_WIDTH >= 64
        // - Non-standard widths that are not handled by the packed modes
        //   above, such as 33-bit data.
        //
        // In this mode, each logical data word occupies one physical RAM entry.
        // No address packing or chunk extraction is performed.
        // ====================================================================
        end else begin : gen_native_ram

            (* ram_style = RAM_STYLE *)
            reg [DATA_WIDTH-1:0] ram [0:(32'd1<<ADDR_WIDTH)-1];

            // ----------------------------------------------------------------
            // Simulation Initialization
            // ----------------------------------------------------------------
            integer i;
            initial begin
                for (i = 0; i < (32'd1<<ADDR_WIDTH); i = i + 1) begin
                    ram[i] = {DATA_WIDTH{1'b0}};
                end
            end

            // =================================================================
            // PORT A
            // =================================================================

            // Synchronous read/write operation for Port A.
            always @(posedge clka) begin
                if (wea)
                    ram[addra] <= dina;

                douta <= ram[addra];
            end

            // =================================================================
            // PORT B
            // =================================================================

            // Synchronous read/write operation for Port B.
            always @(posedge clkb) begin
                if (web)
                    ram[addrb] <= dinb;

                doutb <= ram[addrb];
            end

        end
    endgenerate

endmodule
