`include "defines.vh"  // 包含定义文件，可能定义了常量或宏

module regfile(
    input wire clk,          // 时钟信号，用于同步写操作
    input wire [4:0] raddr1, // 第一个读地址，指定要读取的寄存器
    output wire [31:0] rdata1, // 第一个读数据，输出对应寄存器的值
    input wire [4:0] raddr2, // 第二个读地址，指定要读取的寄存器
    output wire [31:0] rdata2, // 第二个读数据，输出对应寄存器的值
    
    input wire we,           // 写使能信号，控制是否进行写操作
    input wire [4:0] waddr,  // 写地址，指定要写入的寄存器
    input wire [31:0] wdata  // 写数据，要写入寄存器的值
);
    // 定义寄存器数组，32个32位寄存器
    reg [31:0] reg_array [31:0];

    // 写操作逻辑
    always @ (posedge clk) begin
        if (we && waddr != 5'b0) begin  // 如果写使能有效且写地址不为0
            reg_array[waddr] <= wdata;  // 将写数据写入指定寄存器
        end
    end

    // 读操作逻辑1
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : reg_array[raddr1];
    // 如果读地址为0，输出0（MIPS中$0寄存器恒为0）；否则输出对应寄存器的值

    // 读操作逻辑2
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : reg_array[raddr2];
    // 如果读地址为0，输出0；否则输出对应寄存器的值
endmodule