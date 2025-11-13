import numpy as np

class SimData:
    def __init__(self, data=None, q=0):
        """
        初始化SimData对象
        Args:
            data: numpy数组数据
            q: 量化位移，表示 int8_value = float_value * 2^q，scale = 2^q
        """
        self.data = data
        self.q = q
        self.scale = 2 ** q  # scale = 2^q
    
    def __repr__(self):
        """String representation for debugging"""
        if self.data is not None:
            return f"SimData(shape={self.data.shape}, q={self.q}, scale={self.scale:.6f}, range=[{np.min(self.data):.2f}, {np.max(self.data):.2f}])"
        return f"SimData(data=None, q={self.q}, scale={self.scale:.6f})"

    @staticmethod
    def quantize_to_int8(data, scale=None):
        """
        将浮点数据量化到int8范围 (-127 ~ 127)
        
        Args:
            data: 浮点数numpy数组
            scale: 量化比例因子，如果为None则自动计算
        
        Returns:
            量化后的int8数组, 量化比例因子
        """
        if scale is None:
            # 自动计算量化比例因子
            data_max = np.max(np.abs(data))
            if data_max == 0:
                scale = 1.0
            else:
                scale = 127.0 / data_max
        
        # 量化到int8范围：先clip再floor再转换
        # 使用floor而不是round或trunc，这样与硬件行为一致
        quantized = data * scale
        quantized = np.clip(quantized, -127, 127)
        quantized = np.floor(quantized).astype(np.int8)
        
        return quantized, scale
    
    @staticmethod
    def dequantize_from_int8(quantized_data, scale):
        """
        将int8数据反量化到浮点数
        
        Args:
            quantized_data: int8数组
            scale: 量化比例因子
        
        Returns:
            反量化后的浮点数组
        """
        return quantized_data.astype(np.float32) / scale
    
    @staticmethod
    def load_data_from_binary(file_path, n_channels, height, width, q=0):
        """
        从二进制文件加载输入数据
        文件格式: binary (int8, 量化范围 -127 ~ 127)
        数据顺序: [n_channel, height, width]
        按行主序展平
        
        Args:
            file_path: 二进制文件路径
            n_channels: 通道数
            height: 高度
            width: 宽度
            q: 量化位移，scale = 2^q
        
        Returns:
            SimData对象，包含数据和q信息
        """
        try:
            # 读取二进制文件 (int8格式)
            data_flat = np.fromfile(file_path, dtype=np.int8)
            
            # 检查数据大小
            expected_size = n_channels * height * width
            if len(data_flat) != expected_size:
                raise ValueError(f"数据文件大小不匹配。期望 {expected_size} 个值，实际得到 {len(data_flat)} 个值")
            
            # 保持int8格式（不反量化），因为我们在int8域计算
            # 重塑为正确的形状: [n_channel, height, width]
            data = data_flat.reshape(n_channels, height, width)
            
            # 添加batch维度，返回 (1, n_channels, height, width)
            data = np.expand_dims(data, axis=0).astype(np.float32)
            
            print(f"成功从二进制文件加载数据: {file_path}, 形状: {data.shape}, q={q}, scale={2**q}")
            return SimData(data=data, q=q)
            
        except Exception as e:
            print(f"加载二进制数据文件失败: {e}")
            raise
    
    @staticmethod
    def save_data_to_binary(data, file_path, scale=None):
        """
        将数据保存为二进制文件
        数据格式: binary (int8, 量化范围 -127 ~ 127)
        数据顺序: [n_channel, height, width]
        按行主序展平
        
        Args:
            data: numpy数组，形状可以是 (n_channels, height, width) 或 (batch, n_channels, height, width)
            file_path: 保存的二进制文件路径
            scale: 量化比例因子，如果为None则自动计算
        
        Returns:
            量化比例因子
        """
        try:
            # 如果有batch维度，取第一个batch
            if data.ndim == 4:
                data = data[0]  # 取第一个batch
            elif data.ndim != 3:
                raise ValueError(f"数据维度不正确。期望3D或4D数组，实际得到 {data.ndim}D")
            
            # 展平数据
            data_flat = data.flatten()
            
            # 量化到int8格式
            quantized_data, used_scale = SimData.quantize_to_int8(data_flat, scale)
            
            # 保存为binary文件
            quantized_data.tofile(file_path)
            
            print(f"成功保存数据到二进制文件: {file_path}, 形状: {data.shape}, 量化比例: {used_scale}")
            return used_scale
            
        except Exception as e:
            print(f"保存二进制数据文件失败: {e}")
            raise
    
    @staticmethod
    def numpy_to_simdata_format(data: np.ndarray) -> np.ndarray:
        """
        将numpy数组转换为SimData格式 (确保是正确的维度顺序)
        
        Args:
            data: numpy数组
        
        Returns:
            转换后的数组，确保维度顺序为 [batch, n_channel, height, width]
        """
        if data.ndim == 3:
            # 添加batch维度
            data = np.expand_dims(data, axis=0)
        elif data.ndim != 4:
            raise ValueError(f"数据维度不正确。期望3D或4D数组，实际得到 {data.ndim}D")
        
        return data
    
    @staticmethod
    def simdata_to_numpy_format(data):
        """
        将SimData格式转换为标准numpy格式
        
        Args:
            data: SimData格式的数组 [batch, n_channel, height, width]
        
        Returns:
            转换后的数组
        """
        return data

