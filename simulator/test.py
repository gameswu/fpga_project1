"""
Unit tests for neural network layers using pytest framework.

Tests Conv and FC layers with int8 quantization against expected outputs
from binary test data files.
"""

import pytest
from sim import ConvLayer, FcLayer, SimData
import os
import numpy as np
from pathlib import Path

PARAM_DIR = Path("data") / "parameters"
DATA_DIR = Path("data")

# Test data directories
TEST_DIRS = [f"im{i}" for i in range(1, 9)]


@pytest.fixture(scope="class")
def layers():
    """Fixture to create and load all layer weights once per test class."""
    # Float layers (not used in current tests, but kept for reference)
    conv1 = ConvLayer(input_channels=1, output_channels=32, kernel_size=5, stride=1, padding=2)
    conv2 = ConvLayer(input_channels=32, output_channels=64, kernel_size=3, stride=1, padding=1)
    conv3 = ConvLayer(input_channels=64, output_channels=64, kernel_size=3, stride=2, padding=1)
    conv4 = ConvLayer(input_channels=64, output_channels=128, kernel_size=3, stride=2, padding=1)
    fc = FcLayer(input_size=128, output_size=10)

    conv1.load_weights_from_text(str(PARAM_DIR / "conv1.real.dat"))
    conv2.load_weights_from_text(str(PARAM_DIR / "conv2.real.dat"))
    conv3.load_weights_from_text(str(PARAM_DIR / "conv3.real.dat"))
    conv4.load_weights_from_text(str(PARAM_DIR / "conv4.real.dat"))
    fc.load_weights_from_text(str(PARAM_DIR / "fc.real.dat"))

    # Int8 quantized layers
    conv1_int8 = ConvLayer(input_channels=1, output_channels=32, kernel_size=5, stride=1, padding=2, requant_shift=9)
    conv2_int8 = ConvLayer(input_channels=32, output_channels=64, kernel_size=3, stride=1, padding=1, requant_shift=8)
    conv3_int8 = ConvLayer(input_channels=64, output_channels=64, kernel_size=3, stride=2, padding=1, requant_shift=8)
    conv4_int8 = ConvLayer(input_channels=64, output_channels=128, kernel_size=3, stride=2, padding=1, requant_shift=8)
    fc_int8 = FcLayer(input_size=128, output_size=10, requant_shift=6)

    conv1_int8.load_weights_from_binary(str(PARAM_DIR / "conv1.dat"), scale=1.0)
    conv2_int8.load_weights_from_binary(str(PARAM_DIR / "conv2.dat"), scale=1.0)
    conv3_int8.load_weights_from_binary(str(PARAM_DIR / "conv3.dat"), scale=1.0)
    conv4_int8.load_weights_from_binary(str(PARAM_DIR / "conv4.dat"), scale=1.0)
    fc_int8.load_weights_from_binary(str(PARAM_DIR / "fc.dat"), scale=1.0)

    return {
        'conv1': conv1, 'conv2': conv2, 'conv3': conv3, 'conv4': conv4, 'fc': fc,
        'conv1_int8': conv1_int8, 'conv2_int8': conv2_int8, 'conv3_int8': conv3_int8,
        'conv4_int8': conv4_int8, 'fc_int8': fc_int8
    }


def assert_arrays_equal_with_details(actual, expected, layer_name):
    """
    Assert that two arrays are equal and provide detailed diagnostic info if not.
    
    Args:
        actual: Computed output array
        expected: Expected output array
        layer_name: Name of the layer being tested (for error messages)
    """
    # Print diagnostic information
    print(f"\n{layer_name} - 计算输出形状: {actual.shape}")
    print(f"{layer_name} - 期望输出形状: {expected.shape}")
    print(f"{layer_name} - 计算输出范围: [{np.min(actual):.6f}, {np.max(actual):.6f}]")
    print(f"{layer_name} - 期望输出范围: [{np.min(expected):.6f}, {np.max(expected):.6f}]")
    
    if not np.array_equal(actual, expected):
        diff = np.abs(actual - expected)
        max_diff_idx = np.unravel_index(np.argmax(diff), diff.shape)
        print(f"{layer_name} - 最大差异位置: {max_diff_idx}")
        print(f"{layer_name} - 计算值: {actual[max_diff_idx]:.6f}")
        print(f"{layer_name} - 期望值: {expected[max_diff_idx]:.6f}")
        print(f"{layer_name} - 最大差异: {np.max(diff):.6f}")
        print(f"{layer_name} - 平均差异: {np.mean(diff):.6f}")
        
        if np.allclose(actual, expected, rtol=1e-5, atol=1e-6):
            print(f"{layer_name} - 数值在容差范围内相等")
        else:
            print(f"{layer_name} - 数值差异超出容差")
            pytest.fail(f"{layer_name}计算错误: 最大差异 {np.max(diff):.6f} 在位置 {max_diff_idx}")
    else:
        print(f"{layer_name} - 完全匹配!")


