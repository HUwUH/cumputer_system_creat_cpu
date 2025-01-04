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
    output wire [31:0] data_sram_wdata, // 数据存储器写入数据

    //XXX:lby:add
    output wire [37:0] ex_to_id,
    output wire stallreq_from_ex,
    output wire ex_is_load,
    output wire [65:0] hilo_ex_to_id
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
    wire [3:0] data_ram_wen,data_ram_readen;           // 数据存储器写使能信号
    wire rf_we;                        // 寄存器写使能信号
    wire [4:0] rf_waddr;               // 寄存器写地址
    wire sel_rf_res;                   // 寄存器写入数据来源选择信号
    wire [31:0] rf_rdata1, rf_rdata2;  // 寄存器读数据1和读数据2
    reg is_in_delayslot;               // 是否在延迟槽

    assign {
        data_ram_readen,//168:165
        inst_mthi,      //164
        inst_mtlo,      //163
        inst_multu,     //162
        inst_mult,      //161
        inst_divu,      //160
        inst_div,       //159
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

    // 对应于load指令
    assign ex_is_load = (inst[31:26] == 6'b10_0011) ? 1'b1 : 1'b0;

    // 立即数和移位数的扩展
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]}; // 符号扩展立即数
    assign imm_zero_extend = {16'b0, inst[15:0]};         // 零扩展立即数
    assign sa_zero_extend = {27'b0,inst[10:6]};           // 零扩展移位数

    // ALU操作数选择
    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :              // 如果选择信号为1，选择PC值
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
        data_ram_readen,// 79:76 //XXX:添加
        ex_pc,          // 75:44 当前指令的PC值
        data_ram_en,    // 43 数据存储器使能信号
        data_ram_wen,   // 42:39 数据存储器写使能信号
        sel_rf_res,     // 38 寄存器写入数据来源选择信号
        rf_we,          // 37 寄存器写使能信号
        rf_waddr,       // 36:32 寄存器写地址
        ex_result       // 31:0 EX阶段结果
    };

    assign  ex_to_id ={   
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };



    /*XXX: 添加内存读取系统
    这段代码的功能是 控制数据内存的读写操作，具体包括：

        使能信号：控制是否访问数据内存。
        写使能信号：根据访问类型和地址对齐方式生成正确的写使能信号。
        地址信号：将执行阶段计算的内存地址传递给数据内存。
        写入数据：根据写使能信号将寄存器文件中的数据按需对齐并写入内存。
    */
    assign data_sram_en = data_ram_en;
    assign data_sram_wen =   (data_ram_readen==4'b0101 && ex_result[1:0] == 2'b00 )? 4'b0001 
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b01 )? 4'b0010
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b10 )? 4'b0100
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b11 )? 4'b1000
                            :(data_ram_readen==4'b0111 && ex_result[1:0] == 2'b00 )? 4'b0011
                            :(data_ram_readen==4'b0111 && ex_result[1:0]== 2'b10 )? 4'b1100
                            : data_ram_wen;//写使能信号        
    assign data_sram_addr = ex_result;  //内存的地址
    assign data_sram_wdata = data_sram_wen==4'b1111 ? rf_rdata2 
                            :data_sram_wen==4'b0001 ? {24'b0,rf_rdata2[7:0]}
                            :data_sram_wen==4'b0010 ? {16'b0,rf_rdata2[7:0],8'b0}
                            :data_sram_wen==4'b0100 ? {8'b0,rf_rdata2[7:0],16'b0}
                            :data_sram_wen==4'b1000 ? {rf_rdata2[7:0],24'b0}
                            :data_sram_wen==4'b0011 ? {16'b0,rf_rdata2[15:0]}
                            :data_sram_wen==4'b1100 ? {rf_rdata2[15:0],16'b0}
                            :32'b0;

    //XXX: 没添加乘法除法
    wire hi_wen,lo_wen,inst_mthi,inst_mtlo;
    wire [31:0] hi_data,lo_data;
    assign hi_wen = inst_divu | inst_div | inst_mult | inst_multu | inst_mthi;//hi寄存器 写
    assign lo_wen = inst_divu | inst_div | inst_mult | inst_multu | inst_mtlo;//lo寄存器 写

    assign hi_data =  (inst_div|inst_divu)   ? div_result[63:32] //高32位为余数
                    : (inst_mult|inst_multu) ? mul_result[63:32] 
                    : (inst_mthi)            ? rf_rdata1
                    : (32'b0);

    assign lo_data =  (inst_div|inst_divu)   ? div_result[31:0] //低32位为商
                    : (inst_mult|inst_multu) ? mul_result[31:0] 
                    : (inst_mtlo)            ? rf_rdata1
                    : (32'b0);  



    assign hilo_ex_to_id = {
        hi_wen,         // 65
        lo_wen,         // 64
        hi_data,        // 63:32
        lo_data         // 31:0
    };


    
    // MUL part
    wire inst_mult,inst_multu;
    wire [63:0] mul_result;


    wire mul_signed; // 有符号乘法标记
    assign mul_signed =   inst_mult  ? 1 
                        : inst_multu ? 0 
                        : 0; 
    
    wire [31:0] mul_data1,mul_data2;
    assign mul_data1 = (inst_mult | inst_multu) ? rf_rdata1 : 32'b0;
    assign mul_data2 = (inst_mult | inst_multu) ? rf_rdata2 : 32'b0;

    mul u_mul(
    	.clk        (clk            ),
        .resetn     (~rst           ),
        .mul_signed (mul_signed     ),
        .ina        (mul_opdata1_o      ), // 乘法源操作数1
        .inb        (mul_opdata2_o      ), // 乘法源操作数2
        .result     (mul_result     ) // 乘法结果 64bit
    );


    // DIV part 除法单元
    wire [63:0] div_result;
    wire inst_div, inst_divu;         // 是否是除法指令
    wire div_ready_i;                 // 除法结果是否准备好
    reg stallreq_for_div;             // 除法暂停信号
    assign stallreq_from_ex = stallreq_for_div ;

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
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
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
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    // gpt删除了这一行： // mul_result 和 div_result 可以直接使用
    
    
endmodule