class ConvLayer:
    def __init__(self, input_channels, output_channels, kernel_size, stride=1, padding=0):
        self.input_channels = input_channels
        self.output_channels = output_channels
        self.kernel_size = kernel_size
        self.stride = stride
        self.padding = padding
        self.weights = np.random.randn(output_channels, input_channels, kernel_size, kernel_size) * 0.01
        self.bias = np.zeros((output_channels, 1))
        self.weight_q = 0  # 权重的量化位移
        self.weight_scale = 1.0  # 权重的量化比例因子 = 2^weight_q
    
    def load_weights_from_text(self, file_path):
        """
        从纯文本文件加载权重
        文件格式: plain text
        数据顺序: [out_channel, in_channel, kernel_h, kernel_w]
        按行主序展平
        """
        try:
            # 读取纯文本文件
            with open(file_path, 'r') as f:
                data = f.read().strip().split()
            
            # 转换为浮点数
            weights_flat = np.array([float(x) for x in data])
            
            # 重塑为正确的形状
            expected_size = self.output_channels * self.input_channels * self.kernel_size * self.kernel_size
            if len(weights_flat) != expected_size:
                raise ValueError(f"权重文件大小不匹配。期望 {expected_size} 个值，实际得到 {len(weights_flat)} 个值")
            
            self.weights = weights_flat.reshape(self.output_channels, self.input_channels, self.kernel_size, self.kernel_size)
            print(f"成功从文本文件加载权重: {file_path}")
            
        except Exception as e:
            print(f"加载文本权重文件失败: {e}")
            raise
    
    def load_weights_from_binary(self, file_path, q=0):
        """
        从二进制文件加载权重
        文件格式: binary (int8, 量化范围 -127 ~ 127)
        数据顺序: [out_channel, in_channel, kernel_h, kernel_w]
        按行主序展平
        
        Args:
            file_path: 二进制权重文件路径
            q: 量化位移，scale = 2^q
        """
        try:
            # 读取二进制文件 (int8格式)
            weights_flat = np.fromfile(file_path, dtype=np.int8)
            
            # 检查数据大小
            expected_size = self.output_channels * self.input_channels * self.kernel_size * self.kernel_size
            if len(weights_flat) != expected_size:
                raise ValueError(f"权重文件大小不匹配。期望 {expected_size} 个值，实际得到 {len(weights_flat)} 个值")
            
            # 保持int8格式（存储为float32但值是int8范围）
            weights_flat = weights_flat.astype(np.float32)
            
            # 重塑为正确的形状
            self.weights = weights_flat.reshape(self.output_channels, self.input_channels, self.kernel_size, self.kernel_size)
            self.weight_q = q  # 保存权重的量化位移
            self.weight_scale = 2 ** q  # 计算量化比例因子
            print(f"成功从二进制文件加载权重: {file_path}, q={q}, scale={self.weight_scale}")
            
        except Exception as e:
            print(f"加载二进制权重文件失败: {e}")
            raise
    
    def save_weights_to_text(self, file_path):
        """
        将权重保存为纯文本文件
        """
        try:
            weights_flat = self.weights.flatten()
            with open(file_path, 'w') as f:
                for weight in weights_flat:
                    f.write(f"{weight}\n")
            print(f"成功保存权重到文本文件: {file_path}")
        except Exception as e:
            print(f"保存文本权重文件失败: {e}")
            raise
    
    def save_weights_to_binary(self, file_path, scale=None):
        """
        将权重保存为二进制文件
        文件格式: binary (int8, 量化范围 -127 ~ 127)
        
        Args:
            file_path: 保存的二进制文件路径
            scale: 量化比例因子，如果为None则自动计算
        
        Returns:
            量化比例因子
        """
        try:
            weights_flat = self.weights.flatten()
            
            # 量化到int8格式
            quantized_weights, used_scale = SimData.quantize_to_int8(weights_flat, scale)
            
            # 保存为binary文件
            quantized_weights.tofile(file_path)
            
            print(f"成功保存权重到二进制文件: {file_path}, 量化比例: {used_scale}")
            return used_scale
        except Exception as e:
            print(f"保存二进制权重文件失败: {e}")
            raise

    def forward(self, input_simdata, output_q=0):
        """
        在int8域进行卷积计算，模拟硬件行为
        自动根据输入、权重、输出的量化精度计算requant_shift
        
        Args:
            input_simdata: SimData对象，包含int8量化后的输入数据和q
            output_q: 期望的输出量化位移，output_scale = 2^output_q
        
        Returns:
            SimData对象，包含int8量化后的输出数据和q
        """
        input_data = input_simdata.data
        input_q = input_simdata.q
        
        # 计算requant_shift
        requant_shift = input_q + self.weight_q - output_q
        
        # print(f"  [ConvLayer] input_q={input_q}, weight_q={self.weight_q}, output_q={output_q}")
        # print(f"  [ConvLayer] 计算得到 requant_shift={requant_shift}")
        
        batch_size, in_channels, in_height, in_width = input_data.shape
        out_height = (in_height - self.kernel_size + 2 * self.padding) // self.stride + 1
        out_width = (in_width - self.kernel_size + 2 * self.padding) // self.stride + 1
        
        # 转换为int8（四舍五入）
        input_int8 = np.round(input_data).astype(np.int8)
        weights_int8 = np.round(self.weights).astype(np.int8)
        bias_int8 = np.round(self.bias).astype(np.int32)
        
        # 输出数组
        output_data = np.zeros((batch_size, self.output_channels, out_height, out_width), dtype=np.float32)
        
        if self.padding > 0:
            input_int8 = np.pad(input_int8, ((0, 0), (0, 0), (self.padding, self.padding), (self.padding, self.padding)), mode='constant')
        
        for b in range(batch_size):
            for oc in range(self.output_channels):
                for oh in range(out_height):
                    for ow in range(out_width):
                        h_start = oh * self.stride
                        w_start = ow * self.stride
                        h_end = h_start + self.kernel_size
                        w_end = w_start + self.kernel_size
                        
                        # 在int32域进行乘法累加，避免溢出
                        acc = np.int32(0)
                        for ic in range(in_channels):
                            for kh in range(self.kernel_size):
                                for kw in range(self.kernel_size):
                                    # int8 * int8 -> int32
                                    inp_val = np.int32(input_int8[b, ic, h_start+kh, w_start+kw])
                                    weight_val = np.int32(weights_int8[oc, ic, kh, kw])
                                    acc += inp_val * weight_val
                        
                        # 加上bias
                        acc += bias_int8[oc, 0]
                        
                        # Requantization: 右移指定位数
                        acc = acc >> requant_shift
                        
                        # clip到int8范围 [-127, 127]
                        output_data[b, oc, oh, ow] = np.float32(np.clip(acc, -127, 127))
        
        return SimData(data=output_data, q=output_q)

