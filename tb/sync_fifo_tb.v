`timescale 1ns/1ps

module sync_fifo_tb;

    reg clk;
    reg rst;
    reg wr_en;
    reg [7:0] data_in;
    reg rd_en;
    wire [7:0] data_out;
    wire full;
    wire empty;

    sync_fifo dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .data_in(data_in),
        .rd_en(rd_en),
        .data_out(data_out),
        .full(full),
        .empty(empty)
    );

    always #5 clk = ~clk;

    integer i;
	
initial begin
    $dumpfile("fifo.vcd");
    $dumpvars(0, sync_fifo_tb);
end
    initial begin
        clk = 0;
        rst = 1;
        wr_en = 0;
        rd_en = 0;
        data_in = 0;

        #12;
        rst = 0;

        #1;
        if (empty !== 1) $display("FAIL: FIFO should be empty after reset");
        if (full !== 0) $display("FAIL: FIFO should not be full after reset");
        else $display("PASS: reset state correct (empty=%b full=%b)", empty, full);

        @(negedge clk);
        wr_en = 1; data_in = 8'hA5;
        @(negedge clk);
        wr_en = 0;
        if (empty !== 0) $display("FAIL: FIFO should not be empty after one write");

        rd_en = 1;
        @(negedge clk);
        rd_en = 0;
        #1;
        if (data_out !== 8'hA5) $display("FAIL: expected A5, got %h", data_out);
        else $display("PASS: single write/read returned correct data");
        if (empty !== 1) $display("FAIL: FIFO should be empty again after read");

        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            wr_en = 1;
            data_in = i;
        end
        @(negedge clk);
        wr_en = 0;
        #1;
        if (full !== 1) $display("FAIL: FIFO should be full after 8 writes");
        else $display("PASS: full flag asserted correctly after filling FIFO");

        @(negedge clk);
        wr_en = 1;
        data_in = 8'hFF;
        @(negedge clk);
        wr_en = 0;
        #1;
        if (full !== 1) $display("FAIL: full should still be asserted, overflow write not blocked correctly");
        else $display("PASS: write correctly blocked while full");

        for (i = 0; i < 8; i = i + 1) begin
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
            #1;
            if (data_out !== i)
                $display("FAIL: expected %0d, got %0d on read #%0d", i, data_out, i);
        end
        $display("PASS: drained FIFO, data order check done above (no FAIL = correct FIFO ordering)");

        #1;
        if (empty !== 1) $display("FAIL: FIFO should be empty after draining all 8 bytes");
        else $display("PASS: empty flag asserted correctly after full drain");

        @(negedge clk);
        rd_en = 1;
        @(negedge clk);
        rd_en = 0;
        #1;
        if (empty !== 1) $display("FAIL: empty should still be asserted, underflow read not blocked correctly");
        else $display("PASS: read correctly blocked while empty");

        @(negedge clk);
        wr_en = 1; data_in = 8'h11;
        @(negedge clk);
        wr_en = 0;
        @(negedge clk);
        wr_en = 1; data_in = 8'h22;
        rd_en = 1;
        @(negedge clk);
        wr_en = 0; rd_en = 0;
        #1;
        if (data_out !== 8'h11) $display("FAIL: simultaneous read/write - expected 11, got %h", data_out);
        else $display("PASS: simultaneous read/write handled correctly");

        #20;
        $display("---- Testbench complete ----");
        $finish;
    end

endmodule
