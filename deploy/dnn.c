/**
 * DNN Accelerator Control Program for Zynq PS
 * 使用AXI GPIO控制DNN_Wrapper
 */

#include <stdio.h>
#include <stdint.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xil_io.h"
#include "xuartps.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_cache.h"

// ==================== 调试开关 ====================
// 设置为0禁用printf（避免与UART数据通信冲突）
// 设置为1启用printf（通过JTAG UART查看调试信息）
#define DEBUG_PRINT_ENABLE 0

#if DEBUG_PRINT_ENABLE
    #define debug_printf printf
#else
    #define debug_printf(...) ((void)0)
#endif

// ==================== GPIO设备ID定义 ====================
#define GPIO_CMD_ADDR_ID    XPAR_AXI_GPIO_CMD_ADDR_DEVICE_ID
#define GPIO_CMD_WDATA_ID   XPAR_AXI_GPIO_CMD_WDATA_DEVICE_ID
#define GPIO_CMD_RDATA_ID   XPAR_AXI_GPIO_CMD_RDATA_DEVICE_ID
#define GPIO_CONTROL_ID     XPAR_AXI_GPIO_CONTROL_DEVICE_ID
#define GPIO_INTR_ID        XPAR_AXI_GPIO_INTR_DEVICE_ID

// ====================UART协议定义 ====================
#define CMD_CONFIG   0x01
#define CMD_WEIGHT   0x02
#define CMD_IFM      0x03
#define CMD_START    0x04
#define CMD_READ_OFM 0x05

#define UART_DEVICE_ID  XPAR_XUARTPS_0_DEVICE_ID
#define INTC_DEVICE_ID  XPAR_SCUGIC_0_DEVICE_ID

// ==================== DNN配置结构 ====================
typedef struct {
    uint32_t ifm_h;
    uint32_t ifm_w;
    uint32_t ofm_h;
    uint32_t ofm_w;
    uint32_t ic;
    uint32_t oc;
    uint32_t kh;
    uint32_t kw;
    uint32_t stride;
    uint32_t pad;
    uint32_t relu_en;
    uint32_t quant_shift;
    uint32_t is_max_pool;
} dnn_config_t;

// ==================== 全局变量 ====================
static XUartPs uart_inst;
static XScuGic intc_inst;

// GPIO实例
static XGpio gpio_cmd_addr;
static XGpio gpio_cmd_wdata;
static XGpio gpio_cmd_rdata;
static XGpio gpio_control;
static XGpio gpio_intr;

// ==================== GPIO初始化 ====================
int gpio_init(void) {
    int status;
    
    // 初始化5个GPIO
    
    status = XGpio_Initialize(&gpio_cmd_addr, GPIO_CMD_ADDR_ID);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] gpio_cmd_addr init failed\n");
        return XST_FAILURE;
    }
    
    status = XGpio_Initialize(&gpio_cmd_wdata, GPIO_CMD_WDATA_ID);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] gpio_cmd_wdata init failed\n");
        return XST_FAILURE;
    }
    
    status = XGpio_Initialize(&gpio_cmd_rdata, GPIO_CMD_RDATA_ID);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] gpio_cmd_rdata init failed\n");
        return XST_FAILURE;
    }
    
    status = XGpio_Initialize(&gpio_control, GPIO_CONTROL_ID);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] gpio_control init failed\n");
        return XST_FAILURE;
    }
    
    status = XGpio_Initialize(&gpio_intr, GPIO_INTR_ID);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] gpio_intr init failed\n");
        return XST_FAILURE;
    }
    
    // 设置方向
    XGpio_SetDataDirection(&gpio_cmd_addr, 1, 0x0);   // 输出
    XGpio_SetDataDirection(&gpio_cmd_wdata, 1, 0x0);  // 输出
    XGpio_SetDataDirection(&gpio_cmd_rdata, 1, 0xFFFFFFFF); // 输入
    XGpio_SetDataDirection(&gpio_control, 1, 0x0);    // 输出
    XGpio_SetDataDirection(&gpio_intr, 1, 0xFFFFFFFF);// 输入
    
    // 初始化控制信号为0
    XGpio_DiscreteWrite(&gpio_control, 1, 0x0);
    
    debug_printf("[OK] All GPIOs initialized\n");
    return XST_SUCCESS;
}

