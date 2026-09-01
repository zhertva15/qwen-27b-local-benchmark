# mini-swe-benchmark

Возобновляемое сравнение трёх локальных Qwen3.8-27B через официальный
mini-swe-agent и штатный SWE-bench evaluator. Собственного agent loop и собственной
логики определения `resolved` здесь нет.

## Быстрый запуск

Открыть PowerShell от администратора в этой директории и выполнить:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Setup-Environment.ps1
```

После первого включения WSL/VirtualMachinePlatform Windows нужно перезагрузить.
Затем:

```powershell
.\scripts\Prepare-GoldPreflight.ps1
.\scripts\Run-Smoke.ps1
.\scripts\Run-Benchmark.ps1
```

`Run-Benchmark.ps1` можно запускать повторно: готовые `attempt.json` пропускаются.
Лимит серии — шесть часов накопленного времени. Финальные файлы:

- `REPORT.md` — русский отчёт;
- `results/attempts.csv` — одна строка на попытку;
- `results/attempts/` — trajectories, patches и evaluator logs;
- `results/gold-preflight.json` — проверка gold patches;
- `results/smoke-summary.json` — незачётный smoke-test.

## Структура

```text
mini-swe-benchmark/
├── config/
│   ├── models/          # отдельный LiteLLM YAML на модель
│   ├── seeds/           # seed 101 и 202
│   ├── agent-limits.yaml
│   ├── run-plan.json
│   ├── server-profiles.json
│   └── tasks.json
├── scripts/             # только оркестрация готовых CLI
├── state/               # resume state и выбранные после gold задачи
├── logs/server/         # cold-load и llama-server logs
├── results/
│   ├── attempts/
│   ├── preflight/
│   └── smoke/
├── REPORT.md
└── requirements.lock.txt
```

Контейнер агента работает с `--network none`. Один worker и новый `--rm` контейнер
на каждую задачу обеспечивают чистый checkout. Траектории читаются штатным viewer:

```powershell
.\.venv\Scripts\mini-extra.exe inspect .\results\attempts
```

Для ручного запуска/остановки конкретного сервера:

```powershell
.\scripts\Start-Model.ps1 -Model direct-iq4-xs -Seed 101
.\scripts\Stop-Model.ps1
```

