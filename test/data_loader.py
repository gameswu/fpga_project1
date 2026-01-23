#!/usr/bin/env python3
"""
Data loader for Layer 1 (conv1) testbench
Reads input features and weights from simulator/data directory
"""

import numpy as np
import os

def load_conv1_input(data_path="d:/_verilog/fpga_project1/simulator/data/im1/conv1.input.dat"):
    """Load conv1 input feature map (32x32x1)"""
    data = np.fromfile(data_path, dtype=np.uint8)
    # Reshape to 32x32x1 (H x W x C)
    if len(data) == 1024:
        ifm = data.reshape(32, 32, 1)
        return ifm
    else:
        raise ValueError(f"Expected 1024 bytes for conv1 input, got {len(data)}")

def load_conv1_weights(data_path="d:/_verilog/fpga_project1/simulator/data/parameters/conv1.dat"):
    """
    Load conv1 weights
    Conv1: 1 input channel, 32 output channels, 5x5 kernel
    Total: 1 * 32 * 5 * 5 = 800 bytes
    Format: signed int8
    """
    data = np.fromfile(data_path, dtype=np.int8)
    if len(data) == 800:
        # Reshape to (OC=32, IC=1, KH=5, KW=5)
        weights = data.reshape(32, 1, 5, 5)
        return weights
    else:
        raise ValueError(f"Expected 800 bytes for conv1 weights, got {len(data)}")

def load_conv1_output(data_path="d:/_verilog/fpga_project1/simulator/data/im1/conv1.output.dat"):
    """
    Load conv1 output feature map (32x32x32)
    Format: CHW (Channel-first) order
    """
    data = np.fromfile(data_path, dtype=np.uint8)
    # Data is stored in CHW order: 32 channels, each 32x32
    if len(data) == 32768:
        # Reshape as (OC, H, W) then transpose to (H, W, OC)
        ofm = data.reshape(32, 32, 32).transpose(1, 2, 0)
        return ofm
    else:
        raise ValueError(f"Expected 32768 bytes for conv1 output, got {len(data)}")

def generate_ifm_init_sv(ifm, output_file="ifm_init.sv"):
    """Generate SystemVerilog code to initialize IFM buffer"""
    with open(output_file, 'w') as f:
        f.write("// IFM Initialization Code\n")
        f.write("// Input Feature Map: 32x32x1\n")
        f.write("// Each pixel stored in 256-bit word (32 bytes SIMD layout)\n")
        f.write("// BRAM is 32-bit write width, word_idx = pixel_idx * 8\n\n")
        
        for h in range(32):
            for w in range(32):
                pixel_val = ifm[h, w, 0]
                pixel_idx = h * 32 + w
                word_idx = pixel_idx * 8
                # Pack into 32-bit value (4 copies of the same byte)
                val_32bit = (pixel_val << 24) | (pixel_val << 16) | (pixel_val << 8) | pixel_val
                f.write(f"        u_tb_common.write_ifm_word({word_idx}, 32'h{val_32bit:08x}); // Pixel [{h},{w}] = {pixel_val}\n")
                # Also update reference array
                f.write(f"        ifm_data[{h}][{w}] = {pixel_val};\n")

