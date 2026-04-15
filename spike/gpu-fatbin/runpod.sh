#!/usr/bin/env bash
# Path B validation: prove an sm_80-built .node runs on a different-arch NVIDIA GPU
# via NVIDIA driver PTX JIT. Run this on a RunPod H100 (or any non-sm_80) instance.
#
# Usage (browser terminal):
#   bash runpod.sh 2>&1 | tee /workspace/runpod.log
#
# Results land in /workspace/results/ — scp them back or cat them before destroying the pod.

set -uo pipefail  # no -e: we want to keep going past individual failures to collect all data

REPO_URL="${REPO_URL:-https://github.com/codetalcott/napi-mojo.git}"
BRANCH="${BRANCH:-spike/gpu-fatbin}"
WORKDIR="${WORKDIR:-/workspace/napi-mojo}"
RESULTS="/workspace/results"
mkdir -p "$RESULTS"

banner() { printf '\n===== %s =====\n' "$*"; }

banner "0. GPU info (confirm we are NOT on sm_80)"
nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv | tee "$RESULTS/gpu-info.txt"
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d ' .')
echo "Detected compute_cap: $GPU_CC (expect 90 for H100, 89 for L4/4090, NOT 80)"
if [ "$GPU_CC" = "80" ]; then
  echo "WARNING: running on sm_80 — this does not test forward-compat JIT. Continuing anyway."
fi

banner "1. Install pixi (if missing)"
if ! command -v pixi >/dev/null 2>&1; then
  curl -fsSL https://pixi.sh/install.sh | bash
  export PATH="$HOME/.pixi/bin:$PATH"
fi
pixi --version

banner "2. Install Node.js 20 (if missing)"
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -c2-3)" -lt 18 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

banner "3. Clone / update repo"
if [ -d "$WORKDIR/.git" ]; then
  cd "$WORKDIR" && git fetch origin && git checkout "$BRANCH" && git pull
else
  git clone --branch "$BRANCH" "$REPO_URL" "$WORKDIR"
  cd "$WORKDIR"
fi

banner "4. pixi install (downloads MAX — expect 3-5 min)"
pixi install 2>&1 | tail -20

banner "5a. Build GPU addon for sm_80 (Path B test target)"
rm -f build/gpu.node
NAPI_MOJO_GPU_ACCEL="--target-accelerator sm_80" pixi run bash build.sh 2>&1 | tail -20
if [ ! -f build/gpu.node ]; then
  echo "FAIL: sm_80 build produced no build/gpu.node — aborting"
  exit 1
fi
cp build/gpu.node "$RESULTS/gpu.sm80.node"

banner "5b. Verify PTX-text embedding on Linux (should match macOS result: 3 modules, target sm_80)"
{
  echo "target markers: $(strings build/gpu.node | grep -cE '^\.target sm_80')"
  echo "version markers: $(strings build/gpu.node | grep -cE '^\.version [0-9]')"
  echo "cubin/fatbin markers: $(strings build/gpu.node | grep -ciE 'nv_fatbin|ELFCUDA|__nv_module')"
  echo "binary size: $(wc -c < build/gpu.node) bytes"
  echo "kernels:"
  strings build/gpu.node | grep -E '^\.visible \.entry|^\.entry ' | head -10
} | tee "$RESULTS/ptx-inspection-sm80.txt"

banner "5c. ldd (Question 2 data — MAX runtime deps)"
ldd build/gpu.node 2>&1 | tee "$RESULTS/ldd-sm80.txt"

banner "6. npm install + run GPU tests (Path B end-to-end)"
npm ci 2>&1 | tail -5
# Clear CUDA JIT cache so we measure first-load JIT latency, not a warm run
rm -rf "$HOME/.nv/ComputeCache" 2>/dev/null || true
START=$(date +%s%N)
npm test -- tests/gpu-matmul.test.js 2>&1 | tee "$RESULTS/test-sm80-cold.log"
SM80_COLD_EXIT=${PIPESTATUS[0]}
SM80_COLD_NS=$(( $(date +%s%N) - START ))
echo "sm_80 cold run exit=$SM80_COLD_EXIT total_ms=$(( SM80_COLD_NS / 1000000 ))" | tee -a "$RESULTS/timings.txt"

