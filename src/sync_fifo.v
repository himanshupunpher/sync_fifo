module sync_fifo (
    input clk,
    input rst,
    input wr_en,
    input [7:0] data_in,
    input rd_en,
    output reg [7:0] data_out,
    output reg full,
    output reg empty
);
    localparam DEPTH = 8, WIDTH = 8;
    reg [WIDTH - 1:0] mem [0:DEPTH - 1];
    reg [3:0] rd_ptr, wr_ptr;
    always @(*) begin
       empty = (wr_ptr == rd_ptr) ? 1 : 0;
       full = (wr_ptr[2:0] == rd_ptr[2:0]) && (wr_ptr[3] != rd_ptr[3]); 
    end
    always @(posedge clk) begin
        if(rst) begin
            data_out <= 0;
            rd_ptr <= 0;
            wr_ptr <= 0;
        end     
        else begin
            if(wr_en && !full) begin
                mem[wr_ptr[2:0]] <= data_in;
                wr_ptr <= wr_ptr + 1;
            end
            if(rd_en && !empty) begin
                data_out <= mem[rd_ptr[2:0]];
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
