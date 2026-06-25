#!/usr/bin/env bash
# Build bge-m3.llamafile from the original BAAI/bge-m3 weights.
#
# Full chain, all from pins in versions.env:
#   BAAI/bge-m3 (HF) --convert--> f16 GGUF --quantize--> Q4_K_M GGUF
#                                                    |
#                          llamafile runner + .args --+--zipalign--> bge-m3.llamafile
#
# Reproducible locally: `bash scripts/build-llamafile.sh`. The GitHub Action
# runs this exact script, so CI and a local build produce the same artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/versions.env"

WORK="${ROOT}/.work"
DIST="${ROOT}/dist"
mkdir -p "${WORK}" "${DIST}"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "${BGE_M3_HF_REVISION}"  == REPLACE_ME* ]] && die "pin BGE_M3_HF_REVISION in versions.env"
[[ "${LLAMA_CPP_COMMIT}"    == REPLACE_ME* ]] && die "pin LLAMA_CPP_COMMIT in versions.env"
[[ "${LLAMAFILE_VERSION}"   == REPLACE_ME* ]] && die "pin LLAMAFILE_VERSION in versions.env"

# Verify a file's SHA256 against an expected value. Empty expected => print only
# (trust-on-first-use bootstrap; copy the printed hash into versions.env).
verify_sha256() {
  local file="$1" expected="$2" name="$3" actual
  actual="$(sha256sum "${file}" | awk '{print $1}')"
  if [[ -z "${expected}" ]]; then
    echo ">> ${name} SHA256 (unpinned, copy into versions.env): ${actual}"
  elif [[ "${actual}" != "${expected}" ]]; then
    die "${name} SHA256 mismatch: got ${actual}, expected ${expected}"
  else
    echo ">> ${name} SHA256 OK: ${actual}"
  fi
}

echo "== [1/6] llama.cpp @ ${LLAMA_CPP_COMMIT} =="
LCPP="${WORK}/llama.cpp"
if [[ ! -d "${LCPP}/.git" ]]; then
  git clone "${LLAMA_CPP_REPO}" "${LCPP}"
fi
git -C "${LCPP}" fetch --depth=1 origin "${LLAMA_CPP_COMMIT}"
git -C "${LCPP}" checkout -q "${LLAMA_CPP_COMMIT}"

echo "== [2/6] build llama-quantize =="
cmake -S "${LCPP}" -B "${LCPP}/build" -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF >/dev/null
cmake --build "${LCPP}/build" -j"$(nproc)" --target llama-quantize
QUANTIZE_BIN="$(find "${LCPP}/build" -name 'llama-quantize' -type f | head -n1)"
[[ -x "${QUANTIZE_BIN}" ]] || die "llama-quantize not built"

echo "== [3/6] download BAAI/bge-m3 @ ${BGE_M3_HF_REVISION} =="
python3 -m pip install -q --upgrade "huggingface_hub[cli]"
python3 -m pip install -q -r "${LCPP}/requirements/requirements-convert_hf_to_gguf.txt"
MODEL_SRC="${WORK}/bge-m3-src"
huggingface-cli download "${BGE_M3_HF_REPO}" \
  --revision "${BGE_M3_HF_REVISION}" \
  --local-dir "${MODEL_SRC}"

echo "== [4/6] convert -> f16 GGUF -> ${QUANT} GGUF =="
F16_GGUF="${WORK}/bge-m3-f16.gguf"
Q_GGUF="${WORK}/bge-m3-${QUANT}.gguf"
python3 "${LCPP}/convert_hf_to_gguf.py" "${MODEL_SRC}" \
  --outfile "${F16_GGUF}" --outtype f16
"${QUANTIZE_BIN}" "${F16_GGUF}" "${Q_GGUF}" "${QUANT}"

echo "== [5/6] fetch llamafile runner + zipalign @ ${LLAMAFILE_VERSION} =="
BASE="https://github.com/${LLAMAFILE_REPO}/releases/download/${LLAMAFILE_VERSION}"
LLAMAFILE_BIN="${WORK}/llamafile-${LLAMAFILE_VERSION}"
ZIPALIGN_BIN="${WORK}/zipalign-${LLAMAFILE_VERSION}"
curl -fSL "${BASE}/llamafile-${LLAMAFILE_VERSION}" -o "${LLAMAFILE_BIN}"
curl -fSL "${BASE}/zipalign-${LLAMAFILE_VERSION}"  -o "${ZIPALIGN_BIN}"
verify_sha256 "${LLAMAFILE_BIN}" "${LLAMAFILE_SHA256}" "llamafile"
verify_sha256 "${ZIPALIGN_BIN}"  "${ZIPALIGN_SHA256}"  "zipalign"
chmod +x "${LLAMAFILE_BIN}" "${ZIPALIGN_BIN}"

echo "== [6/6] package -> ${DIST}/${OUTPUT_NAME} =="
OUT="${DIST}/${OUTPUT_NAME}"
cp "${LLAMAFILE_BIN}" "${OUT}"
# -j0 stores the GGUF uncompressed and page-aligned so llamafile mmaps it
# instead of copying ~438 MB into RAM. Order matters: weights then .args.
"${ZIPALIGN_BIN}" -j0 "${OUT}" "${Q_GGUF}" "${ROOT}/.args"
chmod +x "${OUT}"

sha256sum "${OUT}" | awk '{print $1}' > "${OUT}.sha256"
echo
echo "Built ${OUT}"
echo "  size:   $(du -h "${OUT}" | awk '{print $1}')"
echo "  sha256: $(cat "${OUT}.sha256")"