# Warm run (JIT cache populated) — shows per-kernel steady-state
START=$(date +%s%N)
npm test -- tests/gpu-matmul.test.js 2>&1 | tee "$RESULTS/test-sm80-warm.log" >/dev/null
SM80_WARM_EXIT=${PIPESTATUS[0]}
SM80_WARM_NS=$(( $(date +%s%N) - START ))
echo "sm_80 warm run exit=$SM80_WARM_EXIT total_ms=$(( SM80_WARM_NS / 1000000 ))" | tee -a "$RESULTS/timings.txt"

banner "7a. Build native sm_90 for perf comparison (skip if not on Hopper+)"
if [ "$GPU_CC" -ge 90 ]; then
  rm -f build/gpu.node
  NAPI_MOJO_GPU_ACCEL="--target-accelerator sm_90" pixi run bash build.sh 2>&1 | tail -20
  if [ -f build/gpu.node ]; then
    cp build/gpu.node "$RESULTS/gpu.sm90.node"
    rm -rf "$HOME/.nv/ComputeCache" 2>/dev/null || true
    START=$(date +%s%N)
    npm test -- tests/gpu-matmul.test.js 2>&1 | tee "$RESULTS/test-sm90-warm.log" >/dev/null
    SM90_WARM_EXIT=${PIPESTATUS[0]}
    SM90_WARM_NS=$(( $(date +%s%N) - START ))
    echo "sm_90 warm run exit=$SM90_WARM_EXIT total_ms=$(( SM90_WARM_NS / 1000000 ))" | tee -a "$RESULTS/timings.txt"
  fi
else
  echo "skipped — GPU is sm_${GPU_CC}, not sm_90+"
fi

banner "7b. Build generic cuda target (Path C probe) — may be slow"
rm -f build/gpu.node
timeout 900 bash -c 'NAPI_MOJO_GPU_ACCEL="--target-accelerator cuda" pixi run bash build.sh' 2>&1 | tail -10 | tee "$RESULTS/path-c-build.log"
if [ -f build/gpu.node ]; then
  cp build/gpu.node "$RESULTS/gpu.cuda.node"
  strings build/gpu.node | grep -cE '^\.target sm_' | tee "$RESULTS/path-c-targets.txt"
  strings build/gpu.node | grep -E '^\.target sm_' | sort -u | tee -a "$RESULTS/path-c-targets.txt"
  npm test -- tests/gpu-matmul.test.js 2>&1 | tee "$RESULTS/test-cuda.log" >/dev/null
  echo "cuda generic test exit=${PIPESTATUS[0]}" | tee -a "$RESULTS/timings.txt"
else
  echo "Path C build did not complete within 15 min — skipping test" | tee -a "$RESULTS/timings.txt"
fi

banner "8. Summary"
{
  echo "=== Path B validation summary ==="
  echo "GPU: $(cat $RESULTS/gpu-info.txt | tail -1)"
  echo
  echo "PTX inspection (sm_80 Linux build):"
  cat "$RESULTS/ptx-inspection-sm80.txt"
  echo
  echo "Timings:"
  cat "$RESULTS/timings.txt"
  echo
  echo "Verdict:"
  if [ "${SM80_COLD_EXIT:-1}" = "0" ]; then
    echo "  PASS — sm_80 PTX JIT works on sm_$GPU_CC. Path B viable."
  else
    echo "  FAIL — sm_80 PTX did not run on sm_$GPU_CC. Check test-sm80-cold.log."
  fi
} | tee "$RESULTS/SUMMARY.txt"

echo
echo "All artifacts in $RESULTS — copy them out before destroying the pod:"
ls -la "$RESULTS"
