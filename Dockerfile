FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime
ENV DEBIAN_FRONTEND=noninteractive

# 代理配置
ARG http_proxy
ARG https_proxy
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}

WORKDIR /workspace

# 合并 apt 安装
RUN sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list && \
    apt-get update -y && \
    apt-get install -y git unzip git-lfs sox libsox-dev build-essential && \
    git lfs install

# 拉取特定分支
RUN git clone --branch dev/Comet --single-branch --recursive https://github.com/FunAudioLLM/CosyVoice.git

# 可选：用 pip 安装 pynini（更稳）
RUN pip install pynini==2.1.5

# 拉 async_cosyvoice 并安装依赖
RUN cd CosyVoice && \
    git clone https://github.com/0x5446/async_cosyvoice.git && \
    cd async_cosyvoice && \
    pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 下载模型指定 commit 并拷贝
RUN mkdir -p /workspace/CosyVoice/pretrained_models/CosyVoice2-0.5B && \
    cd /workspace/CosyVoice/pretrained_models && \
    git clone --no-checkout https://www.modelscope.cn/iic/CosyVoice2-0.5B.git && \
    cd CosyVoice2-0.5B && \
    git checkout 9bd5b08fc085bd93d3f8edb16b67295606290350 && \
    git lfs pull && \
    cp /workspace/CosyVoice/async_cosyvoice/CosyVoice2-0.5B/* /workspace/CosyVoice/pretrained_models/CosyVoice2-0.5B/

# 设置最终运行目录并生成 gRPC 代码及启动服务
WORKDIR /workspace/CosyVoice/async_cosyvoice/runtime/async_grpc
CMD bash -c "python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. cosyvoice.proto && python server.py --load_jit --load_trt --fp16"
