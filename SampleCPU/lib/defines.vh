`define IF_TO_ID_WD 33
`define ID_TO_EX_WD 159
`define EX_TO_MEM_WD 76
`define MEM_TO_WB_WD 70
`define BR_WD 33            // 分支预测信号宽度为 33 位
`define DATA_SRAM_WD 69     // 数据 SRAM（静态随机存取存储器）的信号总线宽度为 69 位
`define WB_TO_RF_WD 38      // WB 阶段到寄存器文件（Register File）的信号总线宽度为 38 位

// 流水线暂停控制宏
`define StallBus 6          // 用于暂停流水线的信号总线宽度为 6 位
`define NoStop 1'b0         // 表示流水线正常运行（没有暂停）
`define Stop 1'b1           // 表示流水线暂停（Stop 信号激活）

// 默认值宏
`define ZeroWord 32'b0      // 一个 32 位的全零值，用于初始化寄存器或表示默认值


//除法div
`define DivFree 2'b00
`define DivByZero 2'b01
`define DivOn 2'b10
`define DivEnd 2'b11
`define DivResultReady 1'b1
`define DivResultNotReady 1'b0
`define DivStart 1'b1
`define DivStop 1'b0