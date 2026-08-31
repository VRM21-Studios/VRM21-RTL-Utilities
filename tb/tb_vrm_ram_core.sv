`timescale 1ns / 1ps

module tb_vrm_ram_core;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 8; // Memory depth of 256 locations.
    parameter CLK_PERIOD = 10;

    reg                   clk;
    reg                   rstn;
    
    // =========================================================================
    // Write Port
    // =========================================================================
    reg                   we;
    reg  [ADDR_WIDTH-1:0] wr_addr;
    reg  [DATA_WIDTH-1:0] wr_data;
    
    // =========================================================================
    // Read Port
    // =========================================================================
    reg                   re;
    reg  [ADDR_WIDTH-1:0] rd_addr;
    wire [DATA_WIDTH-1:0] rd_data;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    vrm_ram_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_STYLE("block")
    ) dut (
        .clk(clk), .rstn(rstn),
        .we(we), .wr_addr(wr_addr), .wr_data(wr_data),
        .re(re), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // =========================================================================
    // Memory Access Tasks
    // Inputs are applied on the falling edge to provide sufficient setup time.
    // =========================================================================
    task write_ram(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            we      <= 1'b1;
            wr_addr <= addr;
            wr_data <= data;
            @(negedge clk);
            we      <= 1'b0;
        end
    endtask

    task read_ram(input [ADDR_WIDTH-1:0] addr);
        begin
            @(negedge clk);
            re      <= 1'b1;
            rd_addr <= addr;
            @(negedge clk);
            re      <= 1'b0;
        end
    endtask

    // =========================================================================
    // Real-Time Output Monitor
    // =========================================================================
    always @(posedge clk) begin
        #1; // Allow the registered output data to update.
        if (re) $display("[%0t] READ -> Address %h | Output Data: %h", $time, rd_addr, rd_data);
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    integer i;

    initial begin
        $dumpfile("dump_ram_core.vcd");
        $dumpvars(0, tb_vrm_ram_core);

        rstn = 0; we = 0; wr_addr = 0; wr_data = 0; re = 0; rd_addr = 0;
        #(CLK_PERIOD * 5) rstn = 1;

        $display("\n--- SCENARIO 1: BASIC WRITE AND READ ---");
        write_ram(8'h05, 32'hDEAD_BEEF);
        read_ram(8'h05);

        #30;
        $display("\n--- SCENARIO 2: BURST WRITE ---");
        // Write five consecutive data words without idle cycles.
        @(negedge clk);
        we <= 1'b1;
        for (i = 0; i < 5; i = i + 1) begin
            wr_addr <= 8'h10 + i;
            wr_data <= 32'hA000_0000 + i;
            @(negedge clk);
        end
        we <= 1'b0;

        #30;
        $display("\n--- SCENARIO 3: PIPELINED READ ---");
        @(negedge clk);
        re <= 1'b1;
        for (i = 0; i < 5; i = i + 1) begin
            rd_addr <= 8'h10 + i;
            @(negedge clk);
        end
        re <= 1'b0;

        #30;
        $display("\n--- SCENARIO 4: READ-DURING-WRITE HAZARD ---");
        // Write to address 0x55 while simultaneously issuing a read from the same address.
        // The resulting behavior depends on the inferred memory implementation.
        @(negedge clk);
        we <= 1'b1; re <= 1'b1;
        wr_addr <= 8'h55; wr_data <= 32'h1234_5678;
        rd_addr <= 8'h55;
        @(negedge clk);
        we <= 1'b0; re <= 1'b0;
        
        #20;
        $display("\n--- SCENARIO 5: VERIFY POST-COLLISION DATA ---");
        read_ram(8'h55); // Verify that the written data is available after the hazard.

        #50;
        $display("\nVRM RAM core stress test completed successfully.");
        $finish;
    end

endmodule