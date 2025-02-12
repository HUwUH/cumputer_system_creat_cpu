`include "lib/defines.vh"
module ID(
    input wire clk,                     // 时钟信号
    input wire rst,                     // 复位信号
    // input wire flush,                // 刷新信号（注释掉了）
    input wire [`StallBus-1:0] stall,   // 流水线暂停信号
    input wire ex_is_load,              // EX阶段是否为加载指令
    output wire stallreq,               // 请求暂停信号

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 从IF段传递到ID段的总线

    input wire [31:0] inst_sram_rdata,  // 从指令存储器读取的指令数据

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 从WB段传递到寄存器文件的总线

    input wire [37:0] ex_to_id,          // EX阶段传递到ID阶段的总线信号
    input wire [37:0] mem_to_id,         // MEM阶段传递到ID阶段的总线信号
    input wire [37:0] wb_to_id,          // WB阶段传递到ID阶段的总线信号

    input wire [65:0] hilo_ex_to_id,     // EX阶段传递到ID阶段的HI/LO寄存器信号
    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // 从ID段传递到EX段的总线

    output wire [`BR_WD-1:0] br_bus,  // 分支信号总线
    output wire stallreq_from_id         // ID阶段产生的暂停请求信号
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;  // 用于存储从IF段传递到ID段的总线数据
    wire [31:0] inst;  // 当前指令
    wire [31:0] id_pc;  // 当前指令的PC值
    wire ce;  // 指令有效信号

    wire wb_rf_we;                          // WB阶段寄存器写使能信号
    wire [4:0] wb_rf_waddr;                 // WB阶段寄存器写地址
    wire [31:0] wb_rf_wdata;                // WB阶段寄存器写数据

    wire wb_id_we;                          // WB阶段传递到ID阶段的写使能信号
    wire [4:0] wb_id_waddr;                 // WB阶段传递到ID阶段的写地址
    wire [31:0] wb_id_wdata;                // WB阶段传递到ID阶段的写数据

    wire mem_id_we;                         // MEM阶段传递到ID阶段的写使能信号
    wire [4:0] mem_id_waddr;                // MEM阶段传递到ID阶段的写地址
    wire [31:0] mem_id_wdata;               // MEM阶段传递到ID阶段的写数据
    reg q;                                  // 用于控制指令读取的寄存器
    wire ex_id_we;                          // EX阶段传递到ID阶段的写使能信号
    wire [4:0] ex_id_waddr;                 // EX阶段传递到ID阶段的写地址
    wire [31:0] ex_id_wdata;                // EX阶段传递到ID阶段的写数据

    // 在时钟上升沿更新if_to_id_bus_r的值
    always @ (posedge clk) begin
        if (rst) begin  // 如果复位信号有效，清零if_to_id_bus_r
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;        
        end
        // else if (flush) begin  // 如果刷新信号有效，清零if_to_id_bus_r（注释掉了）
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin  // 如果流水线暂停条件满足，清零if_to_id_bus_r
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin  // 如果流水线不暂停，更新if_to_id_bus_r
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    
    // 根据暂停信号更新q寄存器
    always @(posedge clk) begin
        if (stall[1]==`Stop) begin
            q <= 1'b1;  // 暂停时置1
        end
        else begin
            q <= 1'b0;  // 否则置0
        end
    end
    assign inst = (q) ?inst: inst_sram_rdata;  // 根据q的值选择指令


    // 从if_to_id_bus_r中提取指令有效信号和PC值
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;

    // 从wb_to_rf_bus中提取WB阶段的寄存器写信号
    assign {
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    // 从wb_to_id中提取WB阶段传递到ID阶段的写信号
    assign {
        wb_id_we,
        wb_id_waddr,
        wb_id_wdata
    } = wb_to_id;

    // 从mem_to_id中提取MEM阶段传递到ID阶段的写信号
    assign {
        mem_id_we,
        mem_id_waddr,
        mem_id_wdata
    } = mem_to_id;

    // 从ex_to_id中提取EX阶段传递到ID阶段的写信号
    assign {
        ex_id_we,
        ex_id_waddr,
        ex_id_wdata
    } = ex_to_id;




    wire [5:0] opcode;  // 指令的操作码
    wire [4:0] rs,rt,rd,sa;  // 指令中的寄存器地址和移位量
    wire [5:0] func;  // 指令的功能码
    wire [15:0] imm;  // 指令中的立即数
    wire [25:0] instr_index;  // 指令中的跳转地址索引
    wire [19:0] code;  // 指令中的代码字段
    wire [4:0] base;  // 指令中的基址寄存器
    wire [15:0] offset;  // 指令中的偏移量
    wire [2:0] sel;  // 选择信号

    wire [63:0] op_d, func_d;  // 操作码和功能码的译码结果
    wire [31:0] rs_d, rt_d, rd_d, sa_d;  // 寄存器地址的译码结果

    wire [2:0] sel_alu_src1;  // ALU第一个操作数的选择信号
    wire [3:0] sel_alu_src2;  // ALU第二个操作数的选择信号
    wire [11:0] alu_op;  // ALU操作控制信号

    wire data_ram_en;  // 数据存储器使能信号
    wire [3:0] data_ram_wen;  // 数据存储器写使能信号
    wire [3:0] data_ram_readen;  // 数据存储器读使能信号//XXX:新增
    
    wire rf_we;  // 寄存器文件写使能信号
    wire [4:0] rf_waddr;  // 寄存器文件写地址
    wire sel_rf_res;  // 寄存器文件写数据选择信号
    wire [2:0] sel_rf_dst;  // 寄存器文件写地址选择信号

    wire [31:0] rdata1, rdata2;  // 从寄存器文件读取的数据
    wire [31:0] rdata11, rdata22;  // 经过旁路处理的寄存器读数据//XXX:新增

    wire hi_r,hi_wen,lo_r,lo_wen;  // HI/LO寄存器读写信号//XXX:新增
    wire [31:0] hi_data;  // HI寄存器数据
    wire [31:0] lo_data;  // LO寄存器数据
    wire [31:0] hilo_data;  // HI/LO寄存器数据

    // 从hilo_ex_to_id中提取HI/LO寄存器信号//XXX:新增
    assign {
        hi_wen,         // 65
        lo_wen,         // 64
        hi_data,        // 63:32
        lo_data         // 31:0
    } = hilo_ex_to_id;

    assign hi_r = inst_mfhi;  // HI寄存器读使能//XXX:新增
    assign lo_r = inst_mflo;  // LO寄存器读使能

    // 实例化寄存器文件模块
    regfile u_regfile(
    	.clk    (clk    ),
        .raddr1 (rs ),
        .rdata1 (rdata1 ),
        .raddr2 (rt ),
        .rdata2 (rdata2 ),
        .we     (wb_rf_we     ),
        .waddr  (wb_rf_waddr  ),
        .wdata  (wb_rf_wdata  ),//XXX:新增

        .hi_r      ( hi_r   ),
        .hi_we     (  hi_wen   ),
        .hi_data   (  hi_data  ),
        .lo_r      (  lo_r   ),
        .lo_we     (   lo_wen   ),
        .lo_data   (   lo_data  ),
        .hilo_data (   hilo_data )
    );

    wire [31:0] mf_data;
    assign mf_data = (inst_mfhi & hi_wen) ? hi_data
                    :(inst_mfhi) ? hilo_data
                    :(inst_mflo & lo_wen) ? lo_data
                    :(inst_mflo) ? hilo_data
                    :(32'b0);
    
  
    assign rdata11 = (inst_mfhi | inst_mflo) ? mf_data
                   :(ex_id_we &(ex_id_waddr==rs))?ex_id_wdata
                   : (mem_id_we &(mem_id_waddr==rs)) ? mem_id_wdata
                   : (wb_id_we &(wb_id_waddr==rs)) ? wb_id_wdata 
                   : rdata1;
    assign rdata22 =  (inst_mfhi | inst_mflo) ? mf_data
                   :(ex_id_we &(ex_id_waddr==rt))?ex_id_wdata
                   : (mem_id_we &(mem_id_waddr==rt)) ? mem_id_wdata
                   : (wb_id_we &(wb_id_waddr==rt)) ? wb_id_wdata 
                   : rdata2;





    // 从指令中提取各个字段
    assign opcode = inst[31:26];
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    // 指令类型判断信号
    wire inst_ori, inst_lui, inst_addiu, inst_beq,
    inst_subu, inst_jr, inst_jal, inst_lw, inst_or, inst_sll, inst_addu, inst_bne,
    inst_xor, inst_xori, inst_nor, inst_sw, inst_sltu, inst_slt, inst_slti, inst_sltiu,
    inst_j, inst_add, inst_addi, inst_sub, inst_and, inst_andi, inst_sllv, inst_sra,
    inst_srav, inst_srl, inst_srlv, inst_bgez, inst_bgtz, inst_blez, inst_bltz,
    inst_bltzal, inst_bgezal, inst_jalr, inst_div, inst_divu, inst_mflo, inst_mfhi,
    inst_mult, inst_multu, inst_mthi, inst_mtlo, inst_lb, inst_lbu, inst_lh, inst_lhu,
    inst_sb, inst_lsa, inst_sh;  
    
    // ALU操作类型信号
    wire op_add, op_sub, op_slt, op_sltu;  
    wire op_and, op_nor, op_or, op_xor;
    wire op_sll, op_srl, op_sra, op_lui;

    // 实例化操作码译码器
    decoder_6_64 u0_decoder_6_64(
    	.in  (opcode  ),
        .out (op_d )
    );

    // 实例化功能码译码器
    decoder_6_64 u1_decoder_6_64(
    	.in  (func  ),
        .out (func_d )
    );
    
    // 实例化rs寄存器地址译码器
    decoder_5_32 u0_decoder_5_32(
    	.in  (rs  ),
        .out (rs_d )
    );

    // 实例化rt寄存器地址译码器
    decoder_5_32 u1_decoder_5_32(
    	.in  (rt  ),
        .out (rt_d )
    );
    /*TODO:这里指令数量不够
    */
    // 判断指令类型
    assign inst_ori     = op_d[6'b00_1101];//或立即数指令
    assign inst_lui     = op_d[6'b00_1111];//加载高位立即数指令
    assign inst_addiu   = op_d[6'b00_1001];//加立即数指令 (最终，目标寄存器 $rt 的值为：imm << 16)
    assign inst_beq     = op_d[6'b00_0100];//分支等于指令
    assign inst_subu    = op_d[6'b00_0000] && func_d[6'b10_0011];
    assign inst_jr      = op_d[6'b00_0000] && func_d[6'b00_1000];
    assign inst_jal     = op_d[6'b00_0011];
    assign inst_lw      = op_d[6'b10_0011];
    assign inst_addu    = op_d[6'b00_0000] && func_d[6'b10_0001];
    assign inst_or      = op_d[6'b00_0000] && func_d[6'b10_0101];
    assign inst_sll     = op_d[6'b00_0000] && func_d[6'b00_0000];
    assign inst_bne     = op_d[6'b00_0101];
    assign inst_xor     = op_d[6'b00_0000] && func_d[6'b10_0110];
    assign inst_xori    = op_d[6'b00_1110];
    assign inst_nor     = op_d[6'b00_0000] && func_d[6'b10_0111];
    assign inst_sw      = op_d[6'b10_1011]; 
    assign inst_sltu    = op_d[6'b00_0000] && func_d[6'b10_1011];
    assign inst_slt     = op_d[6'b00_0000] && func_d[6'b10_1010];
    assign inst_slti    = op_d[6'b00_1010];
    assign inst_sltiu   = op_d[6'b00_1011];
    assign inst_j       = op_d[6'b00_0010]; 
    assign inst_add     = op_d[6'b00_0000] && func_d[6'b10_0000];
    assign inst_addi    = op_d[6'b00_1000];
    assign inst_sub     = op_d[6'b00_0000] && func_d[6'b10_0010];
    assign inst_and     = op_d[6'b00_0000] && func_d[6'b10_0100];
    assign inst_andi    = op_d[6'b00_1100];
    assign inst_sllv    = op_d[6'b00_0000] && func_d[6'b00_0100];
    assign inst_sra     = op_d[6'b00_0000] && func_d[6'b00_0011];
    assign inst_srav    = op_d[6'b00_0000] && func_d[6'b00_0111];
    assign inst_srl     = op_d[6'b00_0000] && func_d[6'b00_0010];
    assign inst_srlv    = op_d[6'b00_0000] && func_d[6'b00_0110];
    assign inst_bgez    = op_d[6'b00_0001] && rt_d[5'b00001];
    assign inst_bgtz    = op_d[6'b00_0111] && rt_d[5'b00000];
    assign inst_blez    = op_d[6'b00_0110] && rt_d[5'b00000];
    assign inst_bltz    = op_d[6'b00_0001] && rt_d[5'b00000];
    assign inst_bltzal  = op_d[6'b00_0001] && rt_d[5'b10000];
    assign inst_bgezal  = op_d[6'b00_0001] && rt_d[5'b10001];
    assign inst_jalr    = op_d[6'b00_0000] && func_d[6'b00_1001];
    assign inst_div     = op_d[6'b00_0000] && func_d[6'b01_1010];
    assign inst_divu    = op_d[6'b00_0000] && func_d[6'b01_1011];
    assign inst_mflo    = op_d[6'b00_0000] && func_d[6'b01_0010];
    assign inst_mfhi    = op_d[6'b00_0000] && func_d[6'b01_0000];
    assign inst_mult    = op_d[6'b00_0000] && func_d[6'b01_1000];
    assign inst_multu   = op_d[6'b00_0000] && func_d[6'b01_1001];
    assign inst_mthi    = op_d[6'b00_0000] && func_d[6'b01_0001];
    assign inst_mtlo    = op_d[6'b00_0000] && func_d[6'b01_0011];
    assign inst_lb      = op_d[6'b10_0000];
    assign inst_lbu     = op_d[6'b10_0100];
    assign inst_lh      = op_d[6'b10_0001];
    assign inst_lhu     = op_d[6'b10_0101];
    assign inst_sb      = op_d[6'b10_1000];
    assign inst_sh      = op_d[6'b10_1001];
    assign inst_lsa     = op_d[6'b01_1100] && func_d[6'b11_0111];

    /*TODO: lby:这一段的操作数选择，有几个操作数始终不选择，有问题
            例如，分支操作，应该会用到“选择PC作为ALU的第一个操作数”
    */
    // ALU第一个操作数的选择逻辑
    assign sel_alu_src1[0] = inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu | inst_bgez | inst_srlv | inst_srav | inst_sllv | inst_andi | inst_and | inst_sub | inst_addi | inst_add | inst_sltiu | inst_slti | inst_slt | inst_sltu | inst_sw | inst_nor | inst_xori | inst_xor | inst_ori | inst_addiu | inst_subu | inst_jr | inst_lw | inst_addu | 
                            inst_or   | inst_mflo  |inst_mfhi | inst_lb |inst_lsa;  // 选择rs作为ALU的第一个操作数
    assign sel_alu_src1[1] = inst_jal | inst_bltzal | inst_bgezal |inst_jalr;  // 选择PC作为ALU的第一个操作数（未使用）
    assign sel_alu_src1[2] =inst_srl |inst_sra | inst_sll;  // 选择sa作为ALU的第一个操作数（未使用）

    // ALU第二个操作数的选择逻辑
    assign sel_alu_src2[0] = inst_lsa|inst_mfhi|inst_mflo | inst_srl | inst_srlv | inst_srav | inst_sra | inst_sllv | inst_and | inst_sub | inst_add | inst_slt | inst_sltu | inst_nor |
     inst_xor  | inst_subu | inst_addu | inst_or |
      inst_sll |inst_div | inst_divu;  // 选择rt作为ALU的第二个操作数（未使用）
    assign sel_alu_src2[1] = inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu | inst_addi | inst_sltiu | inst_slti | inst_sw | inst_lui | inst_addiu |
     inst_lw |inst_lb;  // 选择符号扩展的立即数作为ALU的第二个操作数
    assign sel_alu_src2[2] =inst_jal | inst_bltzal | inst_bgezal |inst_jalr;  // 选择常数8作为ALU的第二个操作数（未使用）
    assign sel_alu_src2[3] =  inst_andi | inst_xori | inst_ori;  // 选择零扩展的立即数作为ALU的第二个操作数

    /*TODO: lby:这一段可以根据指令集参考资料：1，在“判断指令类型”加判断
                2.然后在此处连上，为选择指令提供在某些条件下的成立
    */
    // ALU操作类型控制信号
    assign op_add =inst_lsa|inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu |  inst_lb | inst_addi | inst_add | inst_addiu | inst_lw | inst_addu | inst_jal | inst_sw | inst_bltzal |inst_bgezal|inst_jalr;
    assign op_sub =inst_sub | inst_subu;
    assign op_slt = inst_slt | inst_slti; //有符号比较
    assign op_sltu = inst_sltu|inst_sltiu;  //无符号比较
    assign op_and = inst_andi | inst_and | inst_mflo |inst_mfhi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xori |inst_xor;
    assign op_sll = inst_sllv | inst_sll;//逻辑左移
    assign op_srl = inst_srl | inst_srlv;//逻辑右移
    assign op_sra = inst_srav | inst_sra;//算术右移
    assign op_lui = inst_lui;

    // 组合ALU操作控制信号
    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};


    /*TODO: lby: 这一段，在部分指令下，应当给予赋值。
            例如：如果是ld（Load），那么en为1；如果是store，那么data_ram_wen为1
    */
    // 数据存储器使能和写使能信号（未使用）
    assign data_ram_en =inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu | inst_lw | inst_sw | inst_lb;
    assign data_ram_wen = inst_sw ? 4'b1111 : 4'b0000;

    // 数据存储器读使能信号
    assign data_ram_readen =  inst_lw  ? 4'b1111 
                             :inst_lb  ? 4'b0001 
                             :inst_lbu ? 4'b0010
                             :inst_lh  ? 4'b0011
                             :inst_lhu ? 4'b0100
                             :inst_sb  ? 4'b0101
                             :inst_sh  ? 4'b0111
                             :4'b0000;


    // 寄存器文件写使能信号
    assign rf_we =inst_lsa|inst_lhu | inst_lh | inst_lbu | inst_lb| inst_mfhi | 
    inst_mflo | inst_jalr |inst_bgezal | inst_bltzal|inst_srl | inst_srlv | 
    inst_srav | inst_sra | inst_sllv | inst_andi | inst_and | inst_sub | inst_addi 
    | inst_add | inst_sltiu | inst_slti | inst_slt | inst_sltu | inst_nor |inst_xori
    | inst_xor | inst_sll | inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal
    | inst_lw | inst_addu | inst_or;


    /*TODO：lby：结合上一个todo，结合mem段功能
            如果是store，需要设定好写到的地址，选择第几个指令的位置
    */
    // 寄存器文件写地址选择逻辑，判断
    assign sel_rf_dst[0] = inst_lsa|inst_mfhi | inst_mflo | inst_jalr |inst_srl | inst_srlv | inst_srav | inst_sra | inst_sllv | inst_and | inst_sub | inst_add 
    | inst_slt | inst_sltu | inst_nor | inst_xor |
     inst_subu | inst_addu | inst_or | inst_sll;  // 选择rd作为写地址
    assign sel_rf_dst[1]  = inst_lhu | inst_lh | inst_lbu | inst_lb |inst_andi | inst_addi | inst_sltiu | 
    inst_slti | inst_xori | inst_ori | inst_lui | inst_addiu | inst_lw;  // 选择rt作为写地址
    assign sel_rf_dst[2] = inst_jal | inst_bltzal | inst_bgezal;  // 选择31号寄存器作为写地址

    // 根据选择信号确定寄存器文件写地址
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    /*TODO：lby：结合上一个todo，结合mem段功能
            1.传给wb的是ex段的，为一种信号
            2.传给wb的是mem的如load，为另一种信号
    */
    // 寄存器文件写数据选择信号（未使用）//lby：这个gpt加的注释可能不对
    assign sel_rf_res = 1'b0; //学长的代码在这里没有修改

    // LSA指令处理
    wire [31:0] rdata111;
    assign rdata111 = (inst_lsa &inst[7:6]==2'b11) ? {rdata11[27:0] ,4'b0}
                    :(inst_lsa & inst[7:6]==2'b10) ? {rdata11[28:0] ,3'b0}
                    :(inst_lsa & inst[7:6]==2'b01) ? {rdata11[29:0] ,2'b0}
                    :(inst_lsa & inst[7:6]==2'b00) ? {rdata11[30:0] ,1'b0}
                    :rdata11;

    // 组合ID段传递到EX段的总线信号
    assign id_to_ex_bus = {
        data_ram_readen,//168:165
        inst_mthi,      //164
        inst_mtlo,      //163
        inst_multu,     //162
        inst_mult,      //161
        inst_divu,      //160
        inst_div,       //159
        id_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rdata111,         // 63:32
        rdata22          // 31:0
    };

    // 分支信号生成逻辑
    wire br_e;  // 分支使能信号
    wire [31:0] br_addr;  // 分支目标地址
    wire rs_eq_rt;  // rs和rt相等信号
    wire rs_ge_z;  // rs大于等于零信号
    wire rs_gt_z;  // rs大于零信号
    wire rs_le_z;  // rs小于等于零信号
    wire rs_lt_z;  // rs小于零信号
    wire [31:0] pc_plus_4;  // PC+4的值
    
    assign pc_plus_4 = id_pc + 32'h4;
    assign rs_ge_z  = (rdata11[31] == 1'b0); //大于等于0
    assign rs_gt_z  = (rdata11[31] == 1'b0 & rdata11 != 32'b0  );  //大于0
    assign rs_le_z  = (rdata11[31] == 1'b1 | rdata11 == 32'b0  );  //小于等于0
    assign rs_lt_z  = (rdata11[31] == 1'b1);  //小于0
    assign rs_eq_rt = (rdata11 == rdata22);// 判断rs和rt是否相等


    // 分支判断
    assign br_e =  inst_jalr | (inst_bgezal & rs_ge_z ) | ( inst_bltzal & rs_lt_z) | (inst_bgtz & rs_gt_z  ) | (inst_bltz & rs_lt_z) | (inst_blez & rs_le_z) | (inst_bgez & rs_ge_z ) | (inst_beq & rs_eq_rt) | inst_jr | inst_jal | (inst_bne & !rs_eq_rt) | inst_j ;
    assign br_addr = inst_beq ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :(inst_jr |inst_jalr)  ? (rdata11)  
                    : inst_jal ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    : inst_j ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    :(inst_bgezal|inst_bltzal |inst_blez | inst_bltz |inst_bgez |inst_bgtz ) ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b00})
                    :inst_bne ? (pc_plus_4 + {{14{inst[15]}},{inst[15:0],2'b00}}) : 32'b0;

    // 组合分支信号总线
    assign br_bus = {
        br_e,
        br_addr
    };

    // ID阶段产生的暂停请求信号
    assign stallreq_from_id = (ex_is_load  & ex_id_waddr == rs) | (ex_is_load & ex_id_waddr == rt) ;
    
endmodule