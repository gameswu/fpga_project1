# =========================================================================
# Makefile for FPGA Project - PE Array & Controller
# =========================================================================
# Description:
#   Automates compilation and simulation of Verilog modules using Icarus Verilog
#   Supports individual module testing and full system simulation
#
# Usage:
#   make mac           - Compile and run MAC unit test
#   make pe_array      - Compile and run PE Array test
#   make pe_controller - Compile and run PE Controller test
#   make all           - Run all tests
#   make clean         - Remove all generated files
#   make view_mac      - View MAC waveform with GTKWave
#   make view_array    - View PE Array waveform with GTKWave
#   make view_ctrl     - View PE Controller waveform with GTKWave
#
# =========================================================================

# =========================================================================
# Tool Configuration
# =========================================================================
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# Compiler flags
IVFLAGS  = -g2012 -Wall -Winfloop
VVPFLAGS = 

# =========================================================================
# Directory Structure
# =========================================================================
SRC_DIR        = .
MAC_DIR        = $(SRC_DIR)/MAC
ARRAY_DIR      = $(SRC_DIR)/Array
CONTROLLER_DIR = $(SRC_DIR)/Controller
CONFIG_DIR     = $(SRC_DIR)/Config
BUFFER_DIR     = $(SRC_DIR)/Buffer
PPU_DIR        = $(SRC_DIR)/PPU

BUILD_DIR      = build
WAVE_DIR       = waves

# =========================================================================
# Source Files
# =========================================================================
# MAC Unit
MAC_SRC    = $(MAC_DIR)/mac.v
MAC_TB     = $(MAC_DIR)/mac_tb.v

# PE Array
ARRAY_SRC  = $(ARRAY_DIR)/pe_array.v
ARRAY_TB   = $(ARRAY_DIR)/pe_array_tb.v

# PE Controller
CTRL_SRC   = $(CONTROLLER_DIR)/pe_controller.v
CTRL_TB    = $(CONTROLLER_DIR)/pe_controller_tb.v

# Convolution Testbench
CONV_TB    = $(SRC_DIR)/tb_conv_16x16.v
SYSTEM_TB  = $(SRC_DIR)/tb_pe_top.v

# Other modules
CONFIG_SRC = $(CONFIG_DIR)/config_regs.v
BUFFER_SRC = $(BUFFER_DIR)/input_loader.v
PSUM_BUF_SRC = $(BUFFER_DIR)/psum_buffer.v
WEIGHT_BUF_SRC = $(BUFFER_DIR)/weight_buffer.v
ACT_BUF_SRC = $(BUFFER_DIR)/act_buffer.v
PE_TOP_SRC = $(SRC_DIR)/pe_top.v
PPU_SRC    = $(PPU_DIR)/requantizer.v

# =========================================================================
# Build Targets
# =========================================================================
OUT_MAC    = $(BUILD_DIR)/mac_sim
OUT_ARRAY  = $(BUILD_DIR)/pe_array_sim
OUT_CTRL   = $(BUILD_DIR)/pe_controller_sim
OUT_CONV   = $(BUILD_DIR)/sim_conv
OUT_SYSTEM = $(BUILD_DIR)/sim_system

VCD_MAC    = $(WAVE_DIR)/mac_tb.vcd
VCD_ARRAY  = $(WAVE_DIR)/pe_array_tb.vcd
VCD_CTRL   = $(WAVE_DIR)/pe_controller_tb.vcd
VCD_CONV   = $(WAVE_DIR)/tb_conv_16x16.vcd
VCD_SYSTEM = $(WAVE_DIR)/tb_pe_top.vcd

# =========================================================================
# Phony Targets
# =========================================================================
.PHONY: all clean mac pe_array pe_controller conv_test system_test view_mac view_array view_ctrl help dirs

# Default target
all: system_test

# Help message
help:
	@echo "=========================================="
	@echo "FPGA Project Makefile - Available Targets"
	@echo "=========================================="
	@echo "  make mac           - Compile and run MAC unit test"
	@echo "  make pe_array      - Compile and run PE Array test"
	@echo "  make pe_controller - Compile and run PE Controller test"
	@echo "  make all           - Run all tests"
	@echo "  make clean         - Remove all generated files"
	@echo "  make view_mac      - View MAC waveform"
	@echo "  make view_array    - View PE Array waveform"
	@echo "  make view_ctrl     - View PE Controller waveform"
	@echo "=========================================="

# Create build directories
dirs:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(WAVE_DIR)

# =========================================================================
# MAC Unit Test
# =========================================================================
mac: dirs $(OUT_MAC)
	@echo "=========================================="
	@echo "Running MAC Unit Test"
	@echo "=========================================="
	$(VVP) $(VVPFLAGS) $(OUT_MAC)
	@if [ -f mac_tb.vcd ]; then mv mac_tb.vcd $(VCD_MAC); fi
	@echo "Waveform saved to $(VCD_MAC)"
	@echo ""

$(OUT_MAC): $(MAC_SRC) $(MAC_TB)
	@echo "Compiling MAC unit..."
	$(IVERILOG) $(IVFLAGS) -o $(OUT_MAC) $(MAC_SRC) $(MAC_TB)

