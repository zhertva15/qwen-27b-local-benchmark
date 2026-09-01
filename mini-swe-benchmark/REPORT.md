# mini-swe-agent: LowGPU vs два Q4

Статус: **0 из 24 зачётных попыток**. Данные собраны 2026-09-01 20:40:03 +03:00.

## Вывод

Недостаточно данных: основной прогон ещё не завершён.

## Итоговые метрики

| Модель | Успехи | Уникальные | pass@1 | pass@2 | задач/час | median | p95 | Bash/API steps | Регрессии | OOM/timeout | Peak VRAM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| LowGPU IQ3XXXS | 0/0 | 0/4 | 0 % | 0 % | 0,00 | 0,0s | 0,0s | 0 | 0 | 0/0 | 0 MiB |
| FP8-derived Q4_K_M | 0/0 | 0/4 | 0 % | 0 % | 0,00 | 0,0s | 0,0s | 0 | 0 | 0/0 | 0 MiB |
| Direct OrcaRouter IQ4_XS | 0/0 | 0/4 | 0 % | 0 % | 0,00 | 0,0s | 0,0s | 0 | 0 | 0/0 | 0 MiB |

## Диагностические метрики

| Модель | Cold load median | Peak RAM | F2P | P2P | Тест-команды | Format/incomplete | Tokens prompt/output/reasoning | Patch median | Offload |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| LowGPU IQ3XXXS | 0,0s | 0,00 GiB | 0/0 | 0/0 | 0 | 0/0 | 0/0/0 | 0 lines |  |
| FP8-derived Q4_K_M | 0,0s | 0,00 GiB | 0/0 | 0/0 | 0 | 0/0 | 0/0/0 | 0 lines |  |
| Direct OrcaRouter IQ4_XS | 0,0s | 0,00 GiB | 0/0 | 0/0 | 0 | 0/0 | 0/0/0 | 0 lines |  |

Основная метрика — 3600 × resolved_attempts / total_wall_seconds. Wall time
начинается непосредственно перед запуском mini-swe-agent и заканчивается после
штатного SWE-bench grading. Холодная загрузка llama-server в эту метрику не входит.

## Зафиксированные задачи

- ещё не зафиксированы

Для каждой модели выполнены seed 101 и 202 в порядке блоков из config/run-plan.json.
Каждая попытка получает новый SWE-bench контейнер и чистый checkout; агентный
контейнер запускается с --network none. У evaluator используется неизменённый
официальный harness.

## Профили

- общий контекст 32K, Q4 KV, Flash Attention, batch 2048, ubatch 256,
  cache-reuse 256, threads 8/20, thinking medium и preserve-thinking;
- LowGPU: полный GPU offload без speculation;
- оба Q4: automatic fit и MTP-2 с одинаковыми серверными аргументами.

## Как трактуются дополнительные числа

Tool calls здесь означают Bash/API-шаги mini-swe-agent. Это текстовый
litellm_textbased режим, а не native function calling. Полные команды,
наблюдения и сохранённое reasoning находятся в штатных trajectory JSON.
F2P/P2P, regressions и resolved взяты из официальных report.json; собственная
логика успешности не используется.

Исходные строки: results/attempts.csv. Gold preflight: results/gold-preflight.json.
Smoke-test: results/smoke-summary.json.

## Ограничения

Четыре задачи и два seed дают быстрый практический сигнал, но не статистически
устойчивый рейтинг. Разницу в одну успешную попытку следует считать предварительной.

Инструменты: [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent),
[SWE-bench](https://github.com/SWE-bench/SWE-bench).
