#!/bin/bash

set -e  # 出错立即退出

WORKSPACE=$1

if [ -z "$WORKSPACE" ]; then
  echo "❌ 请传入工作目录作为第一个参数，例如：./install.sh /path/to/workspace"
  exit 1
fi

mkdir -p "$WORKSPACE"

# ========== 1. 安装系统依赖 ==========
echo "📦 安装系统依赖..."
apt-get update -y
apt-get install -y git unzip git-lfs sox libsox-dev build-essential wget

# 初始化 git lfs
git lfs install || true

# ========== 2. 安装 Miniconda3 ==========
echo "📦 安装 Miniconda3..."
MINICONDA_DIR="$WORKSPACE/miniconda3"
if [ -d "$MINICONDA_DIR" ]; then
  read -p "⚠️ 检测到 $MINICONDA_DIR 已存在，是否清理重装？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    rm -rf "$MINICONDA_DIR"
  else
    echo "✅ 跳过 Miniconda3 安装"
  fi
fi

if [ ! -d "$MINICONDA_DIR" ]; then
  MINICONDA_INSTALLER="$WORKSPACE/miniconda.sh"
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$MINICONDA_INSTALLER"
  bash "$MINICONDA_INSTALLER" -b -p "$MINICONDA_DIR"
  rm "$MINICONDA_INSTALLER"
fi

# 设置Conda环境变量
export PATH="$MINICONDA_DIR/bin:$PATH"
. "$MINICONDA_DIR/etc/profile.d/conda.sh"

# 创建cosyvoice2环境
echo "🐍 创建 cosyvoice2 conda 环境..."
conda create -y -n cosyvoice2 python=3.10
conda activate cosyvoice2

# ========== 3. 克隆主项目 ==========
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

# ========== 4. 安装 Python 依赖 ==========
# 检查 Cython 是否已安装
if ! python -c "import Cython" &>/dev/null; then
  echo "🐍 安装 Cython..."
  pip install Cython
else
  echo "✅ Cython 已安装，跳过"
fi

# 检查 pynini 是否已安装
if ! python -c "import pynini" &>/dev/null; then
  echo "🐍 安装 pynini..."
  pip install pynini==2.1.5
else
  echo "✅ pynini 已安装，跳过"
fi

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

# 从 requirements.txt 文件安装依赖
echo "🐍 检查并安装依赖..."
if [ -f "requirements.txt" ]; then
  # 读取requirements.txt并安装缺失的包
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 跳过空行和注释
    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi
    
    # 提取包名（移除版本信息）
    package=$(echo "$line" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | tr -d ' ')
    import_name=$(echo "$package" | tr '-' '_')
    
    # 检查包是否已安装
    if ! python -c "import $import_name" &>/dev/null; then
      echo "🐍 安装 $line..."
      pip install "$line"
    else
      echo "✅ $package 已安装，跳过"
    fi
  done < "requirements.txt"
else
  echo "⚠️ requirements.txt 文件不存在"
  exit 1
fi

# 检查 modelscope 是否已安装
if ! python -c "import modelscope" &>/dev/null; then
  echo "🐍 安装 modelscope CLI..."
  pip install modelscope
else
  echo "✅ modelscope 已安装，跳过"
fi

# ========== 5. 下载模型并拷贝 ==========
echo "🎯 处理模型文件..."
PRETRAINED_DIR="$COSY_DIR/pretrained_models/CosyVoice2-0.5B"
MODEL_COMMIT="9bd5b08fc085bd93d3f8edb16b67295606290350"
MODEL_ID="iic/CosyVoice2-0.5B"

if [ -d "$PRETRAINED_DIR" ]; then
  read -p "⚠️ 模型目录已存在，是否清理并重新下载？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    rm -rf "$PRETRAINED_DIR"
  else
    echo "✅ 跳过模型拷贝"
  fi
fi

if [ ! -d "$PRETRAINED_DIR" ]; then
  echo "📥 使用ModelScope CLI下载模型并切换到指定commit: $MODEL_COMMIT"
  mkdir -p "$PRETRAINED_DIR"
  
  # 使用modelscope CLI工具下载模型，最多重试3次
  MAX_RETRIES=3
  retry_count=0
  success=false

  while [ $retry_count -lt $MAX_RETRIES ] && [ "$success" != "true" ]; do
    if modelscope download $MODEL_ID --revision=$MODEL_COMMIT --target-dir="$PRETRAINED_DIR"; then
      success=true
      echo "✅ 模型下载成功！"
    else
      retry_count=$((retry_count+1))
      if [ $retry_count -lt $MAX_RETRIES ]; then
        echo "⚠️ 下载失败，等待10秒后进行第 $retry_count 次重试..."
        sleep 10
      else
        echo "❌ 多次尝试后仍然下载失败，请检查网络连接或手动下载模型。"
        exit 1
      fi
    fi
  done
  
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
echo "✅ 安装完成！你可以通过以下步骤启动服务："
echo "1. 激活conda环境: conda activate cosyvoice2"
echo "2. 进入服务目录: cd $COSY_DIR/async_cosyvoice/runtime/async_grpc"
echo "3. 启动服务: python3 server.py --load_jit --load_trt --fp16"

