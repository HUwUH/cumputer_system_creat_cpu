`include "lib/defines.vh"

module CTRL(
    input wire rst,  // 复位信号
    input wire stallreq_from_ex,  // 来自EX阶段的暂停请求信号
    input wire stallreq_from_id,  // 来自ID阶段的暂停请求信号

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
            stall <= `StallBus'b0;  // 复位时将所有暂停信号清空，表示没有任何暂停
        end
        // 如果来自 EX 阶段的暂停请求为 1，暂停 IF、ID、EX、MEM 和 WB 阶段
        else if(stallreq_from_ex == 1'b1) begin
            stall <= 6'b001111;  // IF、ID、EX 阶段暂停，MEM 和 WB 阶段继续
        end
        // 如果来自 ID 阶段的暂停请求为 1，暂停 IF、ID 和 EX 阶段
        else if(stallreq_from_id == 1'b1) begin
            stall <= 6'b000111;  // IF、ID 阶段暂停，EX、MEM 和 WB 阶段继续
        end else begin 
            stall <= 6'b000000;  // 没有暂停请求时，所有阶段都继续
        end
    end
    
endmodule
