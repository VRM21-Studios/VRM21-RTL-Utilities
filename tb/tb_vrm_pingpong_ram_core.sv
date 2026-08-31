`timescale 1ns / 1ps

module tb_vrm_pingpong_ram_core;

    // =========================================================================
    // Parameter and Signal Declarations
    // =========================================================================
    localparam DATA_WIDTH = 16;
    localparam ADDR_WIDTH = 4; // Depth of 16 locations for simplified waveform and log inspection.

    reg                   clk;
    reg                   rstn;
    
    // -------------------------------------------------------------------------
    // Bank Control Interface
    // -------------------------------------------------------------------------
    reg                   switch_bank;
    wire                  active_read_bank;
    
    // -------------------------------------------------------------------------
    // Write Port (AXI / Producer)
    // -------------------------------------------------------------------------
    reg                   we;
    reg  [ADDR_WIDTH-1:0] wr_addr;
    reg  [DATA_WIDTH-1:0] wr_data;
    
    // -------------------------------------------------------------------------
    // Read Port (DSP / Consumer)
    // -------------------------------------------------------------------------
    reg                   re;
    reg  [ADDR_WIDTH-1:0] rd_addr;
    wire [DATA_WIDTH-1:0] rd_data;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    vrm_pingpong_ram_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_STYLE("block")
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .switch_bank(switch_bank),
        .active_read_bank(active_read_bank),
        .we(we),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .re(re),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    // =========================================================================
    // Test Stimulus Tasks
    // =========================================================================
    task write_data(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(posedge clk);
            we      <= 1'b1;
            wr_addr <= addr;
            wr_data <= data;
        end
    endtask

    task read_data(input [ADDR_WIDTH-1:0] addr);
        begin
            @(posedge clk);
            re      <= 1'b1;
            rd_addr <= addr;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("tb_vrm_pingpong_ram_core.vcd");
        $dumpvars(0, tb_vrm_pingpong_ram_core);

        // Initialize all interface signals.
        rstn        = 0;
        switch_bank = 0;
        we          = 0;
        wr_addr     = 0;
        wr_data     = 0;
        re          = 0;
        rd_addr     = 0;

        #15 rstn = 1;
        $display("--- SYSTEM RESET DEASSERTED ---");
        $display("Initial Status -> Active Read Bank: %0d (AXI writes to Bank %0d)", 
                 active_read_bank, ~active_read_bank);
        
        // ---------------------------------------------------------------------
        // PHASE 1: AXI Writes Coefficients to Bank 1
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 1: AXI WRITES COEFFICIENTS TO BANK 1 (AAAA, BBBB, CCCC, DDDD) ---");
        // The DSP continues reading from Bank 0 while Bank 1 is updated in the background.
        write_data(4'd0, 16'hAAAA);
        write_data(4'd1, 16'hBBBB);
        write_data(4'd2, 16'hCCCC);
        write_data(4'd3, 16'hDDDD);
        
        @(posedge clk);
        we <= 1'b0; // AXI write operation completed (s_axis_coef_tlast = 1)
        
        repeat(3) @(posedge clk);

        // ---------------------------------------------------------------------
        // PHASE 2: SWITCH BANK AND READ THE NEW DATA
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 2: BANK SWITCH TRIGGER AND IMMEDIATE READ ---");
        @(posedge clk);
        switch_bank <= 1'b1; // Assert the bank-switch trigger.
        
        // The read task waits for one clock cycle, allowing the bank switch
        // trigger to take effect before issuing the read request.
        read_data(4'd0); 
        switch_bank <= 1'b0; // Deassert the bank-switch trigger as reading begins.
        
        read_data(4'd1); // Continue reading on subsequent cycles.
        read_data(4'd2); 
        read_data(4'd3); 
        
        @(posedge clk);
        re <= 1'b0;
        
        repeat(3) @(posedge clk);

        // ---------------------------------------------------------------------
        // PHASE 3: AXI Writes New Coefficients to Bank 0
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 3: AXI WRITES NEW COEFFICIENTS TO BANK 0 (1111, 2222, 3333, 4444) ---");
        // Since Bank 1 is now active for reading, AXI writes are directed to Bank 0.
        write_data(4'd0, 16'h1111);
        write_data(4'd1, 16'h2222);
        write_data(4'd2, 16'h3333);
        write_data(4'd3, 16'h4444);
        
        @(posedge clk);
        we <= 1'b0;
        
        repeat(3) @(posedge clk);

        // ---------------------------------------------------------------------
        // PHASE 4: SWITCH BACK TO BANK 0 AND READ
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 4: SWITCH BACK TO BANK 0 AND READ ---");
        @(posedge clk);
        switch_bank <= 1'b1; // Assert the bank-switch trigger.
        
        read_data(4'd0); 
        switch_bank <= 1'b0; // Deassert the bank-switch trigger.
        
        read_data(4'd1); 
        read_data(4'd2); 
        read_data(4'd3); 
        
        @(posedge clk);
        re <= 1'b0;

        repeat(5) @(posedge clk);
        $display("\n--- SIMULATION COMPLETED ---");
        $finish;
    end

    // =========================================================================
    // Output Monitor
    // =========================================================================
    // Delay the read-enable signal by one clock cycle to align it with the RAM output.
    reg re_q;
    always @(posedge clk) begin
        if (!rstn) re_q <= 0;
        else       re_q <= re;
    end
    
    always @(posedge clk) begin
        #1; // Allow the registered rd_data output to update before monitoring.
        if (re_q) begin
            $display("Time %0t | DSP Reading Active Bank [%0d] | Data: 0x%0h", 
                     $time, active_read_bank, rd_data);
        end
    end

endmodule