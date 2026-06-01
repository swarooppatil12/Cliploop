#!/usr/bin/env python3
"""
Profile UVR_MDXNET_9482.onnx on real Qualcomm hardware via Qualcomm AI Hub.

GOAL
----
Before investing in a forked flutter_onnxruntime + QNN-enabled AAR, answer one
question with real numbers: does the QNN *GPU (Adreno)* backend run the UVR
MDX-Net model materially faster than the current CPU/XNNPACK path?

This script submits profiling jobs to Qualcomm AI Hub (their cloud device farm)
for the same ONNX the app downloads at runtime, across three execution paths:

    1. cpu  -> ONNX Runtime CPU EP            (floor / sanity baseline)
    2. gpu  -> ONNX Runtime QNN EP, GPU backend (the candidate; float, no quant)
    3. htp  -> ONNX Runtime QNN EP, HTP/NPU     (only meaningful if quantized;
                                                 included for contrast, expect
                                                 fallback-to-CPU on this fp model)

It prints the on-device inference latency for each so you can compare against
the per-chunk `ms/call` you captured from the in-app [UVR][timing] logs.

WHY AI HUB (and not a local device)
-----------------------------------
The QNN GPU backend is only reachable through a QNN-enabled ORT build that is
NOT in the stock `onnxruntime-android` AAR the plugin ships. AI Hub lets us get
real Adreno latency WITHOUT first building that AAR or owning a Snapdragon phone.

PREREQUISITES
-------------
    pip install qai-hub
    qai-hub configure --api_token <YOUR_TOKEN>   # from https://aihub.qualcomm.com (free signup)

USAGE
-----
    python profile_uvr_qnn.py                       # default device + all 3 paths
    python profile_uvr_qnn.py --device "Snapdragon 8 Elite QRD"
    python profile_uvr_qnn.py --paths cpu gpu       # skip htp
    python profile_uvr_qnn.py --model /path/to/UVR_MDXNET_9482.onnx

NOTE ON BACKEND-SELECTION FLAGS
-------------------------------
AI Hub's ONNX+QNN profiling is configured via the `options` string passed to
submit_profile_job. The documented selector is `--onnx_execution_providers=qnn`.
GPU-vs-HTP backend selection inside the QNN EP is evolving (the GPU backend is a
2025 preview), so the exact passthrough flag may change. The OPTIONS_* values
below are the current best-known form; if a job errors on an unknown option,
check `https://app.aihub.qualcomm.com/docs/hub/profile_examples.html` for the
current QNN options syntax and update the constants — the rest of the script is
backend-agnostic.
"""

import argparse
import os
import sys
import urllib.request

MODEL_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "source-separation-models/UVR_MDXNET_9482.onnx"
)
DEFAULT_MODEL = "UVR_MDXNET_9482.onnx"

# A recent, widely-available Adreno device. Override with --device.
DEFAULT_DEVICE = "Snapdragon 8 Elite QRD"

# AI Hub profile `options` strings per execution path.
# See the docstring note: verify these against current AI Hub docs if a job
# rejects an option.
OPTIONS_CPU = "--onnx_execution_providers=cpu"
OPTIONS_GPU = (
    "--onnx_execution_providers=qnn "
    "--qnn_options backend_type=gpu"
)
OPTIONS_HTP = (
    "--onnx_execution_providers=qnn "
    "--qnn_options backend_type=htp"
)

PATH_OPTIONS = {"cpu": OPTIONS_CPU, "gpu": OPTIONS_GPU, "htp": OPTIONS_HTP}


def ensure_model(path: str) -> str:
    if os.path.exists(path):
        print(f"[model] using existing {path}")
        return path
    print(f"[model] downloading {MODEL_URL}")
    urllib.request.urlretrieve(MODEL_URL, path)
    size_mb = os.path.getsize(path) / 1e6
    print(f"[model] saved {path} ({size_mb:.1f} MB)")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description="Profile UVR MDX-Net on AI Hub via QNN.")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--device", default=DEFAULT_DEVICE)
    ap.add_argument(
        "--paths",
        nargs="+",
        choices=list(PATH_OPTIONS.keys()),
        default=["cpu", "gpu", "htp"],
        help="Which execution paths to profile.",
    )
    args = ap.parse_args()

    try:
        import qai_hub as hub
    except ImportError:
        print("ERROR: qai-hub not installed.  pip install qai-hub", file=sys.stderr)
        return 1

    model_path = ensure_model(args.model)
    device = hub.Device(args.device)
    print(f"[device] {args.device}")

    jobs = {}
    for path in args.paths:
        options = PATH_OPTIONS[path]
        print(f"\n[submit] path={path}  options='{options}'")
        jobs[path] = hub.submit_profile_job(
            model=model_path,
            device=device,
            options=options,
            name=f"uvr-mdxnet-{path}",
        )
        print(f"[submit] path={path}  -> {jobs[path].url}")

    print("\n[wait] downloading results (this blocks until jobs finish)...\n")
    print(f"{'path':<6} {'inference (ms)':>16}  {'notes'}")
    print("-" * 60)
    for path, job in jobs.items():
        try:
            job.wait()
            profile = job.download_profile()
            # AI Hub profile dict: execution summary holds per-inference latency
            # in microseconds. Key path is stable across recent API versions.
            exec_summary = profile["execution_summary"]
            us = exec_summary["estimated_inference_time"]
            ms = us / 1000.0
            # Flag whether ops actually landed on the requested unit (HTP on an
            # un-quantized model typically reports heavy CPU fallback here).
            note = exec_summary.get("compute_unit_breakdown", "")
            print(f"{path:<6} {ms:>16.2f}  {note}")
        except Exception as e:  # noqa: BLE001 - want to see partial results
            print(f"{path:<6} {'FAILED':>16}  {e}")

    print(
        "\nCompare 'gpu' inference(ms) against the per-chunk ms/call from the "
        "in-app [UVR][timing] log.\nIf GPU << XNNPACK ms/call, the Adreno path "
        "is worth the plugin/AAR work. If not, stop here."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
