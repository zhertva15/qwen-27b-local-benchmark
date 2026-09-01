# Qwen3.8-27B local benchmark workspace

Полная рабочая история тестирования локальных Qwen3.8-27B на RTX 5070 12 GB:

- исходные Q2/Q4/LowGPU тесты и launchers;
- optimization matrix и первый отчёт;
- новый воспроизводимый mini-swe-agent + SWE-bench Verified benchmark;
- скрипты восстановления после очистки системного диска.

## Страховка перед перезагрузкой

Постоянный TrueNAS/iSCSI-диск:

```text
D:\Qwen_testr-backup\mini-swe-benchmark-full.zip
D:\Qwen_testr-backup\mini-swe-benchmark\
D:\Qwen_testr-backup\models\orcarouter_Qwen3.8-27B-Uncensored-IQ4_XS.gguf
```

Если диск C: пережил перезагрузку, продолжить можно из текущей директории.
Если C: очистился, запустить от администратора:

```powershell
powershell -ExecutionPolicy Bypass -File "D:\Qwen_testr-backup\mini-swe-benchmark\Resume-After-Reboot.ps1"
```

Скрипт восстановит проект и direct IQ4_XS на локальный NVMe, заново установит
Python-зависимости, проверит Docker/WSL, выполнит gold preflight, smoke-test и
возобновляемую серию из 24 SWE-bench попыток.

## Важно

GGUF-модели не хранятся в Git из-за размера. WSL, Docker Desktop, Docker images и
виртуальное окружение также не являются частью репозитория, но полностью
восстанавливаются скриптами из `mini-swe-benchmark/scripts/`.

Основная инструкция: [mini-swe-benchmark/README.md](mini-swe-benchmark/README.md).

