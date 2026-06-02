#!/usr/bin/env python3
"""Wait for the ONNX->TFLite compile job, download the .tflite, profile on NPU."""
import qai_hub as hub

COMPILE_JOB = "jgl7k0dm5"
BASELINE = 1849.0

cj = hub.get_job(COMPILE_JOB)
print("waiting for compile job ...")
cj.wait()
print("compile status:", cj.get_status())
m = cj.get_target_model()
if m is None:
    print("ERROR: no target model (compile failed)"); raise SystemExit(1)
m.download("UVR_MDXNET_9482.tflite")
print("downloaded UVR_MDXNET_9482.tflite")

dev = hub.Device("Snapdragon 8 Elite Gen 5 QRD", os="16")
print("submitting NPU profile of the TFLite model ...")
pj = hub.submit_profile_job(model=m, device=dev, options="--compute_unit npu",
                            name="mdxnet-tflite-npu")
print("profile job:", pj.job_id)
pj.wait()
prof = pj.download_profile()
es = prof.get("execution_summary", {})
us = es.get("estimated_inference_time")
ms = us / 1000.0 if us else None
det = prof.get("execution_detail", [])
npu = sum(1 for L in det if L.get("compute_unit") == "NPU")
cpu = sum(1 for L in det if L.get("compute_unit") == "CPU")
gpu = sum(1 for L in det if L.get("compute_unit") == "GPU")
print("\n================ TFLite on NPU ================")
print(f"inference: {ms:.1f} ms/call" if ms else "inference: ?")
if ms:
    print(f"vs CPU baseline: {BASELINE/ms:.1f}x")
print(f"layers  NPU:{npu}  CPU:{cpu}  GPU:{gpu}")
print("===============================================")