view_mac: $(VCD_MAC)
	$(GTKWAVE) $(VCD_MAC) &

# =========================================================================
# PE Array Test
# =========================================================================
pe_array: dirs $(OUT_ARRAY)
	@echo "=========================================="
	@echo "Running PE Array Test"
	@echo "=========================================="
	$(VVP) $(VVPFLAGS) $(OUT_ARRAY)
	@if [ -f pe_array_tb.vcd ]; then mv pe_array_tb.vcd $(VCD_ARRAY); fi
	@echo "Waveform saved to $(VCD_ARRAY)"
	@echo ""

$(OUT_ARRAY): $(MAC_SRC) $(ARRAY_SRC) $(ARRAY_TB)
	@echo "Compiling PE Array..."
	$(IVERILOG) $(IVFLAGS) -o $(OUT_ARRAY) $(MAC_SRC) $(ARRAY_SRC) $(ARRAY_TB)

view_array: $(VCD_ARRAY)
	$(GTKWAVE) $(VCD_ARRAY) &

# =========================================================================
# PE Controller Test
# =========================================================================
pe_controller: dirs $(OUT_CTRL)
	@echo "=========================================="
	@echo "Running PE Controller Test"
	@echo "=========================================="
	$(VVP) $(VVPFLAGS) $(OUT_CTRL)
	@if [ -f pe_controller_tb.vcd ]; then mv pe_controller_tb.vcd $(VCD_CTRL); fi
	@echo "Waveform saved to $(VCD_CTRL)"
	@echo ""

$(OUT_CTRL): $(CTRL_SRC) $(CTRL_TB)
	@echo "Compiling PE Controller..."
	$(IVERILOG) $(IVFLAGS) -o $(OUT_CTRL) $(CTRL_SRC) $(CTRL_TB)

view_ctrl: $(VCD_CTRL)
	$(GTKWAVE) $(VCD_CTRL) &

# =========================================================================
# Convolution Test
# =========================================================================
conv_test: dirs $(OUT_CONV)
	@echo "=========================================="
	@echo "Running Advanced Convolution Test"
	@echo "=========================================="
	$(VVP) $(VVPFLAGS) $(OUT_CONV)
	@if [ -f tb_conv_16x16.vcd ]; then mv tb_conv_16x16.vcd $(VCD_CONV); fi
	@echo "Waveform saved to $(VCD_CONV)"
	@echo ""

$(OUT_CONV): $(CONV_TB) $(CTRL_SRC) $(ARRAY_SRC) $(MAC_SRC) $(PSUM_BUF_SRC)
	@echo "Compiling Convolution Test..."
	$(IVERILOG) $(IVFLAGS) -o $(OUT_CONV) $(CONV_TB) $(CTRL_SRC) $(ARRAY_SRC) $(MAC_SRC) $(PSUM_BUF_SRC)

# =========================================================================
# System Test (PE Top)
# =========================================================================
system_test: dirs $(OUT_SYSTEM)
	@echo "=========================================="
	@echo "Running PE System Test"
	@echo "=========================================="
	$(VVP) $(VVPFLAGS) $(OUT_SYSTEM)
	@if [ -f tb_pe_top.vcd ]; then mv tb_pe_top.vcd $(VCD_SYSTEM); fi
	@echo "Waveform saved to $(VCD_SYSTEM)"
	@echo ""

$(OUT_SYSTEM): $(SYSTEM_TB) $(PE_TOP_SRC) $(CONFIG_SRC) $(WEIGHT_BUF_SRC) $(ACT_BUF_SRC) $(CTRL_SRC) $(ARRAY_SRC) $(MAC_SRC) $(PSUM_BUF_SRC)
	@echo "Compiling System Test..."
	$(IVERILOG) $(IVFLAGS) -o $(OUT_SYSTEM) $(SYSTEM_TB) $(PE_TOP_SRC) $(CONFIG_SRC) $(WEIGHT_BUF_SRC) $(ACT_BUF_SRC) $(CTRL_SRC) $(ARRAY_SRC) $(MAC_SRC) $(PSUM_BUF_SRC)

# =========================================================================
# Clean Target
# =========================================================================
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(WAVE_DIR)
	rm -f *.vcd
	rm -f *.vvp
	@echo "Clean complete."

# =========================================================================
# Additional Utilities
# =========================================================================
# Check if tools are installed
check-tools:
	@echo "Checking for required tools..."
	@which $(IVERILOG) > /dev/null || (echo "ERROR: iverilog not found" && exit 1)
	@which $(VVP) > /dev/null || (echo "ERROR: vvp not found" && exit 1)
	@which $(GTKWAVE) > /dev/null || echo "WARNING: gtkwave not found (optional)"
	@echo "All required tools found."

# List all source files
list-sources:
	@echo "Source Files:"
	@echo "  MAC:        $(MAC_SRC)"
	@echo "  Array:      $(ARRAY_SRC)"
	@echo "  Controller: $(CTRL_SRC)"
	@echo "  Config:     $(CONFIG_SRC)"
	@echo "  Buffer:     $(BUFFER_SRC)"
	@echo "  PPU:        $(PPU_SRC)"
