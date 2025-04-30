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

# ========== 2. 安装/使用 Miniconda3 ==========
echo "🔍 检查是否已安装 Conda（Miniconda/Anaconda）..."

# 检查系统中是否已存在conda
if command -v conda &> /dev/null; then
  EXISTING_CONDA_PATH=$(conda info --base)
  echo "✅ 检测到系统中已安装Conda: $EXISTING_CONDA_PATH"
  read -p "⚠️ 是否使用已有的Conda安装？[Y/n] " use_existing
  
  if [[ "$use_existing" == [nN] ]]; then
    echo "📦 将安装新的Miniconda到指定位置..."
    INSTALL_NEW_CONDA=true
  else
    echo "✅ 使用已存在的Conda安装"
    MINICONDA_DIR="$EXISTING_CONDA_PATH"
    INSTALL_NEW_CONDA=false
  fi
else
  echo "📦 未检测到Conda安装，将安装新的Miniconda..."
  INSTALL_NEW_CONDA=true
fi

if [ "$INSTALL_NEW_CONDA" = true ]; then
  MINICONDA_DIR="$WORKSPACE/miniconda3"
  echo "📦 安装 Miniconda3 到 $MINICONDA_DIR..."
  
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
fi

# 设置Conda环境变量
echo "📦 配置Conda环境..."
export PATH="$MINICONDA_DIR/bin:$PATH"
. "$MINICONDA_DIR/etc/profile.d/conda.sh"

# 检查并创建cosyvoice2环境
if conda info --envs | grep -q "cosyvoice2"; then
  read -p "⚠️ 检测到conda环境 'cosyvoice2' 已存在，是否重新创建？[y/N] " confirm
  if [[ "$confirm" == [yY] ]]; then
    echo "🔄 正在删除并重新创建cosyvoice2环境..."
    conda remove -y --name cosyvoice2 --all
    conda create -y -n cosyvoice2 python=3.10
  else
    echo "✅ 使用现有的cosyvoice2环境"
  fi
else
  echo "🐍 创建 cosyvoice2 conda 环境..."
  conda create -y -n cosyvoice2 python=3.10
fi

# 激活cosyvoice2环境
echo "🐍 正在激活 cosyvoice2 环境..."
conda activate cosyvoice2

# 检查环境是否成功激活
if [[ "$CONDA_DEFAULT_ENV" == "cosyvoice2" ]]; then
  echo "✅ 已成功激活 cosyvoice2 环境"
else
  echo "❌ 环境激活失败，当前环境为: $CONDA_DEFAULT_ENV"
  echo "请尝试手动激活环境: conda activate cosyvoice2"
  exit 1
fi

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
  pip install --upgrade Cython
else
  echo "✅ Cython 已安装，跳过"
fi

# 检查 pynini 是否已安装
if ! python -c "import pynini" &>/dev/null; then
  echo "🐍 安装 pynini..."
  pip install --upgrade pynini==2.1.5
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
echo "🐍 安装 Python 依赖..."
if [ -f "requirements.txt" ]; then
  # 使用 --upgrade 参数，仅在需要时更新包，避免重复下载
  pip install --upgrade -r requirements.txt
else
  echo "⚠️ requirements.txt 文件不存在"
  exit 1
fi

# 检查 modelscope 是否已安装
if ! python -c "import modelscope" &>/dev/null; then
  echo "🐍 安装 modelscope CLI..."
  pip install --upgrade modelscope
else
  echo "✅ modelscope 已安装，跳过"
fi

# ========== 5. 下载模型并拷贝 ==========
echo "🎯 处理模型文件..."
PRETRAINED_DIR="$COSY_DIR/pretrained_models/CosyVoice2-0.5B"
MODEL_REPO="https://www.modelscope.cn/iic/CosyVoice2-0.5B.git"
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
  echo "📥 使用Git LFS下载模型并切换到指定commit: $MODEL_COMMIT"
  mkdir -p "$PRETRAINED_DIR"
  
  # 执行内存优化: 配置Git LFS使用更少的内存
  git config --global lfs.concurrenttransfers 1
  git config --global lfs.fetchrecentrefsdays 1
  git config --global lfs.fetchrecentcommitsdays 1
  
  # 直接克隆到目标目录
  echo "📥 步骤1: 浅克隆仓库..."
  if git clone --depth 1 "$MODEL_REPO" "$PRETRAINED_DIR"; then
    cd "$PRETRAINED_DIR"
    
    echo "📥 步骤2: checkout指定提交..."
    git checkout "$MODEL_COMMIT"
    
    echo "📥 步骤3: 拉取LFS文件..."
    git lfs pull
    
    cd - > /dev/null
    
    echo "✅ 模型下载和安装成功！"
  else
    echo "❌ 克隆失败，请检查网络连接或手动下载模型。"
    exit 1
  fi
  
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

