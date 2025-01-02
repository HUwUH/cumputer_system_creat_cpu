`include "lib/defines.vh"

module WB(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    // input wire flush,
    input wire [`StallBus-1:0] stall,  // 流水线暂停信号

    input wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,  // 从MEM阶段传来的数据

    output wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 送到RF阶段的数据

    output wire [31:0] debug_wb_pc,  // 调试：WB阶段的PC值
    output wire [3:0] debug_wb_rf_wen,  // 调试：WB阶段的寄存器写使能信号
    output wire [4:0] debug_wb_rf_wnum,  // 调试：WB阶段的寄存器写地址
    output wire [31:0] debug_wb_rf_wdata  // 调试：WB阶段的寄存器写数据
);

    reg [`MEM_TO_WB_WD-1:0] mem_to_wb_bus_r;  // 存储从MEM阶段传来的数据

    always @ (posedge clk) begin
        if (rst) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        end
        // else if (flush) begin
        //     mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        // end
        else if (stall[4]==`Stop && stall[5]==`NoStop) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        end
        else if (stall[4]==`NoStop) begin
            mem_to_wb_bus_r <= mem_to_wb_bus;
        end
    end

    // 从mem_to_wb_bus_r寄存器中提取各个信号
    wire [31:0] wb_pc;  // WB阶段的PC值
    wire rf_we;  // 寄存器文件写使能信号
    wire [4:0] rf_waddr;  // 寄存器文件写地址
    wire [31:0] rf_wdata;  // 寄存器文件写数据

    assign {
        wb_pc,
        rf_we,
        rf_waddr,
        rf_wdata
    } = mem_to_wb_bus_r;  // 将mem_to_wb_bus_r中的信号拆解成多个变量

    assign wb_to_rf_bus = {
        rf_we,
        rf_waddr,
        rf_wdata
    };

    assign debug_wb_pc = wb_pc;  // WB阶段的PC值
    assign debug_wb_rf_wen = {4{rf_we}};  // 如果写使能为1，设置4个bit为1
    assign debug_wb_rf_wnum = rf_waddr;  // 写入的寄存器地址
    assign debug_wb_rf_wdata = rf_wdata;  // 写入的寄存器数据
    
endmodule