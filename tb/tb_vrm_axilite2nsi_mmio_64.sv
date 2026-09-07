`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_vrm_axilite2nsi_mmio_64
//
// Description:
//   Cycle-accurate verification environment for the AXI4-Lite to NSI
//   MMIO bridge.
//
// Verification coverage:
//   - Independent AW/W transactions
//   - AW-first write
//   - W-first write
//   - Simultaneous AW/W
//   - Delayed BREADY
//   - Basic read
//   - Delayed RREADY
//   - Write/readback
//   - Back-to-back transactions
//   - Read/write arbitration
//   - Randomized traffic
//   - Native write pulse monitoring
//   - AXI timeout detection
//
// Clocking discipline:
//   - AXI VALID signals are driven on the falling clock edge.
//   - AXI handshakes are sampled on the rising clock edge.
//   - This avoids races between the testbench and DUT sequential logic.
// ============================================================================

module tb_vrm_axilite2nsi_mmio_64;

    // =========================================================================
    // 1. PARAMETERS
    // =========================================================================

    parameter integer C_S_AXI_DATA_WIDTH = 64;
    parameter integer C_S_AXI_ADDR_WIDTH = 64;

    parameter integer AXI_TIMEOUT_CYCLES = 100;
    parameter integer RANDOM_TEST_COUNT  = 32;


    // =========================================================================
    // 2. CLOCK AND RESET
    // =========================================================================

    reg s_axi_aclk;
    reg s_axi_aresetn;


    // =========================================================================
    // 3. AXI4-LITE WRITE ADDRESS CHANNEL
    // =========================================================================

    reg  [63:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;


    // =========================================================================
    // 4. AXI4-LITE WRITE DATA CHANNEL
    // =========================================================================

    reg  [63:0] s_axi_wdata;
    reg  [7:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;


    // =========================================================================
    // 5. AXI4-LITE WRITE RESPONSE CHANNEL
    // =========================================================================

    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;


    // =========================================================================
    // 6. AXI4-LITE READ ADDRESS CHANNEL
    // =========================================================================

    reg  [63:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;


    // =========================================================================
    // 7. AXI4-LITE READ DATA CHANNEL
    // =========================================================================

    wire [63:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;


    // =========================================================================
    // 8. NATIVE NSI INTERFACE
    // =========================================================================

    wire [63:0] mmio_addr;
    wire [63:0] mmio_wdata;
    wire        mmio_we;

    reg  [63:0] mmio_rdata;


    // =========================================================================
    // 9. DEVICE UNDER TEST
    // =========================================================================

    vrm_axilite2nsi_mmio_64 #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) dut (
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),

        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .mmio_we       (mmio_we),
        .mmio_addr     (mmio_addr),
        .mmio_wdata    (mmio_wdata),
        .mmio_rdata    (mmio_rdata)
    );


    // =========================================================================
    // 10. NATIVE REGISTER MODEL
    // =========================================================================

    reg [63:0] dummy_reg [0:7];

    integer i;

    initial begin
        for (i = 0; i < 8; i = i + 1)
            dummy_reg[i] = 64'h0;
    end


    // =========================================================================
    // 11. NATIVE WRITE MONITOR
    // =========================================================================

    integer native_write_count;

    reg [63:0] last_native_addr;
    reg [63:0] last_native_wdata;

    initial begin
        native_write_count = 0;
        last_native_addr   = 64'h0;
        last_native_wdata  = 64'h0;
    end


    // =========================================================================
    // 12. NATIVE MMIO MODEL
    // =========================================================================
    //
    // The native interface is synchronous.
    //
    // A native write is committed when mmio_we is high at a rising edge.
    // Read data is generated with one-cycle registered latency.
    // =========================================================================

    always @(posedge s_axi_aclk) begin

        if (mmio_we) begin

            dummy_reg[mmio_addr[5:3]] <= mmio_wdata;

            last_native_addr  <= mmio_addr;
            last_native_wdata <= mmio_wdata;

            native_write_count = native_write_count + 1;

            $display(
                "[NSI WRITE] t=%0t addr=%016h data=%016h",
                $time,
                mmio_addr,
                mmio_wdata
            );

        end

        mmio_rdata <= dummy_reg[mmio_addr[5:3]];

    end


    // =========================================================================
    // 13. CLOCK
    // =========================================================================

    initial begin

        s_axi_aclk = 1'b0;

        forever #5 s_axi_aclk = ~s_axi_aclk;

    end


    // =========================================================================
    // 14. TEST STATUS
    // =========================================================================

    integer pass_count;
    integer fail_count;

    reg test_failed;

    initial begin

        pass_count  = 0;
        fail_count  = 0;
        test_failed = 1'b0;

    end


    // =========================================================================
    // 15. TEST REPORT TASKS
    // =========================================================================

    task pass_test;
        input [1023:0] message;

        begin

            pass_count = pass_count + 1;

            $display(
                "[PASS] %0s",
                message
            );

        end
    endtask


    task fail_test;
        input [1023:0] message;

        begin

            fail_count  = fail_count + 1;
            test_failed = 1'b1;

            $display(
                "[FAIL] %0s",
                message
            );

        end

    endtask


    // =========================================================================
    // 16. RESET TASK
    // =========================================================================

    task reset_dut;

        begin

            s_axi_aresetn = 1'b0;

            s_axi_awaddr  = 64'h0;
            s_axi_awvalid = 1'b0;

            s_axi_wdata   = 64'h0;
            s_axi_wstrb   = 8'h00;
            s_axi_wvalid  = 1'b0;

            s_axi_bready  = 1'b0;

            s_axi_araddr  = 64'h0;
            s_axi_arvalid = 1'b0;

            s_axi_rready  = 1'b0;

            mmio_rdata    = 64'h0;

            repeat (5)
                @(posedge s_axi_aclk);

            @(negedge s_axi_aclk);

            s_axi_aresetn = 1'b1;

            repeat (2)
                @(posedge s_axi_aclk);

            $display("[INFO] DUT reset complete.");

        end

    endtask


    // =========================================================================
    // 17. AXI WRITE TASK
    // =========================================================================
    //
    // aw_delay and w_delay specify how many falling edges are waited before
    // each corresponding VALID signal is asserted.
    //
    // Examples:
    //
    //   aw_delay=0, w_delay=0 -> simultaneous AW/W
    //   aw_delay=0, w_delay=4 -> AW first
    //   aw_delay=4, w_delay=0 -> W first
    // =========================================================================

    task axi_write;

        input [63:0] addr;
        input [63:0] data;

        input integer aw_delay;
        input integer w_delay;
        input integer bready_delay;

        integer cycle_count;

        integer aw_started;
        integer w_started;

        integer aw_done;
        integer w_done;

        integer b_done;

        begin

            cycle_count = 0;

            aw_started = 0;
            w_started  = 0;

            aw_done = 0;
            w_done  = 0;

            b_done = 0;


            // -----------------------------------------------------------------
            // Prepare channel payloads.
            // -----------------------------------------------------------------

            s_axi_awaddr = addr;
            s_axi_wdata  = data;
            s_axi_wstrb  = 8'hFF;

            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;

            s_axi_bready = 1'b0;


            // -----------------------------------------------------------------
            // AW/W handshake phase.
            // -----------------------------------------------------------------

            while ((aw_done == 0) || (w_done == 0)) begin

                @(negedge s_axi_aclk);

                cycle_count = cycle_count + 1;


                // -------------------------------------------------------------
                // Launch AW.
                // -------------------------------------------------------------

                if ((aw_started == 0) &&
                    (cycle_count > aw_delay)) begin

                    s_axi_awvalid = 1'b1;
                    aw_started    = 1;

                end


                // -------------------------------------------------------------
                // Launch W.
                // -------------------------------------------------------------

                if ((w_started == 0) &&
                    (cycle_count > w_delay)) begin

                    s_axi_wvalid = 1'b1;
                    w_started    = 1;

                end


                // -------------------------------------------------------------
                // Wait for handshake edge.
                // -------------------------------------------------------------

                @(posedge s_axi_aclk);


                // -------------------------------------------------------------
                // AW handshake.
                // -------------------------------------------------------------

                if ((aw_done == 0) &&
                    s_axi_awvalid &&
                    s_axi_awready) begin

                    aw_done = 1;

                    $display(
                        "[AXI AW] t=%0t addr=%016h",
                        $time,
                        addr
                    );

                end


                // -------------------------------------------------------------
                // W handshake.
                // -------------------------------------------------------------

                if ((w_done == 0) &&
                    s_axi_wvalid &&
                    s_axi_wready) begin

                    w_done = 1;

                    $display(
                        "[AXI W ] t=%0t data=%016h",
                        $time,
                        data
                    );

                end


                if (cycle_count > AXI_TIMEOUT_CYCLES) begin

                    fail_test(
                        "AXI write AW/W handshake timeout"
                    );

                    s_axi_awvalid = 1'b0;
                    s_axi_wvalid  = 1'b0;

                    return;

                end

            end


            // -----------------------------------------------------------------
            // Remove VALID after the handshake edge.
            // -----------------------------------------------------------------

            @(negedge s_axi_aclk);

            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;


            // -----------------------------------------------------------------
            // Delay BREADY.
            // -----------------------------------------------------------------

            repeat (bready_delay)
                @(negedge s_axi_aclk);

            s_axi_bready = 1'b1;


            // -----------------------------------------------------------------
            // B channel handshake.
            // -----------------------------------------------------------------

            cycle_count = 0;

            while (b_done == 0) begin

                @(posedge s_axi_aclk);

                cycle_count = cycle_count + 1;

                if (s_axi_bvalid && s_axi_bready) begin

                    b_done = 1;

                    if (s_axi_bresp !== 2'b00) begin

                        fail_test(
                            "AXI write response was not OKAY"
                        );

                    end

                end


                if (cycle_count > AXI_TIMEOUT_CYCLES) begin

                    fail_test(
                        "AXI write BVALID timeout"
                    );

                    s_axi_bready = 1'b0;

                    return;

                end

            end


            @(negedge s_axi_aclk);

            s_axi_bready = 1'b0;

        end

    endtask


    // =========================================================================
    // 18. EXPECT NATIVE WRITE
    // =========================================================================
    //
    // The write monitor runs independently, so this task does not depend on
    // catching the one-cycle mmio_we pulse directly.
    // =========================================================================

    task expect_native_write;

        input [63:0] expected_addr;
        input [63:0] expected_data;
        input integer initial_count;

        integer timeout;

        begin

            timeout = 0;

            while (native_write_count <= initial_count) begin

                @(posedge s_axi_aclk);

                timeout = timeout + 1;

                if (timeout > AXI_TIMEOUT_CYCLES) begin

                    fail_test(
                        "Native write transaction was not observed"
                    );

                    return;

                end

            end


            if (last_native_addr !== expected_addr) begin

                fail_test(
                    "Native write address mismatch"
                );

                $display(
                    "       Expected: %016h",
                    expected_addr
                );

                $display(
                    "       Actual  : %016h",
                    last_native_addr
                );

            end


            if (last_native_wdata !== expected_data) begin

                fail_test(
                    "Native write data mismatch"
                );

                $display(
                    "       Expected: %016h",
                    expected_data
                );

                $display(
                    "       Actual  : %016h",
                    last_native_wdata
                );

            end


            if ((last_native_addr === expected_addr) &&
                (last_native_wdata === expected_data)) begin

                pass_test(
                    "Native write address/data verified"
                );

            end

        end

    endtask


    // =========================================================================
    // 19. AXI READ TASK
    // =========================================================================

    task axi_read;

        input  [63:0] addr;
        output [63:0] data;

        input integer rready_delay;

        integer cycle_count;
        integer ar_done;
        integer r_done;

        begin

            data = 64'h0;

            cycle_count = 0;
            ar_done = 0;
            r_done  = 0;

            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b0;


            // -----------------------------------------------------------------
            // Assert ARVALID on falling edge.
            // -----------------------------------------------------------------

            @(negedge s_axi_aclk);

            s_axi_arvalid = 1'b1;


            // -----------------------------------------------------------------
            // AR handshake.
            // -----------------------------------------------------------------

            while (ar_done == 0) begin

                @(posedge s_axi_aclk);

                cycle_count = cycle_count + 1;

                if (s_axi_arvalid && s_axi_arready) begin

                    ar_done = 1;

                    $display(
                        "[AXI AR] t=%0t addr=%016h",
                        $time,
                        addr
                    );

                end


                if (cycle_count > AXI_TIMEOUT_CYCLES) begin

                    fail_test(
                        "AXI read AR handshake timeout"
                    );

                    s_axi_arvalid = 1'b0;

                    return;

                end

            end


            @(negedge s_axi_aclk);

            s_axi_arvalid = 1'b0;


            // -----------------------------------------------------------------
            // Delay RREADY.
            // -----------------------------------------------------------------

            repeat (rready_delay)
                @(negedge s_axi_aclk);

            s_axi_rready = 1'b1;


            // -----------------------------------------------------------------
            // R handshake.
            // -----------------------------------------------------------------

            cycle_count = 0;

            while (r_done == 0) begin

                @(posedge s_axi_aclk);

                cycle_count = cycle_count + 1;

                if (s_axi_rvalid && s_axi_rready) begin

                    data = s_axi_rdata;

                    r_done = 1;

                    if (s_axi_rresp !== 2'b00) begin

                        fail_test(
                            "AXI read response was not OKAY"
                        );

                    end

                end


                if (cycle_count > AXI_TIMEOUT_CYCLES) begin

                    fail_test(
                        "AXI read RVALID timeout"
                    );

                    s_axi_rready = 1'b0;

                    return;

                end

            end


            @(negedge s_axi_aclk);

            s_axi_rready = 1'b0;

        end

    endtask


    // =========================================================================
    // 20. TEST 1: BASIC WRITE
    // =========================================================================

    task test_basic_write;

        integer write_count;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 1: BASIC WRITE");
            $display("------------------------------------------------------------");

            write_count = native_write_count;

            fork

                begin
                    axi_write(
                        64'h0000_0010,
                        64'hDEAD_BEEF_CAFE_1234,
                        0,
                        0,
                        0
                    );
                end

                begin
                    expect_native_write(
                        64'h0000_0010,
                        64'hDEAD_BEEF_CAFE_1234,
                        write_count
                    );
                end

            join

        end

    endtask


    // =========================================================================
    // 21. TEST 2: AW FIRST
    // =========================================================================

    task test_aw_first;

        integer write_count;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 2: AW FIRST / W DELAYED");
            $display("------------------------------------------------------------");

            write_count = native_write_count;

            fork

                begin
                    axi_write(
                        64'h0000_0020,
                        64'h1111_2222_3333_4444,
                        0,
                        5,
                        0
                    );
                end

                begin
                    expect_native_write(
                        64'h0000_0020,
                        64'h1111_2222_3333_4444,
                        write_count
                    );
                end

            join

        end

    endtask


    // =========================================================================
    // 22. TEST 3: W FIRST
    // =========================================================================

    task test_w_first;

        integer write_count;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 3: W FIRST / AW DELAYED");
            $display("------------------------------------------------------------");

            write_count = native_write_count;

            fork

                begin
                    axi_write(
                        64'h0000_0028,
                        64'h5555_6666_7777_8888,
                        5,
                        0,
                        0
                    );
                end

                begin
                    expect_native_write(
                        64'h0000_0028,
                        64'h5555_6666_7777_8888,
                        write_count
                    );
                end

            join

        end

    endtask


    // =========================================================================
    // 23. TEST 4: BASIC READ
    // =========================================================================

    task test_basic_read;

        reg [63:0] read_value;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 4: BASIC READ");
            $display("------------------------------------------------------------");

            dummy_reg[2] = 64'hCAFE_1234_5678_9ABC;

            axi_read(
                64'h0000_0010,
                read_value,
                0
            );

            if (read_value === 64'hCAFE_1234_5678_9ABC) begin

                pass_test(
                    "Basic read returned expected data"
                );

            end else begin

                fail_test(
                    "Basic read returned incorrect data"
                );

                $display(
                    "       Expected: %016h",
                    64'hCAFE_1234_5678_9ABC
                );

                $display(
                    "       Actual  : %016h",
                    read_value
                );

            end

        end

    endtask


    // =========================================================================
    // 24. TEST 5: DELAYED BREADY
    // =========================================================================

    task test_delayed_bready;

        integer write_count;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 5: DELAYED BREADY");
            $display("------------------------------------------------------------");

            write_count = native_write_count;

            fork

                begin
                    axi_write(
                        64'h0000_0030,
                        64'hAAAA_BBBB_CCCC_DDDD,
                        0,
                        0,
                        8
                    );
                end

                begin
                    expect_native_write(
                        64'h0000_0030,
                        64'hAAAA_BBBB_CCCC_DDDD,
                        write_count
                    );
                end

            join

        end

    endtask


    // =========================================================================
    // 25. TEST 6: DELAYED RREADY
    // =========================================================================

    task test_delayed_rready;

        reg [63:0] read_value;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 6: DELAYED RREADY");
            $display("------------------------------------------------------------");

            dummy_reg[3] = 64'h1234_5678_9ABC_DEF0;

            axi_read(
                64'h0000_0018,
                read_value,
                8
            );

            if (read_value === 64'h1234_5678_9ABC_DEF0) begin

                pass_test(
                    "Delayed RREADY read passed"
                );

            end else begin

                fail_test(
                    "Delayed RREADY read mismatch"
                );

            end

        end

    endtask


    // =========================================================================
    // 26. TEST 7: WRITE / READBACK
    // =========================================================================

    task test_write_readback;

        integer write_count;
        reg [63:0] read_value;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 7: WRITE / READBACK");
            $display("------------------------------------------------------------");

            write_count = native_write_count;

            fork

                begin
                    axi_write(
                        64'h0000_0018,
                        64'h0BAD_F00D_DEAD_BEEF,
                        0,
                        3,
                        0
                    );
                end

                begin
                    expect_native_write(
                        64'h0000_0018,
                        64'h0BAD_F00D_DEAD_BEEF,
                        write_count
                    );
                end

            join


            axi_read(
                64'h0000_0018,
                read_value,
                0
            );


            if (read_value === 64'h0BAD_F00D_DEAD_BEEF) begin

                pass_test(
                    "Write/readback test passed"
                );

            end else begin

                fail_test(
                    "Write/readback mismatch"
                );

            end

        end

    endtask


    // =========================================================================
    // 27. TEST 8: BACK-TO-BACK WRITES
    // =========================================================================

    task test_back_to_back_writes;

        integer k;
        integer write_count;

        reg [63:0] addr;
        reg [63:0] data;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 8: BACK-TO-BACK WRITES");
            $display("------------------------------------------------------------");

            for (k = 0; k < 8; k = k + 1) begin

                addr = k * 8;
                data = 64'h1000_0000_0000_0000 + k;

                write_count = native_write_count;

                fork

                    begin
                        axi_write(
                            addr,
                            data,
                            0,
                            0,
                            0
                        );
                    end

                    begin
                        expect_native_write(
                            addr,
                            data,
                            write_count
                        );
                    end

                join

            end

        end

    endtask


    // =========================================================================
    // 28. TEST 9: BACK-TO-BACK READS
    // =========================================================================

    task test_back_to_back_reads;

        integer k;

        reg [63:0] read_value;
        reg [63:0] expected_value;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 9: BACK-TO-BACK READS");
            $display("------------------------------------------------------------");

            for (k = 0; k < 8; k = k + 1) begin

                expected_value =
                    64'h9000_0000_0000_0000 + k;

                dummy_reg[k] = expected_value;

                axi_read(
                    k * 8,
                    read_value,
                    0
                );

                if (read_value !== expected_value) begin

                    fail_test(
                        "Back-to-back read mismatch"
                    );

                end

            end

        end

    endtask


    // =========================================================================
    // 29. TEST 10: RANDOMIZED WRITE
    // =========================================================================

    task test_random_writes;

        integer k;
        integer write_count;

        integer random_index;

        reg [63:0] random_addr;
        reg [63:0] random_data;

        integer aw_delay;
        integer w_delay;
        integer b_delay;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 10: RANDOMIZED WRITE TRAFFIC");
            $display("------------------------------------------------------------");

            for (k = 0; k < RANDOM_TEST_COUNT; k = k + 1) begin

                random_index = $urandom_range(0, 7);

                random_addr = random_index * 8;

                random_data = {
                    $urandom,
                    $urandom
                };

                aw_delay = $urandom_range(0, 4);
                w_delay  = $urandom_range(0, 4);
                b_delay  = $urandom_range(0, 4);

                write_count = native_write_count;

                fork

                    begin
                        axi_write(
                            random_addr,
                            random_data,
                            aw_delay,
                            w_delay,
                            b_delay
                        );
                    end

                    begin
                        expect_native_write(
                            random_addr,
                            random_data,
                            write_count
                        );
                    end

                join

            end

        end

    endtask


    // =========================================================================
    // 30. TEST 11: RANDOMIZED READ
    // =========================================================================

    task test_random_reads;

        integer k;
        integer random_index;

        reg [63:0] random_addr;
        reg [63:0] expected_data;
        reg [63:0] read_value;

        integer r_delay;

        begin

            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 11: RANDOMIZED READ TRAFFIC");
            $display("------------------------------------------------------------");

            for (k = 0; k < RANDOM_TEST_COUNT; k = k + 1) begin

                random_index = $urandom_range(0, 7);

                random_addr = random_index * 8;

                expected_data = {
                    $urandom,
                    $urandom
                };

                dummy_reg[random_index] = expected_data;

                r_delay = $urandom_range(0, 4);

                axi_read(
                    random_addr,
                    read_value,
                    r_delay
                );

                if (read_value !== expected_data) begin

                    fail_test(
                        "Randomized read mismatch"
                    );

                    $display(
                        "       Address : %016h",
                        random_addr
                    );

                    $display(
                        "       Expected: %016h",
                        expected_data
                    );

                    $display(
                        "       Actual  : %016h",
                        read_value
                    );

                end

            end

        end

    endtask


    // =========================================================================
    // 31. TEST 12: SIMULTANEOUS READ/WRITE
    // =========================================================================
    //
    // Both write and read request are presented together.
    //
    // The bridge must serialize them and eventually complete both transactions.
    // =========================================================================

    task test_simultaneous_read_write;
    
        integer timeout;
    
        integer aw_done;
        integer w_done;
        integer ar_done;
    
        integer b_done;
        integer r_done;
    
        reg [63:0] read_value;
    
        begin
    
            $display("");
            $display("------------------------------------------------------------");
            $display("TEST 12: SIMULTANEOUS READ/WRITE");
            $display("------------------------------------------------------------");
    
            dummy_reg[0] = 64'hFACE_FACE_FACE_FACE;
    
            // -------------------------------------------------------------
            // Present read and write requests simultaneously.
            // Write has priority in the DUT.
            // ------------------------------------------------------------
    
            @(negedge s_axi_aclk);
    
            s_axi_awaddr   = 64'h0000_0010;
            s_axi_wdata    = 64'h1357_2468_9ABC_DEF0;
            s_axi_wstrb    = 8'hFF;
    
            s_axi_araddr   = 64'h0000_0000;
    
            s_axi_awvalid  = 1'b1;
            s_axi_wvalid   = 1'b1;
            s_axi_arvalid  = 1'b1;
    
            s_axi_bready   = 1'b1;
            s_axi_rready   = 1'b1;
    
            aw_done = 0;
            w_done  = 0;
            ar_done = 0;
    
            b_done = 0;
            r_done = 0;
    
            timeout = 0;
    
            // -------------------------------------------------------------
            // Resolve all AXI transactions.
            // -------------------------------------------------------------
    
            while ((b_done == 0) || (r_done == 0)) begin
    
                @(posedge s_axi_aclk);
    
                timeout = timeout + 1;
    
                // ---------------------------------------------------------
                // Capture write-address handshake.
                // ---------------------------------------------------------
    
                if ((aw_done == 0) &&
                    s_axi_awvalid &&
                    s_axi_awready) begin
    
                    aw_done = 1;
    
                    s_axi_awvalid = 1'b0;
    
                    $display(
                        "[AXI AW] t=%0t addr=%016h",
                        $time,
                        s_axi_awaddr
                    );
    
                end
    
    
                // ---------------------------------------------------------
                // Capture write-data handshake.
                // ---------------------------------------------------------
    
                if ((w_done == 0) &&
                    s_axi_wvalid &&
                    s_axi_wready) begin
    
                    w_done = 1;
    
                    s_axi_wvalid = 1'b0;
    
                    $display(
                        "[AXI W ] t=%0t data=%016h",
                        $time,
                        s_axi_wdata
                    );
    
                end
    
    
                // ---------------------------------------------------------
                // Capture read-address handshake.
                //
                // This will normally happen only after the write request
                // has been removed from the AXI interface.
                // ---------------------------------------------------------
    
                if ((ar_done == 0) &&
                    s_axi_arvalid &&
                    s_axi_arready) begin
    
                    ar_done = 1;
    
                    s_axi_arvalid = 1'b0;
    
                    $display(
                        "[AXI AR] t=%0t addr=%016h",
                        $time,
                        s_axi_araddr
                    );
    
                end
    
    
                // ---------------------------------------------------------
                // Write response handshake.
                // ---------------------------------------------------------
    
                if (s_axi_bvalid && s_axi_bready) begin
    
                    b_done = 1;
    
                    if (s_axi_bresp !== 2'b00) begin
    
                        fail_test(
                            "Simultaneous write returned non-OKAY response"
                        );
    
                    end
    
                end
    
    
                // ---------------------------------------------------------
                // Read response handshake.
                // ---------------------------------------------------------
    
                if (s_axi_rvalid && s_axi_rready) begin
    
                    r_done = 1;
    
                    read_value = s_axi_rdata;
    
                    if (s_axi_rresp !== 2'b00) begin
    
                        fail_test(
                            "Simultaneous read returned non-OKAY response"
                        );
    
                    end
    
                end
    
    
                // ---------------------------------------------------------
                // Timeout protection.
                // ---------------------------------------------------------
    
                if (timeout > AXI_TIMEOUT_CYCLES) begin
    
                    fail_test(
                        "Simultaneous read/write transaction timeout"
                    );
    
                    s_axi_awvalid = 1'b0;
                    s_axi_wvalid  = 1'b0;
                    s_axi_arvalid = 1'b0;
    
                    s_axi_bready  = 1'b0;
                    s_axi_rready  = 1'b0;
    
                    return;
    
                end
    
            end
    
    
            @(negedge s_axi_aclk);
    
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_arvalid = 1'b0;
    
            s_axi_bready = 1'b0;
            s_axi_rready = 1'b0;
    
    
            // -------------------------------------------------------------
            // Verify that both transactions completed.
            // -------------------------------------------------------------
    
            if ((aw_done == 1) &&
                (w_done  == 1) &&
                (ar_done == 1) &&
                (b_done  == 1) &&
                (r_done  == 1) &&
                (read_value === 64'hFACE_FACE_FACE_FACE)) begin
    
                pass_test(
                    "Simultaneous read/write arbitration passed"
                );
    
            end else begin
    
                fail_test(
                    "Simultaneous read/write result mismatch"
                );
    
            end
    
        end
    
    endtask


    // =========================================================================
    // 32. MAIN TEST SEQUENCE
    // =========================================================================

    initial begin

        $dumpfile(
            "dump_axilite_mmio_robust.vcd"
        );

        $dumpvars(
            0,
            tb_vrm_axilite2nsi_mmio_64
        );


        reset_dut();


        test_basic_write();

        test_aw_first();

        test_w_first();

        test_basic_read();

        test_delayed_bready();

        test_delayed_rready();

        test_write_readback();

        test_back_to_back_writes();

        test_back_to_back_reads();

        test_random_writes();

        test_random_reads();

        test_simultaneous_read_write();


        #100;


        $display("");
        $display("============================================================");
        $display("VRM AXI4-LITE TO NSI MMIO VERIFICATION SUMMARY");
        $display("============================================================");

        $display(
            "PASS COUNT : %0d",
            pass_count
        );

        $display(
            "FAIL COUNT : %0d",
            fail_count
        );

        $display(
            "NATIVE WRITES OBSERVED : %0d",
            native_write_count
        );


        if (test_failed == 1'b0) begin

            $display("");
            $display("OVERALL RESULT: PASS");
            $display("");

        end else begin

            $display("");
            $display("OVERALL RESULT: FAIL");
            $display("");

        end


        $finish;

    end

endmodule