class FcLayer:
    def __init__(self, input_size, output_size):
        self.input_size = input_size
        self.output_size = output_size
        self.weights = np.random.randn(output_size, input_size) * 0.01
        self.bias = np.zeros((output_size, 1))
        self.weight_q = 0  # 权重的量化位移
        self.weight_scale = 1.0  # 权重的量化比例因子 = 2^weight_q
    
    def load_weights_from_text(self, file_path):
        """
        从纯文本文件加载权重
        文件格式: plain text
        数据顺序: [out_channel, in_channel]
        按行主序展平
        """
        try:
            # 读取纯文本文件
            with open(file_path, 'r') as f:
                data = f.read().strip().split()
            
            # 转换为浮点数
            weights_flat = np.array([float(x) for x in data])
            
            # 重塑为正确的形状
            expected_size = self.output_size * self.input_size
            if len(weights_flat) != expected_size:
                raise ValueError(f"权重文件大小不匹配。期望 {expected_size} 个值，实际得到 {len(weights_flat)} 个值")
            
            self.weights = weights_flat.reshape(self.output_size, self.input_size)
            print(f"成功从文本文件加载权重: {file_path}")
            
        except Exception as e:
            print(f"加载文本权重文件失败: {e}")
            raise
    
    def load_weights_from_binary(self, file_path, q=0):
        """
        从二进制文件加载权重
        文件格式: binary (int8, 量化范围 -127 ~ 127)
        数据顺序: [out_channel, in_channel]
        按行主序展平
        
        Args:
            file_path: 二进制权重文件路径
            q: 量化位移，scale = 2^q
        """
        try:
            # 读取二进制文件 (int8格式)
            weights_flat = np.fromfile(file_path, dtype=np.int8)
            
            # 检查数据大小
            expected_size = self.output_size * self.input_size
            if len(weights_flat) != expected_size:
                raise ValueError(f"权重文件大小不匹配。期望 {expected_size} 个值，实际得到 {len(weights_flat)} 个值")
            
            # 保持int8格式（存储为float32但值是int8范围）
            weights_flat = weights_flat.astype(np.float32)
            
            # 重塑为正确的形状
            self.weights = weights_flat.reshape(self.output_size, self.input_size)
            self.weight_q = q  # 保存权重的量化位移
            self.weight_scale = 2 ** q  # 计算量化比例因子
            print(f"成功从二进制文件加载权重: {file_path}, q={q}, scale={self.weight_scale}")
            
        except Exception as e:
            print(f"加载二进制权重文件失败: {e}")
            raise
    
    def save_weights_to_text(self, file_path):
        """
        将权重保存为纯文本文件
        """
        try:
            weights_flat = self.weights.flatten()
            with open(file_path, 'w') as f:
                for weight in weights_flat:
                    f.write(f"{weight}\n")
            print(f"成功保存权重到文本文件: {file_path}")
        except Exception as e:
            print(f"保存文本权重文件失败: {e}")
            raise
    
    def save_weights_to_binary(self, file_path, scale=None):
        """
        将权重保存为二进制文件
        文件格式: binary (int8, 量化范围 -127 ~ 127)
        
        Args:
            file_path: 保存的二进制文件路径
            scale: 量化比例因子，如果为None则自动计算
        
        Returns:
            量化比例因子
        """
        try:
            weights_flat = self.weights.flatten()
            
            # 量化到int8格式
            quantized_weights, used_scale = SimData.quantize_to_int8(weights_flat, scale)
            
            # 保存为binary文件
            quantized_weights.tofile(file_path)
            
            print(f"成功保存权重到二进制文件: {file_path}, 量化比例: {used_scale}")
            return used_scale
        except Exception as e:
            print(f"保存二进制权重文件失败: {e}")
            raise
    
    def forward(self, input_simdata, output_q=0):
        """
        在int8域进行全连接层计算，模拟硬件行为
        自动根据输入、权重、输出的量化精度计算requant_shift
        
        Args:
            input_simdata: SimData对象，包含int8量化后的输入数据和q
                          可以是4D (batch, channels, h, w) 或 2D (batch, features)
            output_q: 期望的输出量化位移，output_scale = 2^output_q
        
        Returns:
            SimData对象，包含int8量化后的输出数据和q
        """
        input_data = input_simdata.data
        input_q = input_simdata.q
        
        # 如果输入是4D，展平为2D
        if input_data.ndim == 4:
            batch_size = input_data.shape[0]
            input_data = input_data.reshape(batch_size, -1)
        
        batch_size = input_data.shape[0]
        
        # 计算requant_shift
        # requant_shift = input_q + weight_q - output_q
        requant_shift = input_q + self.weight_q - output_q
        
        print(f"  [FcLayer] input_q={input_q}, weight_q={self.weight_q}, output_q={output_q}")
        print(f"  [FcLayer] 计算得到 requant_shift={requant_shift}")
        
        # 转换为int8
        input_int8 = np.round(input_data).astype(np.int8)
        weights_int8 = np.round(self.weights).astype(np.int8)
        bias_int8 = np.round(self.bias).astype(np.int32)
        
        # 输出数组
        output_data = np.zeros((batch_size, self.output_size), dtype=np.float32)
        
        for b in range(batch_size):
            for o in range(self.output_size):
                # 在int32域进行乘法累加
                acc = np.int32(0)
                for i in range(self.input_size):
                    # int8 * int8 -> int32
                    acc += np.int32(input_int8[b, i]) * np.int32(weights_int8[o, i])
                
                # 加上bias
                acc += bias_int8[o, 0]
                
                # Requantization: 右移指定位数
                acc = acc >> requant_shift
                
                # clip到int8范围 [-127, 127]
                output_data[b, o] = np.float32(np.clip(acc, -127, 127))
        
        return SimData(data=output_data, q=output_q)