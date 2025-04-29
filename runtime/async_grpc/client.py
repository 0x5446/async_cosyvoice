import os
import sys
import asyncio
import time
import numpy as np
import soundfile as sf
import librosa

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(f'{ROOT_DIR}/../../..')
sys.path.append(f'{ROOT_DIR}/../../../third_party/Matcha-TTS')
import logging
import argparse
import cosyvoice_pb2
import cosyvoice_pb2_grpc
import grpc
from grpc import aio

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)

def load_wav(wav_path: str, target_sr: int) -> np.ndarray:
    """使用 soundfile 替代 torchaudio 加载音频"""
    try:
        data, sample_rate = sf.read(wav_path, dtype='float32')
        # 多声道转单声道
        if len(data.shape) > 1:
            data = np.mean(data, axis=1)
        # 重采样
        if sample_rate != target_sr:
            data = librosa.resample(
                data,
                orig_sr=sample_rate,
                target_sr=target_sr
            )
        # 添加 batch 维度 (1, samples)
        return data.reshape(1, -1)
    except Exception as e:
        logging.error(f"Error loading {wav_path}: {str(e)}")
        raise

def convert_audio_bytes_to_ndarray(raw_audio: bytes, format: str = None) -> np.ndarray:
    """字节转 numpy 数组"""
    if not format:
        return np.frombuffer(raw_audio, dtype=np.float32).reshape(1, -1)
    elif format in {'pcm'}:
        return np.frombuffer(raw_audio, dtype=np.int16).reshape(1, -1)
    else:
        raise ValueError(f"Unsupported format: {format}")

def convert_audio_ndarray_to_bytes(array: np.ndarray) -> bytes:
    """numpy 数组转字节"""
    return array.astype(np.float32).tobytes()

def construct_request(args, tts_text):
    request = cosyvoice_pb2.Request()
    request.tts_text = tts_text
    request.stream = args.stream
    request.speed = args.speed
    request.text_frontend = args.text_frontend

    request.format = args.format

    # 构造请求
    if args.mode == 'sft':
        logging.info('Constructing sft request')
        sft_request = request.sft_request
        sft_request.spk_id = args.spk_id
    elif args.mode == 'zero_shot':
        logging.info('Constructing zero_shot request')
        zero_shot_request = request.zero_shot_request
        zero_shot_request.prompt_text = args.prompt_text
        prompt_speech = load_wav(args.prompt_wav, 16000)
        zero_shot_request.prompt_audio = convert_audio_ndarray_to_bytes(prompt_speech)
    elif args.mode == 'cross_lingual':
        logging.info('Constructing cross_lingual request')
        cross_lingual_request = request.cross_lingual_request
        prompt_speech = load_wav(args.prompt_wav, 16000)
        cross_lingual_request.prompt_audio = convert_audio_ndarray_to_bytes(prompt_speech)
    elif args.mode == 'instruct2':
        logging.info('Constructing instruct request')
        instruct2_request = request.instruct2_request
        instruct2_request.instruct_text = args.instruct_text
        prompt_speech = load_wav(args.prompt_wav, 16000)
        instruct2_request.prompt_audio = convert_audio_ndarray_to_bytes(prompt_speech)
    elif args.mode == 'instruct2_by_spk_id':
        logging.info('Constructing instruct2_by_spk_id request')
        instruct2_by_spk_id_request = request.instruct2_by_spk_id_request
        instruct2_by_spk_id_request.instruct_text = args.instruct_text
        instruct2_by_spk_id_request.spk_id = args.spk_id
    else:
        logging.info('Constructing zero_shot_by_spk_id request')
        zero_shot_by_spk_id_request = request.zero_shot_by_spk_id_request
        zero_shot_by_spk_id_request.spk_id = args.spk_id
    return request


async def main(args):
    async with aio.insecure_channel(f"{args.host}:{args.port}") as channel:
        stub = cosyvoice_pb2_grpc.CosyVoiceStub(channel)

        # 异步流式接收响应
        try:
            start_time = time.time()
            last_time = start_time
            chunk_index = 0
            tts_audio = b''
            if args.stream_input:
                
                def text_generator(args):
                    yield construct_request(args, "")
                    for i,segment in enumerate(args.tts_text):
                        # 这里是为了模拟流式输入，每次发送一个 segment，一个segment可以是一个字符，也可以是一个句子
                        # 流式返回的情况下，需要等待接收一定的（至少5个）字符，服务端才能合成语音并返回首包
                        logging.info(f'Sending text segment: {segment}')
                        if i > 5:
                            # 模拟流式输入，等待一定时间
                            time.sleep(0.01)
                        request = cosyvoice_pb2.Request()
                        request.tts_text = segment
                        yield request

                response_stream = stub.StreamInference(text_generator(args))
            else:
                request = construct_request(args, args.tts_text)
                response_stream = stub.Inference(request)

            async for response in response_stream:
                tts_audio += response.tts_audio
                logging.info(f'Received audio chunk {len(response.tts_audio)} bytes, chunk index: {chunk_index},' +
                             f'cost {time.time() - last_time:.3f}s  all cost {time.time() - start_time:.3f}s ')

                last_time = time.time()
                chunk_index += 1

            # 音频后处理
            if args.format is None or args.format in {'', 'pcm'}:
                tts_array = convert_audio_bytes_to_ndarray(tts_audio, args.format)
                # 保存为 (samples, 1) 格式

                sf.write(
                    args.output_path,
                    tts_array.T,  # 转置为 (samples, 1)
                    args.target_sr
                )
                duration = tts_array.shape[1] / args.target_sr
                all_time = time.time() - start_time
                logging.info(f'Audio saved to {args.output_path} (duration: {duration:.2f}s) '+
                             f'cost {time.time() - last_time:.3f}s  all cost {all_time:.3f}s, rtf: {all_time / duration:.3f}')
            else:
                logging.error(f"Unsupported format: {args.format}")

        except grpc.RpcError as e:
            logging.error(f"RPC error occurred: {e.code()}: {e.details()}")
        except Exception as e:
            logging.error(f"Processing failed: {str(e)}", exc_info=True)


