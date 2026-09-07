module simple_counter #(
    parameter integer WIDTH = 8,
    parameter integer MAX_COUNT = 255
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             enable,
    output reg  [WIDTH-1:0] count,
    output wire             overflow
);

    initial begin
        count = {WIDTH{1'b0}};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {WIDTH{1'b0}};
        end else if (enable) begin
            if (count == MAX_COUNT[WIDTH-1:0]) begin
                count <= {WIDTH{1'b0}};
            end else begin
                count <= count + {{(WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end

    assign overflow = enable && (count == MAX_COUNT[WIDTH-1:0]);

endmodule
