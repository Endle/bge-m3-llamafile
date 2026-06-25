# bge-m3.llamafile

A single self-contained [llamafile](https://github.com/Mozilla-Ocho/llamafile)
that serves [BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) embeddings
(1024-dim, multilingual) — the llama.cpp engine and the Q4_K_M weights in one
cross-platform executable.

This is the embedding backend for
[fireSeqSearch](https://github.com/Endle/fireSeqSearch): it ships a prebuilt
file so users don't have to compile anything to get embeddings. The weights are
converted, quantized, packaged, and smoke-tested entirely in CI, then published
to Releases with a SHA256 and build-provenance attestation.

## Usage

```sh
chmod +x bge-m3.llamafile
./bge-m3.llamafile --server --nobrowser   # OpenAI-compatible API on :8080
```

## Build

```sh
# fill the pins in versions.env first
bash scripts/build-llamafile.sh           # -> dist/bge-m3.llamafile
bash scripts/smoke-test.sh dist/bge-m3.llamafile
```

Or run the **Build bge-m3.llamafile** workflow (Actions tab): `dry_run: true`
for an inspectable artifact, `dry_run: false` + a `release_tag` to publish.
