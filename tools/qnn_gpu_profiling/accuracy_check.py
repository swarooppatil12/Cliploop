#!/usr/bin/env python3
"""Accuracy check: does the NPU (reduced-precision) MDX-Net match FP32?

Generates a realistic music-like STFT input matching the app's layout
([1,4,2048,256] = batch, [L.re,L.im,R.re,R.im], freq, time; nFFT=4096, hop=1024),
runs it through the NPU and CPU models on AI Hub, and reports the numerical
error between them. Small error => section detection (which only needs vocal
presence) is safe under NPU precision.
"""
import numpy as np
import qai_hub as hub

MODEL = "UVR_MDXNET_9482_b1.onnx"
SR, NFFT, HOP, DIMF, DIMT = 44100, 4096, 1024, 2048, 256
CHUNK = HOP * (DIMT - 1)  # 261120 samples (~5.9s) -> exactly 256 frames


def make_channel(seed):
    rng = np.random.default_rng(seed)
    t = np.arange(CHUNK) / SR
    sig = np.zeros(CHUNK)
    f0 = 110.0
    for k in range(1, 9):                       # harmonic "instrument"
        sig += (1.0 / k) * np.sin(2 * np.pi * f0 * k * t + rng.uniform(0, 2 * np.pi))
    sig *= (0.5 + 0.5 * np.sin(2 * np.pi * 2.0 * t))   # tremolo
    sig += 0.05 * rng.standard_normal(CHUNK)           # noise bed
    sig /= np.max(np.abs(sig)) + 1e-9
    return sig.astype(np.float32)


def stft(x):
    win = np.hanning(NFFT).astype(np.float32)
    xp = np.pad(x, (NFFT // 2, NFFT // 2), mode="reflect")
    frames = [np.fft.rfft(xp[i * HOP:i * HOP + NFFT] * win, n=NFFT)[:DIMF]
              for i in range(DIMT)]
    return np.stack(frames, axis=1)             # [DIMF, DIMT] complex


print("generating realistic STFT input [1,4,2048,256] ...")
L, R = make_channel(1), make_channel(2)
FL, FR = stft(L), stft(R)
inp = np.zeros((1, 4, DIMF, DIMT), dtype=np.float32)
inp[0, 0], inp[0, 1] = FL.real, FL.imag
inp[0, 2], inp[0, 3] = FR.real, FR.imag
print(f"  input range [{inp.min():.3f}, {inp.max():.3f}], std {inp.std():.4f}")

dev = hub.Device("Snapdragon 8 Elite Gen 5 QRD", os="16")
print("submitting NPU + CPU inference jobs ...")
npu = hub.submit_inference_job(model=MODEL, device=dev, inputs={"input": [inp]},
                               name="mdx-acc-npu", options="--compute_unit npu")
cpu = hub.submit_inference_job(model=MODEL, device=dev, inputs={"input": [inp]},
                               name="mdx-acc-cpu", options="--compute_unit cpu")
print(f"  NPU {npu.job_id}  |  CPU {cpu.job_id}")

npu.wait(); cpu.wait()
on = npu.download_output_data()
oc = cpu.download_output_data()
key = list(oc.keys())[0]
ref = np.asarray(oc[key][0], dtype=np.float64)   # FP32 reference
tst = np.asarray(on[key][0], dtype=np.float64)   # NPU output

err = tst - ref
mae = np.mean(np.abs(err))
maxe = np.max(np.abs(err))
rel = np.linalg.norm(err) / (np.linalg.norm(ref) + 1e-12)
sdr = 10 * np.log10(np.sum(ref ** 2) / (np.sum(err ** 2) + 1e-12))

print("\n================ ACCURACY: NPU vs FP32(CPU) ================")
print(f"output shape         : {ref.shape}")
print(f"reference range      : [{ref.min():.4f}, {ref.max():.4f}], std {ref.std():.4f}")
print(f"mean abs error       : {mae:.6f}")
print(f"max  abs error       : {maxe:.6f}")
print(f"relative L2 error    : {rel*100:.2f}%")
print(f"SDR (output vs ref)  : {sdr:.1f} dB   (higher=closer; >20dB usually inaudible-grade)")
print("===========================================================")
print("For section detection (vocal-presence), even ~15-25 dB SDR on the")
print("separated spectrogram is typically plenty. Validate end-to-end on device.")
