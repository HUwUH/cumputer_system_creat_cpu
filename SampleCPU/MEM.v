`include "lib/defines.vh" // 引入定义文件，包含常量和宏定义

module MEM(
    input wire clk,                  // 时钟信号
    input wire rst,                  // 复位信号
    // input wire flush,             // 流水线清空信号（注释掉，可能未使用）
    input wire [`StallBus-1:0] stall, // 流水线暂停信号

    input wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus, // 来自EX阶段的数据总线
    input wire [31:0] data_sram_rdata,            // 数据存储器读取的数据（来自MEM阶段）

    output wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus  // 传递给WB阶段的数据总线
);

    // 保存EX阶段传递到MEM阶段的数据总线
    reg [`EX_TO_MEM_WD-1:0] ex_to_mem_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0; // 复位时清零
        end
        // else if (flush) begin
        //     ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        // end
        else if (stall[3]==`Stop && stall[4]==`NoStop) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0; // 如果MEM阶段暂停，但WB阶段未暂停，清除当前数据
        end
        else if (stall[3]==`NoStop) begin
            ex_to_mem_bus_r <= ex_to_mem_bus; // 正常传递EX到MEM的数据总线
        end
    end

    // 解码来自EX阶段的数据
    wire [31:0] mem_pc;            // 当前指令的PC值
    wire data_ram_en;              // 数据存储器使能信号
    wire [3:0] data_ram_wen;       // 数据存储器写使能信号
    wire sel_rf_res;               // 寄存器写入数据来源选择信号
    wire rf_we;                    // 寄存器写使能信号
    wire [4:0] rf_waddr;           // 寄存器写地址
    wire [31:0] rf_wdata;          // 寄存器写数据
    wire [31:0] ex_result;         // EX阶段的计算结果
    wire [31:0] mem_result;        // MEM阶段的计算结果（可能来自数据存储器）

    // 从ex_to_mem_bus_r中解码出各个信号
    assign {
        mem_pc,         // 75:44 当前指令的PC值
        data_ram_en,    // 43 数据存储器使能信号
        data_ram_wen,   // 42:39 数据存储器写使能信号
        sel_rf_res,     // 38 寄存器写入数据来源选择信号
        rf_we,          // 37 寄存器写使能信号
        rf_waddr,       // 36:32 寄存器写地址
        ex_result       // 31:0 EX阶段计算结果
    } =  ex_to_mem_bus_r;

    //XXX:lby :添加memresult的赋值
    assign mem_result = data_sram_rdata;

    // 根据sel_rf_res信号选择寄存器写入的数据，若为1则使用MEM阶段结果，否则使用EX阶段结果
    assign rf_wdata = sel_rf_res ? mem_result : ex_result;

    // 构造传递到WB阶段的数据总线
    assign mem_to_wb_bus = {
        mem_pc,     // 69:38 当前指令的PC值
        rf_we,      // 37 寄存器写使能信号
        rf_waddr,   // 36:32 寄存器写地址
        rf_wdata    // 31:0 寄存器写入数据
    };




endmodule