// ==================== GPIO读写函数 ====================
static inline void gpio_write_addr(uint32_t value) {
    XGpio_DiscreteWrite(&gpio_cmd_addr, 1, value);
}

static inline void gpio_write_wdata(uint32_t value) {
    XGpio_DiscreteWrite(&gpio_cmd_wdata, 1, value);
}

static inline uint32_t gpio_read_rdata(void) {
    return XGpio_DiscreteRead(&gpio_cmd_rdata, 1);
}

static inline void gpio_write_control(uint32_t value) {
    XGpio_DiscreteWrite(&gpio_control, 1, value);
}

static inline uint32_t gpio_read_intr(void) {
    return XGpio_DiscreteRead(&gpio_intr, 1);
}

// ==================== DNN_Wrapper控制接口 ====================

/**
 * 写DNN_Wrapper的CSR寄存器
 * @param addr 寄存器地址（32位）
 * @param data 写入数据（32位）
 */
void dnn_write_csr(uint32_t addr, uint32_t data) {
    // 1. 写地址到cmd_addr
    gpio_write_addr(addr);
    
    // 2. 写数据到cmd_wdata
    gpio_write_wdata(data);
    
    // 3. 给FPGA时间稳定信号（大幅增加到10us）
    usleep(10);
    
    // 4. 拉高cmd_we (control[0] = 1)
    gpio_write_control(0x01);
    
    // 5. 保持cmd_we足够长时间让FPGA采样（增加到10us）
    usleep(10);
    
    // 6. 拉低cmd_we
    gpio_write_control(0x00);
    
    // 7. 给FPGA时间完成BRAM写操作（增加到10us）
    usleep(10);
}

/**
 * 读DNN_Wrapper的CSR寄存器
 * @param addr 寄存器地址（32位）
 * @return 读取的数据（32位）
 */
uint32_t dnn_read_csr(uint32_t addr) {
    // 1. 写地址到cmd_addr
    gpio_write_addr(addr);
    
    // 2. 给FPGA时间稳定地址
    usleep(1);
    
    // 3. 拉高cmd_re (control[1] = 1)
    gpio_write_control(0x02);
    
    // 4. 等待数据稳定
    usleep(1);
    
    // 5. 读取cmd_rdata
    uint32_t data = gpio_read_rdata();
    
    // 6. 拉低cmd_re
    gpio_write_control(0x00);
    
    return data;
}

/**
 * 写IFM Buffer
 * @param addr 地址（字地址）
 * @param data 数据（32位）
 */
void dnn_write_ifm(uint32_t addr, uint32_t data) {
    dnn_write_csr(0x100000 + (addr << 2), data);  // IFM: cmd_addr[31:20]=0x001
}

/**
 * 写Weight Buffer
 * @param addr 地址（字地址）
 * @param data 数据（32位）
 */
void dnn_write_wgt(uint32_t addr, uint32_t data) {
    dnn_write_csr(0x200000 + (addr << 2), data);  // Weight: cmd_addr[31:20]=0x002
}

/**
 * 读OFM Buffer
 * @param addr 地址（字地址）
 * @return 数据（32位）
 */
uint32_t dnn_read_ofm(uint32_t addr) {
    return dnn_read_csr(0x300000 + (addr << 2));  // OFM: cmd_addr[31:20]=0x003
}

/**
 * 启动DNN计算
 */
void dnn_start(void) {
    // 先读取状态，确认done/busy初始状态
    uint32_t status_before = dnn_read_csr(0x0004);
    debug_printf("[DEBUG] Status before start: 0x%08X (busy=%d, done=%d)\n", 
                 status_before, (status_before & 0x01), (status_before & 0x02) >> 1);
    
    // 持续写入start直到busy变成1（说明Controller真正启动了）
    // start_reg是单周期脉冲，可能需要重复写入才能被Controller采样到
    int retry = 0;
    uint32_t status;
    do {
        dnn_write_csr(0x0000, 1);  // CSR_START = 1
        usleep(10);  // 短延时让硬件响应
        status = dnn_read_csr(0x0004);
        retry++;
        if (retry > 100) {
            debug_printf("[ERROR] Failed to start DNN after 100 retries!\n");
            break;
        }
    } while ((status & 0x01) == 0);  // 等待busy=1
    
    debug_printf("[DEBUG] DNN started after %d retries, busy=%d, done=%d\n",
                 retry, (status & 0x01), (status & 0x02) >> 1);
}

