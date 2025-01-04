`include "lib/defines.vh"
module CTRL(
    input wire rst, // 复位信号
    input wire stallreq_from_ex,  // 来自EX阶段的暂停请求信号
    input wire stallreq_from_id,

    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall  // 流水线各阶段的暂停信号
);  

    // stall[0] 为 1 表示没有暂停
    // stall[1] 为 1 表示 IF 阶段暂停
    // stall[2] 为 1 表示 ID 阶段暂停
    // stall[3] 为 1 表示 EX 阶段暂停
    // stall[4] 为 1 表示 MEM 阶段暂停
    // stall[5] 为 1 表示 WB 阶段暂停

    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0;
        end
        else begin
            stall = `StallBus'b0;
        end
    end

endmodule
