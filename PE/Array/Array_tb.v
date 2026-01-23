`timescale 1ns / 1ps

module Array_tb;

    // ------------------------------------------------------
    // Parameters
    // ------------------------------------------------------
    parameter ROWS = 32;
    parameter COLS = 16;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;

    // ------------------------------------------------------
    // Signals
    // ------------------------------------------------------
    reg clk;
    reg rst_n;
    reg en;
    reg mode_max;

    // Weight Interface
    reg [ROWS-1:0] weight_we_row;
    reg [COLS*DATA_WIDTH-1:0] weight_in_col;

    // Data Interface
    reg [ROWS*DATA_WIDTH-1:0] feature_in_rows;
    reg [COLS*ACC_WIDTH-1:0] psum_in_cols;

    // Outputs
    wire [ROWS*DATA_WIDTH-1:0] feature_out_rows;
    wire [COLS*ACC_WIDTH-1:0] psum_out_cols;

    // Helper array for easier feature assignment
    reg [DATA_WIDTH-1:0] feature_data_array [ROWS-1:0];

    // Flags for verification
    reg col0_passed;
    reg col15_passed;

    // ------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------
    pe_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .mode_max(mode_max),
        .weight_we_row(weight_we_row),
        .weight_in_col(weight_in_col),
        .feature_in_rows(feature_in_rows),
        .psum_in_cols(psum_in_cols),
        .feature_out_rows(feature_out_rows),
        .psum_out_cols(psum_out_cols)
    );

    // ------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // ------------------------------------------------------
    // Data Packing Logic
    // ------------------------------------------------------
    integer r, c;
    always @(*) begin
        // Pack feature_data_array into flat feature_in_rows bus
        for (r = 0; r < ROWS; r = r + 1) begin
            feature_in_rows[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH] = feature_data_array[r];
        end
    end

    // ------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] last_col_out;

    initial begin
        // 1. Initialization
        rst_n = 0;
        en = 0;
        mode_max = 0;
        weight_we_row = 0;
        weight_in_col = 0;
        psum_in_cols = 0; // Keep psum input at 0
        col0_passed = 0;
        col15_passed = 0;
        for (r = 0; r < ROWS; r = r + 1) feature_data_array[r] = 0;

        $display("Simulation Start: Resetting...");
        #100;
        @(posedge clk);
        rst_n = 1;
        #20;

        // 2. Load Weights
        // Load unique weights: PE[row][col] = (row + col + 1)
        // This ensures each PE has a different weight
        // For example: Row0: 1,2,3,...,16  Row1: 2,3,4,...,17  Row31: 32,33,...,47
        $display("Step 1: Loading Weights (Unique per PE: row+col+1)...");
        
        // Enable write for each row sequentially
        for (r = 0; r < ROWS; r = r + 1) begin
            // Prepare weight data for this specific row
            for (c = 0; c < COLS; c = c + 1) begin
                weight_in_col[(c+1)*DATA_WIDTH-1 -: DATA_WIDTH] = (r + c + 1); // Unique per PE
            end
            
            @(posedge clk);
            weight_we_row = 0;
            weight_we_row[r] = 1; // Select row r
        end
        
        @(posedge clk);
        weight_we_row = 0; // Disable write
        $display("Weights Loaded.");

        // 3. Run Systolic Computation
        // We will inject a diagonal wave of '5's.
        // Row 0 gets '5' at t=0
        // Row 1 gets '5' at t=1
        // ...
        // Row 31 gets '5' at t=31
        // Expected: Col0 = sum(row=0..31: (row+0+1)*5) = sum(1..32)*5 = 528*5 = 2640
        //           Col15 = sum(row=0..31: (row+15+1)*5) = sum(16..47)*5 = 1008*5 = 5040
        
        $display("Step 2: Injecting Skewed Inputs (value=5)...");
        @(posedge clk);
        en = 1;
        
        // Run for enough cycles for the wave to propagate to the bottom-right
        // Increased loop count to account for potential extra pipeline stages in DSP IP
        for (integer t = 0; t < 100; t = t + 1) begin
            
            // Update Inputs for this cycle
            for (r = 0; r < ROWS; r = r + 1) begin
                if (t == r) begin
                    feature_data_array[r] = 8'd5; // Inject pulse with value 5
                end else begin
                    feature_data_array[r] = 8'd0;
                end
            end

            // Wait for clock edge to process
            @(posedge clk);
            
            // Monitor Outputs (Delayed check to allow signal stability)
            #1; 
            
            // Check Column 0 Output: sum((1+2+...+32)*5) = 528*5 = 2640
            if (!col0_passed && psum_out_cols[ACC_WIDTH-1:0] == 2640) begin
                $display("[PASS] Time %t: Col 0 Output matched 2640 (sum(1..32)*5) at cycle t=%d", $time, t);
                col0_passed = 1;
            end

            // Check Column 15 Output: sum((16+17+...+47)*5) = 1008*5 = 5040
            last_col_out = psum_out_cols[COLS*ACC_WIDTH-1 -: ACC_WIDTH];
            if (!col15_passed && last_col_out == 5040) begin
                $display("[PASS] Time %t: Col 15 Output matched 5040 (sum(16..47)*5) at cycle t=%d", $time, t);
                col15_passed = 1;
            end
        end

        if (col0_passed && col15_passed)
            $display("Step 2: MAC Simulation SUCCESS.");
        else begin
            $display("Step 2: MAC Simulation FAILED.");
        end

        // ------------------------------------------------------
        // 4. Test Max Pooling Mode
        // ------------------------------------------------------
        $display("\nStep 3: Testing Max Pooling Mode...");
        
        // Reset
        en = 0;
        mode_max = 1; // Enable Max Pooling
        col0_passed = 0;
        col15_passed = 0;
        for (r = 0; r < ROWS; r = r + 1) feature_data_array[r] = 0;
        
        #20;
        @(posedge clk);
        en = 1;
        
        // We will inject a pattern with varying values: Row 0=15, Row 5=23, Row 10=127, Row 20=42, others=18
        // Expected Output: Max(15, 18, ..., 23, ..., 127, ..., 42, ..., 18) = 127
        // Skewing is still required for the values to align in the column pipeline.
        
        for (integer t = 0; t < 100; t = t + 1) begin
            
            // Update Inputs
            for (r = 0; r < ROWS; r = r + 1) begin
                if (t == r) begin
                    if (r == 0) 
                        feature_data_array[r] = 8'd15;
                    else if (r == 5)
                        feature_data_array[r] = 8'd23;
                    else if (r == 10) 
                        feature_data_array[r] = 8'd127; // Max value at Row 10
                    else if (r == 20)
                        feature_data_array[r] = 8'd42;
                    else 
                        feature_data_array[r] = 8'd18;  // Other rows
                end else begin
                    feature_data_array[r] = 8'd0;
                end
            end

            @(posedge clk);
            #1; 
            
            // Check Column 0 Output
            // Expected: 127
            if (!col0_passed && psum_out_cols[ACC_WIDTH-1:0] == 127) begin
                $display("[PASS] Time %t: Col 0 Max Output matched 127 at cycle t=%d", $time, t);
                col0_passed = 1;
            end
            
            // Check Column 0 for incorrect Sum (if it was summing, it would be much larger)
            if (psum_out_cols[ACC_WIDTH-1:0] > 600) begin
                 $display("[FAIL] Time %t: Col 0 is SUMMING instead of MAX pooling! Got %d", $time, psum_out_cols[ACC_WIDTH-1:0]);
            end

            // Check Column 15 Output
            last_col_out = psum_out_cols[COLS*ACC_WIDTH-1 -: ACC_WIDTH];
            if (!col15_passed && last_col_out == 127) begin
                $display("[PASS] Time %t: Col 15 Max Output matched 127 at cycle t=%d", $time, t);
                col15_passed = 1;
            end
        end
        
        if (col0_passed && col15_passed)
            $display("Step 3: Max Pooling Simulation SUCCESS.");
        else
            $display("Step 3: Max Pooling Simulation FAILED.");

        $finish;
    end

endmodule