def generate_wgt_init_sv(weights, output_file="wgt_init.sv"):
    """
    Generate SystemVerilog code to initialize weight buffer
    
    Weight layout in controller:
    Loop Tile_OC (0..1 for 32 output channels)
      Loop Tile_IC (0 for 1 input channel)
        Loop KY (0..4)
          Loop KW (0..4)
            Block of 32 rows × 4 words/row = 128 words (32-bit)
            For IC=1, only row 0 is used
    
    Total blocks: 2 (tile_oc) * 1 (tile_ic) * 5 (ky) * 5 (kw) = 50 blocks
    """
    OC = 32
    IC = 1
    KH = 5
    KW = 5
    PE_ROWS = 32
    PE_COLS = 16
    
    with open(output_file, 'w') as f:
        f.write("// Weight Initialization Code\n")
        f.write("// Weights: OC=32, IC=1, KH=5, KW=5\n")
        f.write("// Layout: [Tile_OC][Tile_IC][KY][KW][PE_ROWS][4 words]\n\n")
        
        # First, zero out all weight memory
        total_blocks = ((OC + PE_COLS - 1) // PE_COLS) * ((IC + PE_ROWS - 1) // PE_ROWS) * KH * KW
        total_words = total_blocks * PE_ROWS * 4
        f.write(f"        // Zero out all weight memory ({total_words} words)\n")
        f.write(f"        for (k = 0; k < {total_words}; k = k + 1) begin\n")
        f.write("            u_tb_common.write_wgt_word(k, 32'h00000000);\n")
        f.write("        end\n\n")
        
        # Now write actual weights
        f.write("        // Write actual weights (only row 0 of each block for IC=1)\n")
        num_tile_oc = (OC + PE_COLS - 1) // PE_COLS  # = 2
        num_tile_ic = (IC + PE_ROWS - 1) // PE_ROWS  # = 1
        
        block_idx = 0
        for tile_oc in range(num_tile_oc):
            for tile_ic in range(num_tile_ic):
                for ky in range(KH):
                    for kw in range(KW):
                        base_addr = block_idx * 128  # Each block = 128 words
                        
                        f.write(f"        // Block {block_idx}: tile_oc={tile_oc}, ky={ky}, kw={kw}\n")
                        
                        # For IC=1, only write row 0 (pe_row=0, ic_idx=0)
                        # Row 0 has 4 words, each word contains 4 OC channels (packed)
                        for word_idx in range(4):
                            # Each word contains 4 consecutive output channels
                            word_data = 0
                            for byte_pos in range(4):
                                oc_idx = tile_oc * PE_COLS + word_idx * 4 + byte_pos
                                if oc_idx < OC:
                                    weight_val = int(weights[oc_idx, 0, ky, kw])
                                    # Convert signed int8 to unsigned for Verilog
                                    if weight_val < 0:
                                        weight_val = weight_val + 256
                                    word_data |= (weight_val << (byte_pos * 8))
                            
                            word_addr = base_addr + word_idx
                            f.write(f"        u_tb_common.write_wgt_word({word_addr}, 32'h{word_data:08x}); ")
                            
                            # Add comments showing which OCs are in this word
                            ocs_in_word = []
                            for byte_pos in range(4):
                                oc_idx = tile_oc * PE_COLS + word_idx * 4 + byte_pos
                                if oc_idx < OC:
                                    ocs_in_word.append(f"OC{oc_idx}={int(weights[oc_idx, 0, ky, kw])}")
                            f.write(f"// K[{ky},{kw}]: {', '.join(ocs_in_word)}\n")
                        
                        block_idx += 1

def generate_kernel_array_sv(weights, oc_idx=0, output_file="kernel_array.sv"):
    """Generate kernel array for expected output calculation (for one output channel)"""
    with open(output_file, 'w') as f:
        f.write(f"// Kernel values for output channel {oc_idx}\n")
        for ky in range(5):
            for kw in range(5):
                weight_val = int(weights[oc_idx, 0, ky, kw])
                f.write(f"        kernel[{ky}][{kw}] = {weight_val}; ")
            f.write(f"\n")

def generate_ofm_expected_sv(ofm, oc_idx=0, output_file="ofm_expected.sv"):
    """Generate expected OFM values for verification (for one output channel)"""
    with open(output_file, 'w') as f:
        f.write(f"// Expected OFM values for output channel {oc_idx}\n")
        f.write(f"// Loaded from conv1.output.dat\n\n")
        
        for h in range(32):
            for w in range(32):
                expected_val = int(ofm[h, w, oc_idx])
                f.write(f"        expected_ofm[{h}][{w}] = {expected_val};\n")

if __name__ == "__main__":
    # Load data
    print("Loading conv1 input...")
    ifm = load_conv1_input()
    print(f"IFM shape: {ifm.shape}")
    print(f"IFM min: {ifm.min()}, max: {ifm.max()}, mean: {ifm.mean():.2f}")
    
    print("\nLoading conv1 weights...")
    weights = load_conv1_weights()
    print(f"Weights shape: {weights.shape}")
    print(f"Weights min: {weights.min()}, max: {weights.max()}, mean: {weights.mean():.2f}")
    
    print("\nLoading conv1 output (expected)...")
    ofm = load_conv1_output()
    print(f"OFM shape: {ofm.shape}")
    print(f"OFM min: {ofm.min()}, max: {ofm.max()}, mean: {ofm.mean():.2f}")
    print(f"OFM non-zero: {np.count_nonzero(ofm)}")
    
    # Generate SystemVerilog initialization code
    print("\nGenerating IFM initialization code...")
    generate_ifm_init_sv(ifm, "test/ifm_init.sv")
    
    print("Generating weight initialization code...")
    generate_wgt_init_sv(weights, "test/wgt_init.sv")
    
    print("Generating kernel array for verification...")
    generate_kernel_array_sv(weights, 0, "test/kernel_array.sv")
    
    print("Generating expected OFM values...")
    generate_ofm_expected_sv(ofm, 0, "test/ofm_expected.sv")
    
    print("\nDone! Generated files:")
    print("  - test/ifm_init.sv")
    print("  - test/wgt_init.sv")
    print("  - test/kernel_array.sv")
    print("  - test/ofm_expected.sv")
