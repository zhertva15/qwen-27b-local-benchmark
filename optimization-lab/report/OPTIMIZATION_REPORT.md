# Отчёт по оптимизации Qwen3.8-27B на RTX 5070 12 GiB

Дата теста: 2026-09-01. Все цифры ниже получены заново в изолированной
директории `optimization-lab`; старый отчёт не использовался как источник
метрик.

## Короткий вывод

Оптимизации подтвердились, но каждая полезна в своём сценарии:

1. **Самый быстрый обычный coding:** Unleashed UD-Q2_K_XL + MTP-2 —
   **74.27 tok/s**, acceptance 93.8%, peak VRAM 11,104 MiB.
2. **Самый предсказуемый универсальный профиль:** LowGPU IQ3XXXS + Q4 KV —
   **41.24 tok/s**, peak VRAM 10,225 MiB и около 1.7 GiB запаса.
3. **Самый быстрый копирующий refactor:** Unleashed + ngram-simple —
   **247.31 tok/s**, точное совпадение результата с ожидаемым файлом.
4. **Q4 стал терпимее:** MTP поднял его с 6.37 до **14.32 tok/s** на coding,
   а ngram дал **39.41 tok/s** на копирующем refactor.
5. **Q4 KV сам по себе не ускоряет уже GPU-resident Unleashed/LowGPU**, но
   освобождает примерно 320 MiB VRAM. Старому FP8-Q2 он помог разместить все
   слои на GPU и поднял скорость с 27.75 до **38.00 tok/s**.

## Методика

Общие параметры: llama.cpp b10734, CUDA, 16,384 context, один slot, Flash
Attention, temperature 0, thinking disabled, 8 generation threads и 16 batch
threads.

Профили:

- `baseline`: Q8_0 K/V, batch 1024, ubatch 512, автоматический fit.
- `q4kv`: Q4_0 K/V, batch 512, ubatch 128; полный GPU offload для моделей,
  которые помещаются, и auto-fit для Q4.
- `q4kv-ngram`: тот же профиль плюс `--spec-type ngram-simple`.
- `q4kv-mtp`: тот же профиль плюс `--spec-type draft-mtp` и draft max 2.

На каждом запуске выполнялись:

- компактная генерация `merge_intervals` с шестью asserts;
- копирующий refactor файла на 551–556 выходных токенов;
- function call `read_file` и второй turn с результатом инструмента;
- замер load time, prompt/decode throughput, VRAM и speculative acceptance.

## Полная матрица

| Модель | Профиль | Load, с | VRAM loaded/peak, MiB | Coding prompt/decode, tok/s | Refactor, tok/s | Draft acceptance |
|---|---|---:|---:|---:|---:|---:|
| FP8-derived Q2_K | baseline | 35.65 | 11,417 / 11,430 | 287.22 / 27.75 | 27.43 | — |
| FP8-derived Q2_K | q4kv | 4.61 | 11,490 / 11,504 | 423.50 / 38.00 | 37.78 | — |
| FP8-derived Q2_K | q4kv-ngram | 4.56 | 11,491 / 11,505 | 422.34 / 37.84 | 230.14 | 513/624, 82.2% |
| FP8-derived Q2_K | q4kv-mtp | 4.53 | 11,786 / 11,802 | 330.69 / 51.33 | 53.22 | coding 94.1%; refactor 99.7% |
| FP8-derived Q4_K_M | baseline | 52.83 | 10,711 / 10,716 | 80.35 / 6.37 | 6.36 | — |
| FP8-derived Q4_K_M | q4kv | 8.10 | 11,144 / 11,175 | 93.22 / 6.98 | 6.98 | — |
| FP8-derived Q4_K_M | q4kv-ngram | 8.11 | 11,143 / 11,184 | 92.16 / 6.94 | 39.41 | 513/624, 82.2% |
| FP8-derived Q4_K_M | q4kv-mtp | 8.62 | 11,092 / 11,092 | 77.53 / 14.32 | 14.24 | coding 97.6%; refactor 100% |
| Unleashed UD-Q2_K_XL | baseline | 30.45 | 10,495 / 10,715 | 249.48 / 40.63 | 40.61 | — |
| Unleashed UD-Q2_K_XL | q4kv | 4.04 | 10,167 / 10,384 | 366.14 / 40.55 | 40.45 | — |
| Unleashed UD-Q2_K_XL | q4kv-ngram | 4.06 | 10,165 / 10,396 | 358.99 / 39.49 | 247.31 | 514/576, 89.2% |
| Unleashed UD-Q2_K_XL | q4kv-mtp | 4.08 | 10,986 / 11,104 | 329.63 / 74.27 | 77.67 | coding 93.8%; refactor 100% |
| LowGPU IQ3XXXS | baseline | 29.98 | 10,271 / 10,571 | 311.08 / 41.28 | 41.22 | — |
| LowGPU IQ3XXXS | q4kv | 4.07 | 9,947 / 10,225 | 328.68 / 41.24 | 41.10 | — |
| LowGPU IQ3XXXS | q4kv-ngram | 4.06 | 9,947 / 10,231 | 327.13 / 39.81 | 235.12 | 513/624, 82.2% |

