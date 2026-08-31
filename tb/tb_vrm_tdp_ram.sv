`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_tdp_ram
// Description : Dual-port RAM verification using two independent clock
//               domains for simultaneous memory access testing.
//
// Test Coverage:
//   - Port A write followed by Port B read
//   - Port B write followed by Port A read
//   - Simultaneous dual-port write operations
//   - Simultaneous cross-port read operations
//   - Burst write and read operations
//   - Write-write address collision
//   - Read-during-write hazard
//
// Features:
//   - Independent clock domains for Port A and Port B
//   - Dedicated read and write stimulus tasks for each port
//   - Parallel dual-port access testing
//   - Block RAM inference configuration
//   - VCD waveform generation for simulation analysis
//
// Notes:
//   - Port A operates at a 100 MHz clock rate.
//   - Port B operates at approximately 142 MHz.
//   - Collision scenarios are intentionally included to observe the behavior
//     of the inferred FPGA memory under concurrent access conditions.
//   - Read-during-write behavior may depend on the target FPGA memory
//     implementation and its configured inference mode.
// ============================================================================

module tb_vrm_tdp_ram();

    // =========================================================================
    // Parameter and Signal Declarations
    // =========================================================================
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 10;

    // -------------------------------------------------------------------------
    // Port A Signals
    // -------------------------------------------------------------------------
    reg                   clka;
    reg                   wea;
    reg  [ADDR_WIDTH-1:0] addra;
    reg  [DATA_WIDTH-1:0] dina;
    wire [DATA_WIDTH-1:0] douta;

    // -------------------------------------------------------------------------
    // Port B Signals
    // -------------------------------------------------------------------------
    reg                   clkb;
    reg                   web;
    reg  [ADDR_WIDTH-1:0] addrb;
    reg  [DATA_WIDTH-1:0] dinb;
    wire [DATA_WIDTH-1:0] doutb;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    vrm_tdp_ram_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_STYLE("block")
    ) dut (
        .clka(clka), .wea(wea), .addra(addra), .dina(dina), .douta(douta),
        .clkb(clkb), .web(web), .addrb(addrb), .dinb(dinb), .doutb(doutb)
    );

    // =========================================================================
    // Clock Generation
    // Two independent clock domains are used for Port A and Port B.
    // =========================================================================
    initial begin
        clka = 0;
        forever #5 clka = ~clka; // clka = 10 ns period (100 MHz)
    end

    initial begin
        clkb = 0;
        forever #3.5 clkb = ~clkb; // clkb = 7 ns period (~142 MHz)
    end

    // =========================================================================
    // Port Access Tasks
    // =========================================================================
    task write_A(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clka);
            wea   <= 1'b1;
            addra <= addr;
            dina  <= data;
            @(negedge clka);
            wea   <= 1'b0;
        end
    endtask

    task write_B(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clkb);
            web   <= 1'b1;
            addrb <= addr;
            dinb  <= data;
            @(negedge clkb);
            web   <= 1'b0;
        end
    endtask

    task read_A(input [ADDR_WIDTH-1:0] addr);
        begin
            @(negedge clka);
            wea   <= 1'b0;
            addra <= addr;
            @(negedge clka);
            $display("[%0t] PORT A READ: Address %h = %h", $time, addr, douta);
        end
    endtask

    task read_B(input [ADDR_WIDTH-1:0] addr);
        begin
            @(negedge clkb);
            web   <= 1'b0;
            addrb <= addr;
            @(negedge clkb);
            $display("[%0t] PORT B READ: Address %h = %h", $time, addr, doutb);
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    integer i = 0, j = 0;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_vrm_tdp_ram);

        // Initialize all interface signals.
        wea = 0; addra = 0; dina = 0;
        web = 0; addrb = 0; dinb = 0;
        
        #50;

        $display("\n--- SCENARIO 1: WRITE THROUGH PORT A, READ THROUGH PORT B ---");
        write_A(10'h00A, 32'hDEADBEEF); // Write using the slower clock domain.
        #20;
        read_B(10'h00A);                // Read using the faster clock domain.

        #50;
        $display("\n--- SCENARIO 2: WRITE THROUGH PORT B, READ THROUGH PORT A ---");
        write_B(10'h00B, 32'hCAFEBA5E); // Write using the faster clock domain.
        #20;
        read_A(10'h00B);                // Read using the slower clock domain.

        #50;
        $display("\n--- SCENARIO 3: SIMULTANEOUS DUAL-PORT ACCESS ---");
        // Port A writes to address 1 while Port B writes to address 2 in parallel.
        fork
            write_A(10'h001, 32'h11111111);
            write_B(10'h002, 32'h22222222);
        join
        
        #20;
        // Port A reads the data written by Port B, while Port B reads the data written by Port A.
        fork
            read_A(10'h002);
            read_B(10'h001);
        join

        #50;

        $display("\n--- SCENARIO 4: BURST WRITE AND READ ---");
        // Port A writes to five consecutive addresses.
        // Port B performs reads concurrently using the faster clock domain.
        fork
            begin
                for (i=0; i<5; i=i+1) write_A(10'h020 + i, 32'hA0000000 + i);
            end
            begin
                #12; // Provide sufficient delay for the first write operation.
                for (j=0; j<5; j=j+1) read_B(10'h020 + j);
            end
        join

        #50;
        $display("\n--- SCENARIO 5: WRITE-WRITE ADDRESS COLLISION ---");
        // Port A and Port B write different data to the same address.
        // Because clka and clkb are asynchronous, the resulting value depends
        // on the relative timing of the two write operations.
        fork
            write_A(10'h0FF, 32'hAAAAAAAA);
            write_B(10'h0FF, 32'hBBBBBBBB);
        join
        
        #30;
        read_A(10'h0FF); // Observe the resulting memory value after the collision.

        #50;
        $display("\n--- SCENARIO 6: READ-DURING-WRITE HAZARD ---");
        // Port A writes to an address while Port B reads the same address.
        // The resulting behavior depends on the memory implementation and its
        // configured read-during-write mode.
        fork
            write_A(10'h100, 32'h99999999);
            read_B(10'h100);
        join
        
        #30;
        read_B(10'h100); // Perform a subsequent read to verify the final stored value.

        #50;
        $display("\nVRM TDP RAM stress test completed successfully.");
        $finish;
    end

endmodule