def run_async_main(args):
    asyncio.run(main(args))

from argparse import Namespace

from concurrent.futures import ProcessPoolExecutor, as_completed

def multiprocess_main(args):
    max_conc = args.max_conc
    
    all_text = []
    with open(args.input_file, 'r') as f:
        for line in f:
            line = line.strip()
            all_text.append(line) if line else None

    start_time = time.monotonic()
    os.makedirs(args.output_path, exist_ok=True)
    with ProcessPoolExecutor(max_workers=max_conc) as executor:
        requests = []
        for i, text in enumerate(all_text):
            clone_args = Namespace(**args.__dict__)
            clone_args.tts_text = text
            clone_args.output_path = f"{args.output_path}/{i}.wav"
            requests.append(clone_args)
            
        futures = [executor.submit(run_async_main, request) for request in requests]
        for future in as_completed(futures):
            future.result()
    logging.info(f"Total time: {time.monotonic() - start_time:.2f}s")

async def register_spk(args):
    async with aio.insecure_channel(f"{args.host}:{args.port}") as channel:
        stub = cosyvoice_pb2_grpc.CosyVoiceStub(channel)
        audio_data = load_wav(args.prompt_wav, 16000)
        audio_bytes, sr = convert_audio_ndarray_to_bytes(audio_data), 16000
        future = stub.RegisterSpk(cosyvoice_pb2.RegisterSpkRequest(spk_id=args.spk_id, prompt_text=args.prompt_text, prompt_audio_bytes=audio_bytes, ori_sample_rate=sr))
        response = await future
        logging.info(f"RegisterSpk response: {response}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', type=str, default='0.0.0.0')
    parser.add_argument('--port', type=int, default=50000)
    parser.add_argument('--mode', default='zero_shot_by_spk_id',
                        choices=['sft', 'zero_shot', 'cross_lingual', 'instruct2',
                                 'instruct2_by_spk_id', 'zero_shot_by_spk_id', 'register_spk'],
                        help='Request mode')
    parser.add_argument('--stream_input', action="store_true", help="是否流式输入，用于双工流式")
    parser.add_argument('--stream', action='store_true', help='是否流式输出')
    parser.add_argument('--speed', type=float, default=1.0, help='Speed up the audio')
    parser.add_argument('--text_frontend', type=bool, default=True, help='Text frontend mode')
    parser.add_argument('--tts_text', type=str, default='你好，我是通义千问语音合成大模型，请问有什么可以帮您的吗？')
    parser.add_argument('--spk_id', type=str, default='001')
    parser.add_argument('--prompt_text', type=str, default='希望你以后能够做的比我还好呦。')
    parser.add_argument('--prompt_wav', type=str, default='../../../asset/zero_shot_prompt.wav')
    parser.add_argument('--format', type=str, choices=['', 'pcm'],
                        default='', help='音频输出格式[mp3, wav, pcm]，pcm可用于流式输出，目前测试客户端只支持对【 原始float32格式、Int16位pcm格式】 的音频数据处理，其他格式需自行实现转换')
    parser.add_argument('--instruct_text', type=str, default='使用四川话说')
    parser.add_argument('--output_path', type=str, default='demo.wav', help='输出音频的文件名')
    parser.add_argument('--target_sr', type=int, default=24000, help='输出音频的目标采样率 cosyvoice2 为 24000')
    parser.add_argument('--max_conc', type=int, default=4, help='最大并发数')
    parser.add_argument('--input_file', type=str, default='', help='输入需要合成音频文本的文件路径，单行文本为一个语音合成请求，将并发合成音频，并通过--max_conc设置并发数')
    args = parser.parse_args()

    if args.mode == 'register_spk':
        asyncio.run(register_spk(args))
    else:
        if args.input_file:
            multiprocess_main(args)
        else:
            asyncio.run(main(args))

    # python client.py --mode zero_shot_by_spk_id --spk_id 001 --stream_input --tts_text 你好，请问有什么可以帮您的吗？ --stream
    # python client.py --mode zero_shot_by_spk_id --spk_id 001 --input_file text.txt --max_conc 10 --output_path output