Load time после первого профиля в каждом семействе в основном отражает тёплый
Windows file cache, поэтому основная ценность этой колонки — сравнение первого
cold-ish load с последующими переключениями, а не рейтинг квантов.

## Проверка качества

- Все 15 случаев сформировали корректный `read_file` call, приняли tool result
  и завершили multi-turn flow правильным summary.
- Все 15 refactor-ответов после удаления `<think>` и Markdown fences **побайтно
  совпали** с ожидаемым Python-файлом: изменены только две требуемые строки.
- FP8-Q2 и FP8-Q4 дали корректный `merge_intervals` во всех профилях.
- LowGPU дал корректную функцию во всех профилях. Baseline-набор asserts не
  содержал отдельного endpoint-touching примера, но сама функция этот случай
  обрабатывает правильно.
- Unleashed baseline снова воспроизвёл старую ошибку: обращение к `merged[-1]`
  при пустом списке. Профили `q4kv` и `q4kv-mtp` выдали корректный код.
  `q4kv-ngram` выдал корректную функцию, но один assert противоречил её
  семантике touching. Это один smoke-тест, однако он не позволяет считать
  Unleashed безусловно надёжнее LowGPU только из-за скорости.

## Что реально дали оптимизации

### Q4 KV и уменьшенные буферы

- FP8-Q2: 27.75 → 38.00 tok/s (+36.9%), потому что логи подтверждают полный
  offload 66/66 слоёв.
- Q4: 6.37 → 6.98 tok/s (+9.6%); в GPU попало 42/66 слоёв, примерно 6,002 MiB
  весов остались CPU-mapped.
- Unleashed и LowGPU: decode почти не изменился, зато loaded VRAM уменьшился
  на 328 и 324 MiB соответственно.

Flash Attention не упал на CPU: server logs во всех проверенных Q4-KV случаях
показывают `flash_attn = enabled` и CUDA compute buffers. Отдельная сборка с
`GGML_CUDA_FA_ALL_QUANTS` для этих тестов не понадобилась.

### ngram-simple

На обычной генерации ngram дал небольшой overhead и снизил decode примерно на
1–3%. На задаче, где почти весь исходный код копируется в ответ, ускорение было
огромным:

| Модель | Без speculation | ngram-simple | Ускорение |
|---|---:|---:|---:|
| FP8-Q2 | 37.78 | 230.14 | 6.09× |
| FP8-Q4 | 6.98 | 39.41 | 5.65× |
| Unleashed | 40.45 | 247.31 | 6.11× |
| LowGPU | 41.10 | 235.12 | 5.72× |

Следовательно, ngram надо включать для edit/refactor маршрута, но не держать
единственным глобальным профилем агента.

### MTP-2

На текущих coding/refactor prompts acceptance оказался очень высоким, поэтому
MTP дал крупный прирост. Но прошлый длинный prose-тест этой же машины при 68.6%
acceptance замедлялся. MTP следует включать для coding и отключать/перепроверять
для длинной свободной прозы.

FP8-Q2 с MTP достиг 51.33 tok/s, но peak VRAM 11,802 MiB оставляет примерно
142 MiB — профиль слишком хрупкий для рабочего desktop. Unleashed MTP достиг
74.27 tok/s при peak 11,104 MiB и остаётся практичнее. Q4 MTP использовал только
39/66 GPU layers, но высокая acceptance всё равно более чем удвоила decode.

## Рекомендуемые рабочие профили

### Безопасный универсальный coding-agent

`lowgpu-iq3 + q4kv`: 41.24 tok/s, хороший запас VRAM, корректный coding,
refactor и tool flow. Это основной профиль, если важнее предсказуемость.

### Турбо coding

`unleashed-q2 + q4kv-mtp`: 74.27 tok/s. Использовать с автотестами/линтером,
поскольку Unleashed показал нестабильность на одном компактном coding smoke-test.

### Copy-heavy edit/refactor

`unleashed-q2 + q4kv-ngram`: 247.31 tok/s. Если важнее более осторожный квант,
`lowgpu-iq3 + q4kv-ngram` дал 235.12 tok/s и тот же точный refactor.

### Q4-класс

`fp8-q4 + q4kv-mtp`: 14.32 tok/s для обычного coding. Для копирующего edit
маршрута `q4kv-ngram` достигает 39.41 tok/s. Q4 всё равно уступает Q2/IQ3 по
latency, но эти профили делают её пригоднее для задач, где качество кванта важнее.

## Что не вошло в этот прогон

- Q4_K_S не тестировался: файла нет локально, а добавление новой модели нарушило
  бы чистое сравнение четырёх уже установленных GGUF.
- Selective FFN offload не смешивался с основной матрицей. Для него нужен
  отдельный подбор tensor overrides и собственный отчёт после фиксации baseline.
- Для окончательного выбора между LowGPU и Unleashed нужен более широкий coding
  suite, а не один алгоритмический smoke-test.

## Артефакты

- Плоская таблица: `results/summary.csv`
- Аудит точного refactor: `results/audit.csv`
- Полные ответы и метрики: `results/raw/*.json`
- Backend/offload логи: `logs/server/*.stderr.log`
- Воспроизводимый runner: `scripts/Run-OptimizationMatrix.ps1`
- Запуск выбранного профиля: `launchers/Start-Profile.ps1`
