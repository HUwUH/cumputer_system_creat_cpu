`include "lib/defines.vh"  // 引入外部定义文件，通常用于存储常量和宏定义

// IF阶段模块：负责获取指令并决定下一个PC地址
module IF(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    input wire [`StallBus-1:0] stall,  // 流水线暂停信号

    // 输入信号：分支信息
    input wire [`BR_WD-1:0] br_bus,  // 分支信号，包括是否为分支（br_e）和分支地址（br_addr）

    // 输出信号：从IF到ID阶段的总线
    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 传递到ID阶段的信息

    // 输出信号：与指令SRAM的交互信号
    output wire inst_sram_en,  // 指令SRAM使能信号
    output wire [3:0] inst_sram_wen,  // 指令SRAM写使能信号
    output wire [31:0] inst_sram_addr,  // 指令SRAM地址
    output wire [31:0] inst_sram_wdata  // 指令SRAM写数据
);
    // PC寄存器：保存当前程序计数器（PC）值
    reg [31:0] pc_reg;

    // CE寄存器：用于控制指令获取模块是否有效
    reg ce_reg;

    // 下一个PC的值
    wire [31:0] next_pc;

    // 分支有效信号及分支地址
    wire br_e;
    wire [31:0] br_addr;

    // 将分支信号和分支地址从br_bus中解码
    assign {
        br_e,   // br_e: 是否为分支
        br_addr // br_addr: 分支地址
    } = br_bus;

    // 每个时钟周期更新PC寄存器的值
    always @ (posedge clk) begin
        if (rst) begin
            // 如果复位信号有效，则将PC重置为指定值
            pc_reg <= 32'hbfbf_fffc;  // 初始化PC值
        end
        else if (stall[0] == `NoStop) begin
            // 如果没有暂停信号，则根据next_pc更新PC寄存器
            pc_reg <= next_pc;
        end
    end

    // 控制CE寄存器的更新
    always @ (posedge clk) begin
        if (rst) begin
            ce_reg <= 1'b0;  // 复位时关闭CE
        end
        else if (stall[0] == `NoStop) begin
            ce_reg <= 1'b1;  // 没有暂停时启用CE
        end
    end

    // 计算下一个PC地址
    assign next_pc = br_e ? br_addr // 如果是分支，则跳转到分支地址
                   : pc_reg + 32'h4; // 否则，PC加4（指向下一条指令）

    // 指令SRAM的信号：设置使能信号、写使能信号、地址、写数据
    assign inst_sram_en = ce_reg;  // 如果CE有效，则使能SRAM
    assign inst_sram_wen = 4'b0;   // 无需写数据，所以写使能为0
    assign inst_sram_addr = pc_reg;  // 指令SRAM地址为当前PC地址
    assign inst_sram_wdata = 32'b0;  // 不向SRAM写数据，因此写数据为0

    // 将PC和CE寄存器的值传递到ID阶段
    assign if_to_id_bus = {
        ce_reg,  // 控制信号ce_reg
        pc_reg   // 当前PC值
    };

endmodule
