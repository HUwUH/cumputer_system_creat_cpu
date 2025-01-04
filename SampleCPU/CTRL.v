`include "lib/defines.vh"
module CTRL(
    input wire rst, // 复位信号
    input wire stallreq_from_ex,  // 来自EX阶段的暂停请求信号
    input wire stallreq_from_id,

    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall  // 流水线各阶段的暂停信号
);  

    // lby：https://www.cnblogs.com/yangykaifa/p/6823998.html
    // stall[0]：表示取值地址PC是否保持不变，为1表示不变
    // stall[1] 为 1 表示 IF 阶段暂停
    // stall[2] 为 1 表示 ID 阶段暂停
    // stall[3] 为 1 表示 EX 阶段暂停
    // stall[4] 为 1 表示 MEM 阶段暂停
    // stall[5] 为 1 表示 WB 阶段暂停

    always @ (*) begin
        //XXX:lby:很好理解，如果ex发起stall，那么ex和之后的都stall
        //                  如果id发起stall，那么mem和之后都stall
        if (rst) begin
            stall <= `StallBus'b0;
        end
        else if(stallreq_from_ex == 1'b1) begin
            stall <= 6'b001111;
        end
        else if(stallreq_from_id == 1'b1) begin
            stall <= 6'b000111;
        end else begin 
            stall <= 6'b000000;
        end
    end

endmodule
