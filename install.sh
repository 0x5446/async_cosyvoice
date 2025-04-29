#!/bin/bash

set -e  # 出错立即退出

WORKSPACE=$1
PYTHON_VERSION="3.10"  # 指定Python版本

if [ -z "$WORKSPACE" ]; then
  echo "❌ 请传入工作目录作为第一个参数，例如：./install.sh /path/to/workspace"
  exit 1
fi

mkdir -p "$WORKSPACE"

# ========== 1. 安装系统依赖 ==========
echo "📦 安装系统依赖..."
apt-get update -y

# 卸载已有Python版本
echo "🔄 卸载已有Python版本..."
apt-get remove -y python3 python3-pip python3-dev || true

# 安装指定版本的Python
echo "📥 安装Python ${PYTHON_VERSION}..."
apt-get install -y git unzip git-lfs sox libsox-dev build-essential python${PYTHON_VERSION} python${PYTHON_VERSION}-pip python${PYTHON_VERSION}-dev

# 创建软链接确保python3和pip3指向正确版本
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1
update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip${PYTHON_VERSION} 1

# 初始化 git lfs
git lfs install || true

# ========== 2. 克隆主项目 ==========
echo "📥 处理 CosyVoice 主项目..."
COSY_DIR="$WORKSPACE/CosyVoice"
if [ -d "$COSY_DIR" ]; then
  read -p "⚠️ 检测到 $COSY_DIR 已存在，是否清理重装？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    rm -rf "$COSY_DIR"
  else
    echo "✅ 跳过主项目克隆"
  fi
fi

if [ ! -d "$COSY_DIR" ]; then
  git clone --branch dev/Comet --single-branch --recursive https://github.com/FunAudioLLM/CosyVoice.git "$COSY_DIR"
fi

# ========== 3. 安装 Python 依赖 ==========
echo "🐍 安装 pynini..."
pip install pynini==2.1.5

echo "📥 处理 async_cosyvoice 子项目..."
ASYNC_DIR="$COSY_DIR/async_cosyvoice"
if [ -d "$ASYNC_DIR" ]; then
  read -p "⚠️ 检测到 $ASYNC_DIR 已存在，是否清理重装？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    rm -rf "$ASYNC_DIR"
  else
    echo "✅ 跳过 async_cosyvoice 克隆"
  fi
fi

if [ ! -d "$ASYNC_DIR" ]; then
  git clone https://github.com/0x5446/async_cosyvoice.git "$ASYNC_DIR"
fi

cd "$ASYNC_DIR"
pip install -r requirements.txt

# ========== 4. 下载模型并拷贝 ==========
echo "🎯 处理模型文件..."
PRETRAINED_DIR="$COSY_DIR/pretrained_models/CosyVoice2-0.5B"
MODEL_COMMIT="9bd5b08fc085bd93d3f8edb16b67295606290350"

if [ -d "$PRETRAINED_DIR" ]; then
  read -p "⚠️ 模型目录已存在，是否清理并重新下载？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    rm -rf "$PRETRAINED_DIR"
  else
    echo "✅ 跳过模型拷贝"
  fi
fi

if [ ! -d "$PRETRAINED_DIR" ]; then
  echo "📥 克隆模型并切换到指定 commit: $MODEL_COMMIT"
  mkdir -p "$PRETRAINED_DIR"
  git clone https://www.modelscope.cn/iic/CosyVoice2-0.5B.git "$PRETRAINED_DIR"
  cd "$PRETRAINED_DIR"
  git checkout "$MODEL_COMMIT"
  
  # 使用ASYNC_DIR中的文件覆盖模型目录
  if [ -d "$ASYNC_DIR/CosyVoice2-0.5B" ]; then
    echo "📥 从async_cosyvoice/CosyVoice2-0.5B覆盖模型目录..."
    cp -r "$ASYNC_DIR/CosyVoice2-0.5B"/* "$PRETRAINED_DIR"
  else
    echo "⚠️ $ASYNC_DIR/CosyVoice2-0.5B 目录不存在，跳过覆盖步骤"
  fi
fi

# ========== 完成提示 ==========
echo ""
echo "✅ 安装完成！你可以运行以下命令启动服务："
echo "cd $COSY_DIR/async_cosyvoice/runtime/async_grpc"
echo "python3 server.py --load_jit --load_trt --fp16"

