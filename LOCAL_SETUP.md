# Qwen3.8-27B Uncensored local setup

The persistent archive lives under `D:\AI\Qwen3.8-27B-Uncensored` on the
TrueNAS iSCSI disk. Active models and llama.cpp are cached under
`C:\AI\Qwen3.8-27B-Uncensored` on the local NVMe.

The club may reset C: after a reboot. Restore or refresh the local cache with:

```powershell
powershell -ExecutionPolicy Bypass -File .\sync-models-to-local.ps1
```

Run only one model server at a time. Every launcher binds to localhost and uses
API key `local-qwen-key`. Defaults are a 16K context, Q8 KV cache, Flash
Attention, one concurrent slot, and automatic GPU-layer fitting.

## Recommended: OrcaRouter LowGPU IQ3XXXS

```powershell
powershell -ExecutionPolicy Bypass -File .\run-lowgpu-iq3.ps1
```

- Web UI: <http://127.0.0.1:8083>
- API base URL: `http://127.0.0.1:8083/v1`
- Model ID: `qwen38-27b-lowgpu-iq3`
- Provenance: `orcarouter/Qwen3.8-27B-Uncensored`

## Unleashed UD-Q2_K_XL

```powershell
powershell -ExecutionPolicy Bypass -File .\run-unleashed-q2.ps1
```

- Web UI: <http://127.0.0.1:8082>
- API base URL: `http://127.0.0.1:8082/v1`
- Model ID: `qwen38-27b-unleashed-q2`
- Provenance: `JonathanColetti/Qwen3.8-27B-Uncensored`

MTP is optional and is disabled by default because it was slower on a long
local test. To test it again:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-unleashed-q2.ps1 -Mtp
```

## Earlier FP8-derived quants

```powershell
powershell -ExecutionPolicy Bypass -File .\run-q2.ps1
powershell -ExecutionPolicy Bypass -File .\run-q4.ps1
```

- Q2: <http://127.0.0.1:8080>, model `qwen38-27b-q2`
- Q4: <http://127.0.0.1:8081>, model `qwen38-27b-q4`

Close GPU-heavy applications before starting a server. The 512 MiB target used
by the three small quants is fairly tight. If a model runs out of VRAM, increase
`--fit-target 512` to `1024`, or close the browser and other GPU applications.
