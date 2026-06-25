#!/usr/bin/env bash
# Prove the built artifact actually serves bge-m3 embeddings before it ships.
# Launches it with the SAME invocation fireSeqSearch uses (process.rs) and
# asserts /v1/embeddings returns a 1024-dim vector.
set -euo pipefail

LLAMAFILE="${1:?usage: smoke-test.sh <path-to.llamafile>}"
PORT="${PORT:-18080}"
URL="http://127.0.0.1:${PORT}"

# .llamafile is an APE binary; on Linux the kernel may refuse direct exec, so
# launch via sh — the file's shell prelude bootstraps it (matches process.rs).
sh "${LLAMAFILE}" --server --port "${PORT}" --nobrowser \
  --embedding -ub 8192 -b 8192 -c 8192 >/tmp/llamafile.smoke.log 2>&1 &
SERVER_PID=$!
cleanup() { kill "${SERVER_PID}" 2>/dev/null || true; wait "${SERVER_PID}" 2>/dev/null || true; }
trap cleanup EXIT

echo ">> waiting for ${URL}/health"
for _ in $(seq 1 120); do
  if curl -fsS "${URL}/health" >/dev/null 2>&1; then ready=1; break; fi
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "ERROR: llamafile exited during startup:" >&2; cat /tmp/llamafile.smoke.log >&2; exit 1
  fi
  sleep 1
done
[[ "${ready:-}" == 1 ]] || { echo "ERROR: server never became healthy" >&2; cat /tmp/llamafile.smoke.log >&2; exit 1; }

echo ">> POST ${URL}/v1/embeddings"
DIMS="$(curl -fsS "${URL}/v1/embeddings" \
  -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","input":"fireSeqSearch smoke test"}' \
  | jq '.data[0].embedding | length')"

echo ">> embedding dimension: ${DIMS}"
[[ "${DIMS}" == "1024" ]] || { echo "ERROR: expected 1024 dims, got ${DIMS}" >&2; exit 1; }
echo "SMOKE TEST PASSED"
