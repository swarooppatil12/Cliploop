#!/usr/bin/env python3
"""Fetch MDX-Net NPU profiles across Snapdragon generations (reads .agejobs)."""
import qai_hub as hub

BASELINE = 1849.0
rows = []
with open(".agejobs") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        jid, name, tag = line.split("|")
        rows.append((tag, name, jid))

print(f"on-device CPU baseline (8 Elite Gen5): {BASELINE:.0f} ms/call")
print(f"reference: 8 Elite Gen5 NPU = ~42 ms/call\n")
print(f"{'generation':<12}{'device':<26}{'NPU ms':>9}{'vs CPU':>9}  layers (NPU/CPU)")
print("-" * 78)
for tag, name, jid in rows:
    try:
        job = hub.get_job(jid)
        job.wait()
        prof = job.download_profile()
        es = prof.get("execution_summary", {})
        us = es.get("estimated_inference_time")
        ms = us / 1000.0 if us else None
        det = prof.get("execution_detail", [])
        npu = sum(1 for L in det if (L.get("compute_unit") == "NPU"))
        cpu = sum(1 for L in det if (L.get("compute_unit") == "CPU"))
        gpu = sum(1 for L in det if (L.get("compute_unit") == "GPU"))
        vs = f"{BASELINE/ms:.1f}x" if ms else "?"
        mss = f"{ms:.1f}" if ms else "FAIL"
        units = f"{npu}/{cpu}" + (f" (+{gpu}gpu)" if gpu else "")
        print(f"{tag:<12}{name:<26}{mss:>9}{vs:>9}  {units}")
    except Exception as e:  # noqa: BLE001
        print(f"{tag:<12}{name:<26}{'ERROR':>9}{'':>9}  {str(e)[:30]}")

print("\nHigh NPU-layer count = ran on NPU. High CPU count = fallback (slower/")
print("less supported on that generation).")
