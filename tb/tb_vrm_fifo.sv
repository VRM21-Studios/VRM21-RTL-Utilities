`timescale 1ns / 1ps

module tb_vrm_fifo;

    localparam DATA_WIDTH = 32;
    localparam FIFO_DEPTH = 16; 
    localparam CLK_PERIOD = 10;

    reg                   aclk;
    reg                   aresetn;

    // =========================================================================
    // AXI-Stream Slave Interface (Producer)
    // =========================================================================
    reg  [DATA_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tlast;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    wire                  s_axis_almost_full;

    // =========================================================================
    // AXI-Stream Master Interface (Consumer)
    // =========================================================================
    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tlast;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    vrm_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tlast(s_axis_tlast), .s_axis_tvalid(s_axis_tvalid), 
        .s_axis_tready(s_axis_tready), .s_axis_almost_full(s_axis_almost_full),
        .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast), .m_axis_tvalid(m_axis_tvalid), 
        .m_axis_tready(m_axis_tready)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial aclk = 0;
    always #(CLK_PERIOD/2.0) aclk = ~aclk;

    // =========================================================================
    // AXI-Stream Stimulus Task
    // Inputs are driven on the falling edge to avoid race conditions.
    // =========================================================================
    task automatic push_data(input [DATA_WIDTH-1:0] data, input tlast);
    begin
        @(negedge aclk);
        s_axis_tdata  = data;
        s_axis_tlast  = tlast;
        s_axis_tvalid = 1'b1;

        @(posedge aclk);
        while (s_axis_tready == 1'b0) begin
            @(posedge aclk); // Wait safely while the FIFO is applying backpressure.
        end
    end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("dump_fifo.vcd");
        $dumpvars(0, tb_vrm_fifo);

        aresetn = 0;
        s_axis_tdata = 0; s_axis_tlast = 0; s_axis_tvalid = 0;
        m_axis_tready = 0; 

        #(CLK_PERIOD * 5) aresetn = 1;
        $display("=== VRM FIFO STRESS TEST ===");

        $display("\n--- SCENARIO 1: BACKPRESSURE AND RECOVERY ---");
        // The producer attempts to transmit 20 data words while the FIFO depth is 16.
        // The consumer starts later to release backpressure and allow transmission to continue.
        fork
            // THREAD A: PRODUCER
            begin
                for (int i = 0; i < 20; i++) begin
                    push_data(32'hD000 + i, (i == 19));
                    $display("[%0t] PRODUCER: Data 0x%h successfully accepted!", $time, 32'hD000 + i);
                end
                @(negedge aclk);
                s_axis_tvalid = 1'b0;
                $display("[%0t] PRODUCER: All 20 data words transmitted successfully.", $time);
            end
            
            // THREAD B: CONSUMER
            begin
                #(CLK_PERIOD * 25); // Allow sufficient time for the FIFO to reach the full condition.
                $display("[%0t] CONSUMER: FIFO backpressure is expected. Starting data consumption.", $time);
                
                @(negedge aclk);
                m_axis_tready = 1'b1;
                
                for (int j = 0; j < 20; j++) begin
                    @(posedge aclk);
                    while (m_axis_tvalid == 1'b0) @(posedge aclk);
                    $display("[%0t] CONSUMER: Received Data 0x%h | TLAST: %b", $time, m_axis_tdata, m_axis_tlast);
                end
                
                @(negedge aclk);
                m_axis_tready = 1'b0;
            end
        join

        #50;
        $display("\n--- SCENARIO 2: SIMULTANEOUS PUSH-POP (STREAMING) ---");
        fork
            begin
                for (int i = 0; i < 5; i++) begin
                    push_data(32'hAABB_0000 + i, (i == 4));
                end
                @(negedge aclk);
                s_axis_tvalid = 1'b0;
            end
            begin
                @(negedge aclk);
                m_axis_tready = 1'b1;
                for (int j = 0; j < 5; j++) begin
                    @(posedge aclk);
                    while (m_axis_tvalid == 1'b0) @(posedge aclk);
                    $display("[%0t] STREAMING OUTPUT: 0x%h", $time, m_axis_tdata);
                end
                @(negedge aclk);
                m_axis_tready = 1'b0;
            end
        join

        #50;
        $display("\nVRM FIFO stress test completed successfully.");
        $finish;
    end

    // =========================================================================
    // Real-Time Almost-Full Monitor
    // =========================================================================
    always @(posedge aclk) begin
        #1;
        if (s_axis_almost_full && s_axis_tvalid && s_axis_tready) 
            $display("   [ALERT] FIFO capacity is approaching its limit at %0t", $time);
    end

endmodule