/**
 * 检查DNN是否完成
 */
int dnn_is_done(void) {
    return (gpio_read_intr() & 0x01);
}

// ==================== UART接收函数 ====================

/**
 * UART接收指定字节数
 */
int uart_recv_bytes(uint8_t *buf, uint32_t len) {
    uint32_t received = 0;
    while (received < len) {
        received += XUartPs_Recv(&uart_inst, buf + received, len - received);
    }
    return 0;
}

/**
 * 接收并配置DNN参数
 */
int uart_recv_config(dnn_config_t *cfg) {
    debug_printf("[INFO] Receiving configuration...\n");
    
    // 接收配置数据（13个uint32_t）
    uint32_t config_buf[13];
    uart_recv_bytes((uint8_t*)config_buf, 13 * sizeof(uint32_t));
    
    // 解析配置
    cfg->ifm_h = config_buf[0];
    cfg->ifm_w = config_buf[1];
    cfg->ofm_h = config_buf[2];
    cfg->ofm_w = config_buf[3];
    cfg->ic = config_buf[4];
    cfg->oc = config_buf[5];
    cfg->kh = config_buf[6];
    cfg->kw = config_buf[7];
    cfg->stride = config_buf[8];
    cfg->pad = config_buf[9];
    cfg->relu_en = config_buf[10];
    cfg->quant_shift = config_buf[11];
    cfg->is_max_pool = config_buf[12];
    
    // 写入CSR寄存器
    dnn_write_csr(0x0010, cfg->ifm_h);
    dnn_write_csr(0x0014, cfg->ifm_w);
    dnn_write_csr(0x0018, cfg->ofm_h);
    dnn_write_csr(0x001C, cfg->ofm_w);
    dnn_write_csr(0x0020, cfg->ic);
    dnn_write_csr(0x0024, cfg->oc);
    dnn_write_csr(0x0028, cfg->kh);
    dnn_write_csr(0x002C, cfg->kw);
    dnn_write_csr(0x0030, cfg->stride);
    dnn_write_csr(0x0034, cfg->pad);
    dnn_write_csr(0x0038, cfg->relu_en);
    dnn_write_csr(0x003C, cfg->quant_shift);
    dnn_write_csr(0x0040, cfg->is_max_pool);
    
    debug_printf("[OK] Config: IFM=%dx%dx%d, OFM=%dx%dx%d, K=%dx%d\n",
           cfg->ifm_h, cfg->ifm_w, cfg->ic,
           cfg->ofm_h, cfg->ofm_w, cfg->oc,
           cfg->kh, cfg->kw);
    
    return 0;
}

/**
 * 接收并加载权重数据
 */
int uart_recv_weights(uint32_t weight_size) {
    debug_printf("[INFO] Receiving weights... (%d bytes)\n", weight_size);
    
    uint8_t buf[4];
    uint32_t addr = 0;
    uint32_t words = (weight_size + 3) / 4;
    
    for (uint32_t i = 0; i < words; i++) {
        uart_recv_bytes(buf, 4);
        uint32_t data = (buf[3] << 24) | (buf[2] << 16) | (buf[1] << 8) | buf[0];
        dnn_write_wgt(addr++, data);
        
        if (i % 1024 == 0) {
            debug_printf(".");
            fflush(stdout);
        }
    }
    
    debug_printf("\n[OK] Weights loaded (%d words)\n", words);
    return 0;
}

/**
 * 接收并加载输入特征图
 */
int uart_recv_ifm(uint32_t ifm_size) {
    debug_printf("[INFO] Receiving IFM... (%d bytes)\n", ifm_size);
    
    uint8_t buf[4];
    uint32_t addr = 0;
    uint32_t words = (ifm_size + 3) / 4;
    
    for (uint32_t i = 0; i < words; i++) {
        uart_recv_bytes(buf, 4);
        uint32_t data = (buf[3] << 24) | (buf[2] << 16) | (buf[1] << 8) | buf[0];
        dnn_write_ifm(addr++, data);
        
        if (i % 1024 == 0) {
            debug_printf(".");
            fflush(stdout);
        }
    }
    
    debug_printf("\n[OK] IFM loaded (%d words)\n", words);
    return 0;
}

/**
 * 发送OFM数据回PC
 */
