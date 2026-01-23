#!/usr/bin/env python3
"""
验证FPGA输出与Golden Reference的一致性
"""

import numpy as np
import sys

def verify_output(fpga_file, golden_file):
    """比较FPGA输出和Golden Reference"""
    
    print("="*60)
    print("  FPGA Output Verification")
    print("="*60)
    
    # 读取FPGA输出
    try:
        ofm_fpga_raw_full = np.fromfile(fpga_file, dtype=np.int32)
        print(f"\n[OK] FPGA output loaded: {fpga_file}")
        print(f"     Total elements: {ofm_fpga_raw_full.size}")
        
        # FPGA输出有32个元素的偏移（1个像素），需要跳过前32个并补0到末尾
        ofm_fpga_raw = np.zeros(32768, dtype=np.int32)
        ofm_fpga_raw[:32736] = ofm_fpga_raw_full[32:]
        print(f"[OK] Adjusted for 32-element offset (skipped first 32, padded end)")
        
        # FPGA输出是tile-interleaved格式，需要de-interleave
        # Controller写入地址: (y*W+x)*num_tiles + tile
        # 每个tile包含16个int32 (512-bit BRAM)
        # For Layer1: H=32, W=32, OC=32, num_tiles=2
        H, W, OC = 32, 32, 32
        num_tiles = (OC + 15) // 16
        channels_per_tile = 16
        
        # De-interleave: 从tile格式转换为HWC格式
        ofm_fpga = np.zeros(H * W * OC, dtype=np.int32)
        for y in range(H):
            for x in range(W):
                for tile in range(num_tiles):
                    # FPGA中该tile的起始位置（512-bit word地址）
                    addr_512 = (y * W + x) * num_tiles + tile
                    # 转换为32-bit word地址（每个512-bit = 16个int32）
                    addr_32_start = addr_512 * 16
                    
                    # 该tile的通道数
                    num_ch = min(channels_per_tile, OC - tile * channels_per_tile)
                    
                    # 从FPGA raw数据读取
                    fpga_tile_data = ofm_fpga_raw[addr_32_start : addr_32_start + num_ch]
                    
                    # 写入到HWC格式的正确位置
                    hwc_idx_start = (y * W + x) * OC + tile * channels_per_tile
                    ofm_fpga[hwc_idx_start : hwc_idx_start + num_ch] = fpga_tile_data
        
        print(f"[OK] De-interleaved from tile format to HWC format")
        
    except FileNotFoundError:
        print(f"\n[ERROR] FPGA output file not found: {fpga_file}")
        return False
    
    # 读取Golden Reference (注意：simulator输出是int8格式，CHW顺序)
    try:
        ofm_golden_raw = np.fromfile(golden_file, dtype=np.int8)
        # Golden是CHW格式 (Channel, Height, Width): 32 channels × 32×32
        # 需要转换为HWC格式 (Height, Width, Channel) 来匹配FPGA输出
        ofm_golden_chw = ofm_golden_raw.reshape(32, 32, 32)  # [C, H, W]
        ofm_golden_hwc = ofm_golden_chw.transpose(1, 2, 0)   # [H, W, C]
        ofm_golden = ofm_golden_hwc.flatten().astype(np.int32)
        
        print(f"[OK] Golden reference loaded: {golden_file}")
        print(f"     Total elements: {ofm_golden.size}")
        print(f"     Format: int8 (CHW) -> int32 (HWC)")
    except FileNotFoundError:
        print(f"\n[ERROR] Golden reference file not found: {golden_file}")
        return False
    
    # 检查大小是否一致
    if ofm_fpga.size != ofm_golden.size:
        print(f"\n[ERROR] Size mismatch!")
        print(f"     FPGA: {ofm_fpga.size} elements")
        print(f"     Golden: {ofm_golden.size} elements")
        return False
    
    # 统计信息
    print("\n" + "-"*60)
    print("Statistical Analysis:")
    print("-"*60)
    print(f"FPGA Output:")
    print(f"  Range: [{ofm_fpga.min()}, {ofm_fpga.max()}]")
    print(f"  Mean: {ofm_fpga.mean():.2f}")
    print(f"  Std: {ofm_fpga.std():.2f}")
    print(f"  Non-zero: {np.count_nonzero(ofm_fpga)}/{ofm_fpga.size}")
    
    print(f"\nGolden Reference:")
    print(f"  Range: [{ofm_golden.min()}, {ofm_golden.max()}]")
    print(f"  Mean: {ofm_golden.mean():.2f}")
    print(f"  Std: {ofm_golden.std():.2f}")
    print(f"  Non-zero: {np.count_nonzero(ofm_golden)}/{ofm_golden.size}")
    
    # 比较结果
    print("\n" + "-"*60)
    print("Comparison Results:")
    print("-"*60)
    
    if np.array_equal(ofm_fpga, ofm_golden):
        print("✓ PERFECT MATCH! FPGA output is identical to golden reference!")
        print("\n" + "="*60)
        print("  VERIFICATION PASSED")
        print("="*60 + "\n")
        return True
    
    # 计算差异
    diff = np.abs(ofm_fpga - ofm_golden)
    mismatch_count = np.sum(ofm_fpga != ofm_golden)
    mismatch_percentage = 100.0 * mismatch_count / ofm_fpga.size
    
    print(f"✗ Mismatch detected!")
    print(f"  Total mismatches: {mismatch_count}/{ofm_fpga.size} ({mismatch_percentage:.2f}%)")
    print(f"  Max difference: {diff.max()}")
    print(f"  Mean difference: {diff.mean():.4f}")
    print(f"  Std difference: {diff.std():.4f}")
    
    # 显示前10个不匹配的位置
    mismatch_indices = np.argwhere(ofm_fpga != ofm_golden)
    print(f"\nFirst 10 mismatches:")
    for i, idx in enumerate(mismatch_indices[:10]):
        pos = idx[0]
        fpga_val = ofm_fpga[pos]
        golden_val = ofm_golden[pos]
        diff_val = fpga_val - golden_val
        print(f"  [{i+1}] Position {pos}: FPGA={fpga_val}, Golden={golden_val}, Diff={diff_val}")
    
    print("\n" + "="*60)
    print("  VERIFICATION FAILED")
    print("="*60 + "\n")
    return False

if __name__ == '__main__':
    fpga_output = 'output_ofm.bin'
    golden_reference = '../simulator/data/im1/conv1.output.dat'
    
    # 允许命令行参数覆盖
    if len(sys.argv) > 1:
        fpga_output = sys.argv[1]
    if len(sys.argv) > 2:
        golden_reference = sys.argv[2]
    
    success = verify_output(fpga_output, golden_reference)
    sys.exit(0 if success else 1)
