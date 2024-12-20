`include "lib/defines.vh"  // 包含定义文件，提供常量和宏定义

module EX(
    input wire clk,            // 时钟信号
    input wire rst,            // 复位信号,
    // input wire flush,
    input wire [`StallBus-1:0] stall, // 流水线暂停控制信号

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus, // 从ID阶段传递到EX阶段的数据总线

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus, // EX阶段传递到MEM阶段的数据总线

    output wire data_sram_en,  // 数据存储器使能信号
    output wire [3:0] data_sram_wen, // 数据存储器写使能信号
    output wire [31:0] data_sram_addr, // 数据存储器地址
    output wire [31:0] data_sram_wdata // 数据存储器写入数据
);

    // 保存从ID阶段传递过来的数据，用于流水线暂停时的数据保持
    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0; // 复位时清零
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0; // 如果EX阶段暂停但MEM阶段未暂停，清除当前数据
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus; // 正常传递数据
        end
    end

    // 解码从ID阶段传递的总线数据
    wire [31:0] ex_pc, inst;           // 当前指令的PC值和指令内容
    wire [11:0] alu_op;                // ALU操作码
    wire [2:0] sel_alu_src1;           // ALU操作数1选择信号
    wire [3:0] sel_alu_src2;           // ALU操作数2选择信号
    wire data_ram_en;                  // 数据存储器使能信号
    wire [3:0] data_ram_wen;           // 数据存储器写使能信号
    wire rf_we;                        // 寄存器写使能信号
    wire [4:0] rf_waddr;               // 寄存器写地址
    wire sel_rf_res;                   // 寄存器写入数据来源选择信号
    wire [31:0] rf_rdata1, rf_rdata2;  // 寄存器读数据1和读数据2
    reg is_in_delayslot;               // 是否在延迟槽

    assign {
        ex_pc,          // 148:117 当前指令的PC值
        inst,           // 116:85 当前指令
        alu_op,         // 84:83 ALU操作码
        sel_alu_src1,   // 82:80 ALU操作数1选择信号
        sel_alu_src2,   // 79:76 ALU操作数2选择信号
        data_ram_en,    // 75 数据存储器使能信号
        data_ram_wen,   // 74:71 数据存储器写使能信号
        rf_we,          // 70 寄存器写使能信号
        rf_waddr,       // 69:65 寄存器写地址
        sel_rf_res,     // 64 寄存器写入数据来源选择信号
        rf_rdata1,      // 63:32 寄存器读数据1
        rf_rdata2       // 31:0 寄存器读数据2
    } = id_to_ex_bus_r;

    // 立即数和移位数的扩展
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]}; // 符号扩展立即数
    assign imm_zero_extend = {16'b0, inst[15:0]};         // 零扩展立即数
    assign sa_zero_extend = {27'b0,inst[10:6]};           // 零扩展移位数

    // ALU操作数选择
    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :               // 如果选择信号为1，选择PC值
                      sel_alu_src1[2] ? sa_zero_extend :     // 如果选择信号为2，选择移位数
                      rf_rdata1;                             // 默认选择寄存器数据1

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :     // 符号扩展立即数
                      sel_alu_src2[2] ? 32'd8 :              // 常数8
                      sel_alu_src2[3] ? imm_zero_extend :    // 零扩展立即数
                      rf_rdata2;                             // 默认选择寄存器数据2

    // 实例化ALU
    alu u_alu(
    	.alu_control (alu_op ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );

    assign ex_result = alu_result; // EX阶段结果

    // 输出到MEM阶段的数据总线
    assign ex_to_mem_bus = {
        ex_pc,          // 75:44 当前指令的PC值
        data_ram_en,    // 43 数据存储器使能信号
        data_ram_wen,   // 42:39 数据存储器写使能信号
        sel_rf_res,     // 38 寄存器写入数据来源选择信号
        rf_we,          // 37 寄存器写使能信号
        rf_waddr,       // 36:32 寄存器写地址
        ex_result       // 31:0 EX阶段结果
    };

    // MUL part 乘法单元
    wire [63:0] mul_result;
    wire mul_signed; // 有符号乘法标记

    mul u_mul(
    	.clk        (clk            ),
        .resetn     (~rst           ),
        .mul_signed (mul_signed     ),
        .ina        (      ), // 乘法源操作数1
        .inb        (      ), // 乘法源操作数2
        //gpt修改上两行如下
        // .ina        (rf_rdata1      ), // 乘法源操作数1
        // .inb        (rf_rdata2      ), // 乘法源操作数2
        .result     (mul_result     ) // 乘法结果 64bit
    );

    // DIV part 除法单元
    wire [63:0] div_result;
    wire inst_div, inst_divu;         // 是否是除法指令
    wire div_ready_i;                 // 除法结果是否准备好
    reg stallreq_for_div;             // 除法暂停信号
    assign stallreq_for_ex = stallreq_for_div;

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    div u_div(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_div_i (signed_div_o ),
        .opdata1_i    (div_opdata1_o    ),
        .opdata2_i    (div_opdata2_o    ),
        .start_i      (div_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (div_result     ), // 除法结果 64bit
        .ready_o      (div_ready_i      )
    );

    // 除法控制逻辑
    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin // 有符号除法
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    //gpt删除了这一段------------------------------开始
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    //gpt删除了这一段------------------------------结束
                end
                2'b01:begin // 无符号除法
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    //gpt删除了这一段------------------------------开始
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    //gpt删除了这一段------------------------------结束
                end
                default:begin
                end
            endcase
        end
    end

    //gpt删除了这一行： // mul_result 和 div_result 可以直接使用
    
    
endmodule