int uart_send_ofm(uint32_t ofm_size) {
    debug_printf("[INFO] Sending OFM... (%d bytes)\n", ofm_size);
    
    // 先读取前几个OFM字检查是否有数据
    debug_printf("[DEBUG] First 4 OFM words: 0x%08X 0x%08X 0x%08X 0x%08X\n",
                 dnn_read_ofm(0), dnn_read_ofm(1), dnn_read_ofm(2), dnn_read_ofm(3));
    
    uint8_t buf[4];
    uint32_t addr = 0;
    uint32_t words = (ofm_size + 3) / 4;
    
    for (uint32_t i = 0; i < words; i++) {
        uint32_t data = dnn_read_ofm(addr++);
        buf[0] = (data >> 0) & 0xFF;
        buf[1] = (data >> 8) & 0xFF;
        buf[2] = (data >> 16) & 0xFF;
        buf[3] = (data >> 24) & 0xFF;
        
        // 逐字节发送
        for (int j = 0; j < 4; j++) {
            XUartPs_SendByte(XPAR_XUARTPS_0_BASEADDR, buf[j]);
        }
        
        if (i % 1024 == 0) {
            debug_printf(".");
            fflush(stdout);
        }
    }
    
    debug_printf("\n[OK] OFM sent (%d words)\n", words);
    return 0;
}

// ==================== UART初始化 ====================
int uart_init(void) {
    XUartPs_Config *uart_cfg;
    
    // 初始化UART
    uart_cfg = XUartPs_LookupConfig(UART_DEVICE_ID);
    if (uart_cfg == NULL) {
        debug_printf("[ERROR] UART config lookup failed\n");
        return XST_FAILURE;
    }
    
    int status = XUartPs_CfgInitialize(&uart_inst, uart_cfg, uart_cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        debug_printf("[ERROR] UART initialization failed\n");
        return XST_FAILURE;
    }
    
    // 设置波特率115200
    XUartPs_SetBaudRate(&uart_inst, 115200);
    
    debug_printf("[OK] UART initialized at 115200 baud\n");
    return XST_SUCCESS;
}

// ==================== 主程序 ====================
int main(void) {
    debug_printf("\n");
    debug_printf("=========================================\n");
    debug_printf("  DNN Accelerator Control Program\n");
    debug_printf("  Zynq PS + PL via AXI GPIO\n");
    debug_printf("=========================================\n\n");
    
    // 初始化GPIO
    if (gpio_init() != XST_SUCCESS) {
        debug_printf("[ERROR] GPIO initialization failed\n");
        return XST_FAILURE;
    }
    
    // 初始化UART
    if (uart_init() != XST_SUCCESS) {
        return XST_FAILURE;
    }
    
    debug_printf("[INFO] Waiting for commands from PC...\n\n");
    
    dnn_config_t config;
    uint8_t cmd;
    uint32_t size;
    
    // 主循环：等待PC命令
    while (1) {
        // 接收命令字节
        uart_recv_bytes(&cmd, 1);
        
        switch (cmd) {
            case CMD_CONFIG:
                uart_recv_config(&config);
                break;
                
            case CMD_WEIGHT:
                // 接收权重大小
                uart_recv_bytes((uint8_t*)&size, 4);
                uart_recv_weights(size);
                break;
                
            case CMD_IFM:
                // 接收IFM大小
                uart_recv_bytes((uint8_t*)&size, 4);
                uart_recv_ifm(size);
                break;
                
            case CMD_START:
                debug_printf("[INFO] Starting DNN computation...\n");
                dnn_start();
                
                // 等待计算完成（done从0变成1）
                // 注意：dnn_start()已经确保busy=1，现在等待done=1
                int timeout = 10000000;  // 10秒超时
                while (!dnn_is_done() && timeout-- > 0) {
                    // 轮询done信号
                }
                
                if (timeout <= 0) {
                    debug_printf("[ERROR] Computation timeout!\n");
                } else {
                    debug_printf("[OK] DNN computation done!\n");
                }
                
                // 发送完成响应（使用SendByte确保可靠）
                XUartPs_SendByte(XPAR_XUARTPS_0_BASEADDR, 0xAA);
                break;
                
            case CMD_READ_OFM:
                // 接收OFM大小
                uart_recv_bytes((uint8_t*)&size, 4);
                uart_send_ofm(size);
                break;
                
            default:
                debug_printf("[WARN] Unknown command: 0x%02X\n", cmd);
                break;
        }
    }
    
    return 0;
}
