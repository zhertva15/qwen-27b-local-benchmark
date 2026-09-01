# Qwen3.8 optimization lab

This directory is isolated from the original launchers and reports. It contains
only reproducible optimization experiments for the four locally cached models.

## Layout

- `config/` — model inventory and benchmark profile matrix.
- `prompts/` — fixed prompts shared by every run.
- `scripts/` — orchestration and reporting scripts.
- `launchers/` — one configurable launcher for daily use of tested profiles.
- `results/raw/` — one JSON result per model/profile pair.
- `results/summary.csv` — flat metrics for quick comparison.
- `logs/server/` — llama-server stdout and stderr for each run.
- `report/` — the human-readable final report.

## Run the complete matrix

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-OptimizationMatrix.ps1
```

Run a subset while tuning:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-OptimizationMatrix.ps1 `
  -OnlyModel lowgpu-iq3 `
  -OnlyProfile baseline,q4kv,q4kv-ngram
```

The runner uses port 8090, binds only to `127.0.0.1`, and stops every server
before moving to the next case. Do not run another llama-server at the same time.

## Start a tested profile

Fast general coding with Unleashed MTP:

```powershell
powershell -ExecutionPolicy Bypass -File .\launchers\Start-Profile.ps1 `
  -ModelId unleashed-q2 -ProfileId q4kv-mtp -Port 8082
```

Safe general-purpose LowGPU profile:

```powershell
powershell -ExecutionPolicy Bypass -File .\launchers\Start-Profile.ps1 `
  -ModelId lowgpu-iq3 -ProfileId q4kv -Port 8083
```

For copy-heavy edits and refactors, replace `q4kv` with `q4kv-ngram`.
