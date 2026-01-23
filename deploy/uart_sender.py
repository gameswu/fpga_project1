#!/usr/bin/env python3
"""
PC端控制脚本 - 通过UART发送配置、权重和输入数据到FPGA
使用方法: python uart_sender.py --port COM3 --config layer1.json --weight weight.bin --ifm input.bin

协议格式：
  CMD_CONFIG (0x01): 发送13个uint32配置参数
  CMD_WEIGHT (0x02): 发送uint32大小 + 权重数据
  CMD_IFM (0x03):    发送uint32大小 + IFM数据
  CMD_START (0x04):  启动计算，等待0xAA响应
  CMD_READ_OFM (0x05): 发送uint32大小，接收OFM数据
"""

import serial
import struct
import json
import numpy as np
import argparse
import time

# 命令定义（与dnn.c保持一致）
CMD_CONFIG = 0x01
CMD_WEIGHT = 0x02
CMD_IFM = 0x03
CMD_START = 0x04
CMD_READ_OFM = 0x05

class FPGAController:
    def __init__(self, port, baudrate=115200):
        """初始化UART连接"""
        self.ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=10  # 增加超时时间到10秒
        )
        print(f"[INFO] Connected to {port} at {baudrate} baud")
        time.sleep(0.5)  # 等待串口稳定
    
    def send_config(self, config_file):
        """发送层配置
        config_file: JSON格式配置文件
        {
            "ifm_h": 32, "ifm_w": 32,
            "ofm_h": 32, "ofm_w": 32,
            "ic": 1, "oc": 32,
            "kh": 5, "kw": 5,
            "stride": 1, "pad": 2,
            "relu_en": 1,
            "quant_shift": 9,
            "is_max_pool": 0
        }
        
        协议：发送13个uint32_t参数（小端序）
        """
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        # 保存config供后续weight重排使用
        self._config = config
        
        print(f"[INFO] Sending configuration from: {config_file}")
        
        # 发送CMD_CONFIG命令字节
        self.ser.write(bytes([CMD_CONFIG]))
        
        # 打包13个uint32参数（小端序）
        config_data = struct.pack('<13I',
            config['ifm_h'], 
            config['ifm_w'],
            config['ofm_h'], 
            config['ofm_w'],
            config['ic'], 
            config['oc'],
            config['kh'], 
            config['kw'],
            config['stride'], 
            config['pad'],
            config['relu_en'], 
            config['quant_shift'],
            config.get('is_max_pool', 0)
        )
        
        # 发送配置数据
        self.ser.write(config_data)
        self.ser.flush()
        
        print(f"[OK] Configuration sent (13 x 4 = 52 bytes)")
        print(f"     IFM: {config['ifm_h']}x{config['ifm_w']}x{config['ic']}")
        print(f"     OFM: {config['ofm_h']}x{config['ofm_w']}x{config['oc']}")
        print(f"     Kernel: {config['kh']}x{config['kw']}, Stride: {config['stride']}, Pad: {config['pad']}")
        time.sleep(0.1)
    
    def send_weights(self, weight_file):
        """发送权重数据
        weight_file: 二进制格式，int8类型
        
        协议：CMD_WEIGHT + uint32大小 + 数据
        
        重要：硬件Weight BRAM布局考虑
        Controller每个kernel point读取32行，每行128-bit
        对于IC<32的情况，需要填充0到32行
        """
        print(f"[INFO] Loading weights from: {weight_file}")
        weights_raw = np.fromfile(weight_file, dtype=np.int8)
        
        # 从JSON config中获取OC, IC, KH, KW
        if not hasattr(self, '_config'):
            raise Exception("Must call send_config() before send_weights() to get layer dimensions")
        
        oc = self._config['oc']
        ic = self._config['ic']
        kh = self._config['kh']
        kw = self._config['kw']
        kernel_size = kh * kw
        expected_size = oc * ic * kernel_size
        
        if len(weights_raw) != expected_size:
            raise Exception(f"Weight size mismatch: expected {expected_size}, got {len(weights_raw)}")
        
        print(f"[INFO] Reshaping weights: OC={oc}, IC={ic}, KH={kh}, KW={kw}")
        
        # Reshape: [OC, IC, KH, KW]
        weights = weights_raw.reshape(oc, ic, kh, kw)
        
        # Hardware expects: For each (tile_oc, ic, ky, kw), all OCs in that tile
        # Layout: [tile_oc][IC][KY][KW][32 rows × 16 bytes]
        
        # Transpose to [IC, KH, KW, OC]
        weights_transposed = weights.transpose(1, 2, 3, 0)
        
        # Now expand to PE_ROWS rows per kernel point, organized by tile
        PE_ROWS = 32
        PE_COLS = 16
        num_tile_oc = (oc + PE_COLS - 1) // PE_COLS
        
        weights_expanded = []
        
        # Loop order: tile_oc, ic, ky, kw (matching Controller's wgt_addr_base increment)
        for tile_oc in range(num_tile_oc):
            for ic_idx in range(ic):
                for ky_idx in range(kh):
                    for kw_idx in range(kw):
                        # This kernel point's data for OCs in this tile
                        oc_start = tile_oc * PE_COLS
                        oc_end = min(oc_start + PE_COLS, oc)
                        num_ocs_in_tile = oc_end - oc_start
                        
                        kernel_weights = weights_transposed[ic_idx, ky_idx, kw_idx, oc_start:oc_end]
                        
                        # Create block: 32 rows × 16 bytes = 512 bytes
                        block_data = np.zeros(PE_ROWS * PE_COLS, dtype=np.int8)
                        
                        # Fill row ic_idx with actual weights for this tile's OCs
                        row_start = ic_idx * PE_COLS
                        block_data[row_start:row_start+num_ocs_in_tile] = kernel_weights
                        
                        weights_expanded.append(block_data)
        
        weights_reordered = np.concatenate(weights_expanded)
        
        print(f"[INFO] Weight layout after expansion:")
        print(f"     Tiles: {num_tile_oc}, Kernel points per tile: {ic * kh * kw}")
        print(f"     Total bytes: {len(weights_reordered)} (original: {expected_size})")
        print(f"     Expected: {num_tile_oc * ic * kh * kw * PE_ROWS * PE_COLS} bytes")
        
        # Debug: Print first kernel point (first 16 bytes of row 0)
        print(f"[DEBUG] First kernel point, row 0, first 16 bytes:")
        first_block = weights_expanded[0]
        print(f"        {' '.join([f'{int(x) & 0xFF:02X}' for x in first_block[:16]])}")
        
        print(f"[INFO] Sending {len(weights_reordered)} bytes of weights...")
        
        # 发送命令字节
        self.ser.write(bytes([CMD_WEIGHT]))
        
        # 发送数据大小（uint32，小端序）
        self.ser.write(struct.pack('<I', len(weights_reordered)))
        
        # 分块发送权重 (每次1024字节)
        chunk_size = 1024
        bytes_sent = 0
        for i in range(0, len(weights_reordered), chunk_size):
            chunk = weights_reordered[i:i+chunk_size]
            self.ser.write(chunk.tobytes())
            bytes_sent += len(chunk)
            
            if (i // chunk_size) % 100 == 0:
                print(f"  Progress: {bytes_sent}/{len(weights_reordered)} bytes ({100*bytes_sent//len(weights_reordered)}%)")
        
        self.ser.flush()
        print(f"[OK] Weight transfer complete ({len(weights_reordered)} bytes)")
        time.sleep(0.2)
    
    def send_ifm(self, ifm_file):
        """发送输入特征图
        ifm_file: 二进制格式，int8类型
        
        协议：CMD_IFM + uint32大小 + 数据
        
        重要：硬件IFM BRAM布局考虑
        - Port B读取256-bit (32 channels)
        - 对于IC<32的情况，每个像素需要扩展到32字节
        - IC=1时，每个像素占用8个32-bit words (第一个word的第一个字节)
        """
        print(f"[INFO] Loading IFM from: {ifm_file}")
        ifm = np.fromfile(ifm_file, dtype=np.int8)
        
        # 从config获取IC
        if not hasattr(self, '_config'):
            raise Exception("Must call send_config() before send_ifm()")
        
        ic = self._config['ic']
        ifm_h = self._config['ifm_h']
        ifm_w = self._config['ifm_w']
        
        # 扩展IFM数据：每个像素需要占用32字节 (8个32-bit words)
        # 对于IC=1，只有第一个字节有数据
        ifm_expanded = []
        for pixel_val in ifm:
            # 每个像素扩展到32字节（8个words）
            # 第一个word的第一个字节 = pixel_val，其他31字节 = 0
            pixel_block = np.zeros(32, dtype=np.uint8)
            pixel_block[0] = int(pixel_val) & 0xFF  # 转换为Python int再做位运算
            ifm_expanded.append(pixel_block)
        
        ifm_expanded = np.concatenate(ifm_expanded)
        
        print(f"[INFO] IFM layout after expansion:")
        print(f"     Original: {len(ifm)} pixels")
        print(f"     Expanded: {len(ifm_expanded)} bytes ({len(ifm)} pixels × 32 bytes/pixel)")
        print(f"[DEBUG] First pixel: value={ifm[0]}, expanded block[0]={ifm_expanded[0]}")
        
        print(f"[INFO] Sending {len(ifm_expanded)} bytes of IFM...")
        
        # 发送命令字节
        self.ser.write(bytes([CMD_IFM]))
        
        # 发送数据大小（uint32，小端序）
        self.ser.write(struct.pack('<I', len(ifm_expanded)))
        
        # 分块发送
        chunk_size = 1024
        bytes_sent = 0
        for i in range(0, len(ifm_expanded), chunk_size):
            chunk = ifm_expanded[i:i+chunk_size]
            self.ser.write(chunk.tobytes())
            bytes_sent += len(chunk)
            
            if (i // chunk_size) % 100 == 0:
                print(f"  Progress: {bytes_sent}/{len(ifm_expanded)} bytes ({100*bytes_sent//len(ifm_expanded)}%)")
        
        self.ser.flush()
        print(f"[OK] IFM transfer complete ({len(ifm_expanded)} bytes)")
        time.sleep(0.2)
    
    def start_computation(self):
        """启动计算
        
        协议：发送CMD_START，等待0xAA响应
        """
        print("[INFO] Starting DNN computation...")
        self.ser.write(bytes([CMD_START]))
        self.ser.flush()
        
        # 等待计算完成响应（0xAA）
        start_time = time.time()
        response = self.ser.read(1)
        elapsed = time.time() - start_time
        
        if len(response) != 1:
            raise Exception("No response from FPGA (timeout)")
        
        if response[0] != 0xAA:
            raise Exception(f"Invalid completion response: 0x{response[0]:02X}")
        
        print(f"[OK] Computation completed! (took {elapsed:.2f} seconds)")
    
    def read_ofm(self, ofm_size, output_file):
        """接收输出特征图
        
        协议：发送CMD_READ_OFM + uint32大小，接收数据
        
        Args:
            ofm_size: OFM字节数
            output_file: 保存路径
        """
        print(f"[INFO] Requesting {ofm_size} bytes of OFM...")
        
        # 发送命令
        self.ser.write(bytes([CMD_READ_OFM]))
        
        # 发送OFM大小
        self.ser.write(struct.pack('<I', ofm_size))
        self.ser.flush()
        
        # 接收数据
        ofm_data = bytearray()
        chunk_size = 1024
        
        while len(ofm_data) < ofm_size:
            remaining = ofm_size - len(ofm_data)
            chunk = self.ser.read(min(chunk_size, remaining))
            
            if len(chunk) == 0:
                raise Exception("OFM data timeout")
            
            ofm_data.extend(chunk)
            
            if len(ofm_data) % (100 * chunk_size) == 0:
                print(f"  Progress: {len(ofm_data)}/{ofm_size} bytes ({100*len(ofm_data)//ofm_size}%)")
        
        # 保存为numpy数组（int32格式）
        ofm_array = np.frombuffer(ofm_data, dtype=np.int32)
        ofm_array.tofile(output_file)
        
        print(f"[OK] OFM saved to: {output_file}")
        print(f"     Shape: {ofm_array.shape}, Range: [{ofm_array.min()}, {ofm_array.max()}]")
        
        return ofm_array
    
    def close(self):
        """关闭串口"""
        self.ser.close()


def main():
    parser = argparse.ArgumentParser(
        description='FPGA DNN Accelerator UART Controller',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python uart_sender.py --port COM3 --config config.json --weight weight.bin --ifm input.bin
  python uart_sender.py --port /dev/ttyUSB0 --config layer1.json --weight conv1.dat --ifm ifm.bin --read-ofm
        """
    )
    parser.add_argument('--port', required=True, help='UART port (e.g., COM3 or /dev/ttyUSB0)')
    parser.add_argument('--config', required=True, help='Layer configuration JSON file')
    parser.add_argument('--weight', required=True, help='Weight binary file (int8)')
    parser.add_argument('--ifm', required=True, help='Input feature map binary file (int8)')
    parser.add_argument('--output', default='output_ofm.bin', help='Output file for OFM (default: output_ofm.bin)')
    parser.add_argument('--baudrate', type=int, default=115200, help='UART baudrate (default: 115200)')
    parser.add_argument('--read-ofm', action='store_true', help='Read OFM after computation')
    parser.add_argument('--ofm-size', type=int, help='OFM size in bytes (auto-calculated if not specified)')
    
    args = parser.parse_args()
    
    print("\n" + "="*60)
    print("  FPGA DNN Accelerator - UART Controller")
    print("="*60 + "\n")
    
    try:
        # 创建控制器
        ctrl = FPGAController(args.port, args.baudrate)
        
        # Step 1: 发送配置
        print("\n[Step 1/4] Sending Configuration...")
        ctrl.send_config(args.config)
        
        # Step 2: 发送权重
        print("\n[Step 2/4] Sending Weights...")
        ctrl.send_weights(args.weight)
        
        # Step 3: 发送输入特征图
        print("\n[Step 3/4] Sending Input Feature Map...")
        ctrl.send_ifm(args.ifm)
        
        # Step 4: 启动计算
        print("\n[Step 4/4] Starting Computation...")
        ctrl.start_computation()
        
        # Step 5 (可选): 读取输出
        if args.read_ofm:
            print("\n[Optional] Reading Output Feature Map...")
            
            # 计算OFM大小（如果没有指定）
            if args.ofm_size is None:
                with open(args.config, 'r') as f:
                    config = json.load(f)
                # OFM大小 = H * W * C * 4字节（int32）
                ofm_size = config['ofm_h'] * config['ofm_w'] * config['oc'] * 4
                print(f"[INFO] Auto-calculated OFM size: {ofm_size} bytes")
            else:
                ofm_size = args.ofm_size
            
            ctrl.read_ofm(ofm_size, args.output)
        
        print("\n" + "="*60)
        print("  ✓ ALL OPERATIONS COMPLETED SUCCESSFULLY")
        print("="*60 + "\n")
        
        ctrl.close()
        
    except FileNotFoundError as e:
        print(f"\n[ERROR] File not found: {e}")
        return -1
    except serial.SerialException as e:
        print(f"\n[ERROR] Serial port error: {e}")
        return -1
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        return -1
    
    return 0


if __name__ == '__main__':
    exit(main())