@pytest.mark.parametrize("test_dir_name", TEST_DIRS)
class TestConvLayers:
    """Test suite for convolutional layers with int8 quantization."""
    
    def test_conv1_int8(self, layers, test_dir_name):
        """Test Conv1 layer with int8 quantization."""
        test_dir = DATA_DIR / test_dir_name
        
        # Load input and expected output
        input_data = SimData.load_data_from_binary(
            str(test_dir / "conv1.input.dat"), 1, 32, 32, scale=1.0
        )
        expected_output = SimData.load_data_from_binary(
            str(test_dir / "conv1.output.dat"), 32, 32, 32, scale=1.0
        )
        
        # Forward pass
        output = layers['conv1_int8'].forward(input_data)
        
        # Assert equality with detailed diagnostics
        assert_arrays_equal_with_details(output, expected_output, f"Conv1 ({test_dir_name})")
    
    def test_conv2_int8(self, layers, test_dir_name):
        """Test Conv2 layer with int8 quantization."""
        test_dir = DATA_DIR / test_dir_name
        
        # Load input and expected output
        input_data = SimData.load_data_from_binary(
            str(test_dir / "conv2.input.dat"), 32, 16, 16, scale=1.0
        )
        expected_output = SimData.load_data_from_binary(
            str(test_dir / "conv2.output.dat"), 64, 16, 16, scale=1.0
        )
        
        # Forward pass
        output = layers['conv2_int8'].forward(input_data)
        
        # Assert equality with detailed diagnostics
        assert_arrays_equal_with_details(output, expected_output, f"Conv2 ({test_dir_name})")
    
    def test_conv3_int8(self, layers, test_dir_name):
        """Test Conv3 layer with int8 quantization."""
        test_dir = DATA_DIR / test_dir_name
        
        # Load input and expected output
        input_data = SimData.load_data_from_binary(
            str(test_dir / "conv3.input.dat"), 64, 16, 16, scale=1.0
        )
        expected_output = SimData.load_data_from_binary(
            str(test_dir / "conv3.output.dat"), 64, 8, 8, scale=1.0
        )
        
        # Forward pass
        output = layers['conv3_int8'].forward(input_data)
        
        # Assert equality with detailed diagnostics
        assert_arrays_equal_with_details(output, expected_output, f"Conv3 ({test_dir_name})")
    
    def test_conv4_int8(self, layers, test_dir_name):
        """Test Conv4 layer with int8 quantization."""
        test_dir = DATA_DIR / test_dir_name
        
        # Load input and expected output
        input_data = SimData.load_data_from_binary(
            str(test_dir / "conv4.input.dat"), 64, 8, 8, scale=1.0
        )
        expected_output = SimData.load_data_from_binary(
            str(test_dir / "conv4.output.dat"), 128, 4, 4, scale=1.0
        )
        
        # Forward pass
        output = layers['conv4_int8'].forward(input_data)
        
        # Assert equality with detailed diagnostics
        assert_arrays_equal_with_details(output, expected_output, f"Conv4 ({test_dir_name})")


@pytest.mark.parametrize("test_dir_name", TEST_DIRS)
class TestFcLayer:
    """Test suite for fully connected layer with int8 quantization."""
    
    def test_fc_int8(self, layers, test_dir_name):
        """Test FC layer with int8 quantization."""
        test_dir = DATA_DIR / test_dir_name
        
        # Load input and expected output
        input_data = SimData.load_data_from_binary(
            str(test_dir / "fc.input.dat"), 128, 1, 1, scale=1.0
        )
        expected_output = SimData.load_data_from_binary(
            str(test_dir / "fc.output.dat"), 10, 1, 1, scale=1.0
        )
        
        # Forward pass (flatten input for FC layer)
        output = layers['fc_int8'].forward(input_data.reshape(1, -1))
        expected_output = expected_output.reshape(1, -1)
        
        # Assert equality with detailed diagnostics
        assert_arrays_equal_with_details(output, expected_output, f"FC ({test_dir_name})")


if __name__ == "__main__":
    # Run tests with pytest when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
