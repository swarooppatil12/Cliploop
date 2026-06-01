#!/usr/bin/env python3
"""Wait for the three MDX-Net profile jobs and print a comparison table.

Reports per-backend on-device inference latency and the compute-unit breakdown
(how many layers landed on NPU/GPU/CPU — i.e. whether the model actually ran on
the requested accelerator or silently fell back to CPU).
"""
import qai_hub as hub

JOBS = {"GPU (Adreno)": "jp13exkk5", "NPU (Hexagon)": "jgd0olykp", "CPU": "jp48v011g"}
BASELINE_MS_PER_CALL = 1849.0  # on-device XNNPACK average (runs 1 & 2)


def summarize(profile):
    """Best-effort extraction across qai_hub schema versions."""
    out = {"inference_ms": None, "units": {}}
    es = profile.get("execution_summary", {}) if isinstance(profile, dict) else {}
    us = es.get("estimated_inference_time") or es.get("estimated_inference_time_us")
    if us:
        out["inference_ms"] = us / 1000.0
    # per-layer compute-unit histogram
    detail = profile.get("execution_detail") or profile.get("layer_details") or []
    for layer in detail:
        cu = (layer.get("compute_unit") or layer.get("computeUnit") or "?")
        out["units"][cu] = out["units"].get(cu, 0) + 1
    return out


print(f"baseline (on-device XNNPACK): {BASELINE_MS_PER_CALL:.0f} ms/call\n")
print(f"{'backend':<14}{'infer (ms)':>12}{'vs baseline':>13}  compute-units")
print("-" * 70)
for label, jid in JOBS.items():
    try:
        job = hub.get_job(jid)
        job.wait()
        prof = job.download_profile()
        s = summarize(prof)
        ms = s["inference_ms"]
        vs = f"{BASELINE_MS_PER_CALL/ms:.2f}x" if ms else "?"
        units = ", ".join(f"{k}:{v}" for k, v in sorted(s["units"].items())) or "n/a"
        ms_str = f"{ms:.1f}" if ms else "FAILED"
        print(f"{label:<14}{ms_str:>12}{vs:>13}  {units}")
    except Exception as e:  # noqa: BLE001
        print(f"{label:<14}{'ERROR':>12}{'':>13}  {e}")

print("\nNote: 'compute-units' shows where layers ran. Heavy CPU counts on the")
print("NPU/GPU jobs = fallback (the accelerator couldn't run those ops).")
