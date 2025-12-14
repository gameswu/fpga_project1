`timescale 1ns / 1ps

module pe_array_tb;

    // Parameters
    parameter ARRAY_SIZE = 16;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;

    // Signals
    reg clk;
    reg rst_n;
    reg enable;
    reg acc_clear;
    reg weight_load;
    
    // Updated widths for fully parallel inputs (16x16 unique values)
    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] data_in;
    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] weight_in;
    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] acc_out;

    // Instantiate DUT
    pe_array #(
        .ARRAY_DIM(ARRAY_SIZE), // Map TB parameter to DUT parameter
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .weight_write_enable(enable),
        .acc_clear(acc_clear),
        .weight_load(weight_load),
        .data_in(data_in),
        .weight_in(weight_in),
        .acc_out(acc_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Helper task to set weight for a specific PE(row, col)
    task set_weight(input integer row, input integer col, input integer val);
        begin
            weight_in[((row * ARRAY_SIZE + col) * DATA_WIDTH) +: DATA_WIDTH] = val;
        end
    endtask

    // Helper task to set data for a specific PE(row, col)
    task set_data(input integer row, input integer col, input integer val);
        begin
            data_in[((row * ARRAY_SIZE + col) * DATA_WIDTH) +: DATA_WIDTH] = val;
        end
    endtask

    // Helper function to get output from a PE
    function [ACC_WIDTH-1:0] get_acc(input integer row, input integer col);
        begin
            get_acc = acc_out[((row * ARRAY_SIZE + col) * ACC_WIDTH) +: ACC_WIDTH];
        end
    endfunction

    integer i, j;
    integer errors;

    // Test Sequence
    initial begin
        $dumpfile("pe_array_tb.vcd");
        $dumpvars(0, pe_array_tb);
        
        // Initialize
        rst_n = 0;
        enable = 0;
        acc_clear = 0;
        weight_load = 0;
        data_in = 0;
        weight_in = 0;
        errors = 0;

        // Reset
        #20;
        rst_n = 1;
        #10;

        // 1. Load Weights
        // Set Weight(i,j) = i + 1
        $display("Loading Weights...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                set_weight(i, j, i + 1);
            end
        end
        
        weight_load = 1;
        #10;
        weight_load = 0;
        #10;

        // 2. Run Computation
        // Set Input(i,j) = j + 1
        $display("Running Computation...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                set_data(i, j, j + 1);
            end
        end

        enable = 1;
        #10; // Cycle 1
        enable = 0;
        #10;

        // 3. Check Results
        // Expected: Acc(i,j) = Weight(i,j) * Input(i,j) = (i+1) * (j+1)
        $display("Checking Results...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                if (get_acc(i, j) !== (i + 1) * (j + 1)) begin
                    $display("ERROR at PE(%0d, %0d): Expected %0d, Got %0d", 
                        i, j, (i + 1) * (j + 1), get_acc(i, j));
                    errors = errors + 1;
                end
            end
        end
        
        // Check a specific one
        $display("PE(2, 3) [Row 2, Col 3]: Weight=%0d, Input=%0d, Acc=%0d", 
            3, 4, get_acc(2, 3)); 

        // 4. Accumulate again with different values
        $display("Accumulating again with unique values...");
        // Set Input(i,j) = i + j
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                set_data(i, j, i + j);
            end
        end
        
        enable = 1;
        #10;
        enable = 0;
        #10;
        
        // Check PE(2, 3)
        // i=2, j=3
        // Prev Acc = 12
        // Weight = 3
        // New Input = 2 + 3 = 5
        // New Term = 5 * 3 = 15
        // Total = 12 + 15 = 27
        
        if (get_acc(2, 3) !== 27) begin
             $display("ERROR at PE(2, 3) after 2nd cycle: Expected 27, Got %0d", get_acc(2, 3));
             errors = errors + 1;
        end else begin
             $display("PE(2, 3) Accumulation OK: %0d", get_acc(2, 3));
        end

        // 5. Clear
        $display("Clearing...");
        acc_clear = 1;
        #10;
        acc_clear = 0;
        #10;
        
        if (get_acc(5, 5) !== 0) begin
            $display("ERROR: Clear failed");
            errors = errors + 1;
        end else begin
            $display("Clear OK");
        end

        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TESTS FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule
