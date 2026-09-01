. (Join-Path $PSScriptRoot 'Common.ps1')
Set-StrictMode -Off
$paths = Get-BenchmarkPaths
$csvPath = Join-Path $paths.Results 'attempts.csv'
if (-not (Test-Path -LiteralPath $csvPath)) { throw 'attempts.csv is missing.' }
$attempts = @(Import-Csv -LiteralPath $csvPath)
$selectedPath = Join-Path $paths.State 'selected-tasks.json'
$selected = if (Test-Path -LiteralPath $selectedPath) { Get-Content -LiteralPath $selectedPath -Raw | ConvertFrom-Json } else { $null }

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if ($Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    $index = [math]::Max(0, [math]::Ceiling($Percentile * $sorted.Count) - 1)
    return [double]$sorted[$index]
}

$modelNames = [ordered]@{
    'lowgpu-iq3xxxs' = 'LowGPU IQ3XXXS'
    'fp8-q4-k-m' = 'FP8-derived Q4_K_M'
    'direct-iq4-xs' = 'Direct OrcaRouter IQ4_XS'
}
$stats = [Collections.Generic.List[object]]::new()
foreach ($modelId in $modelNames.Keys) {
    $items = @($attempts | Where-Object model -eq $modelId)
    $resolvedItems = @($items | Where-Object resolved -eq 'True')
    $wall = ($items | Measure-Object -Property total_wall_seconds -Sum).Sum
    if ($null -eq $wall) { $wall = 0 }
    $seed101 = @($items | Where-Object { $_.seed -eq '101' -and $_.resolved -eq 'True' }).Count
    $uniqueResolved = @($resolvedItems.task | Sort-Object -Unique).Count
    $coldLoads = @($items | Group-Object block | ForEach-Object { [double]$_.Group[0].cold_load_seconds })
    $stats.Add([pscustomobject]@{
        model = $modelId
        name = $modelNames[$modelId]
        attempts = $items.Count
        resolved = $resolvedItems.Count
        unique = $uniqueResolved
        pass1 = if ($items.Count) { $seed101 / 4.0 } else { 0 }
        pass2 = if ($items.Count) { $uniqueResolved / 4.0 } else { 0 }
        tasksPerHour = if ($wall -gt 0) { 3600.0 * $resolvedItems.Count / $wall } else { 0 }
        medianWall = Get-Percentile -Values @($items.total_wall_seconds | ForEach-Object { [double]$_ }) -Percentile 0.5
        p95Wall = Get-Percentile -Values @($items.total_wall_seconds | ForEach-Object { [double]$_ }) -Percentile 0.95
        steps = [int](($items | Measure-Object -Property api_bash_steps -Sum).Sum)
        formatErrors = [int](($items | Measure-Object -Property format_errors -Sum).Sum)
        testCommands = [int](($items | Measure-Object -Property test_commands -Sum).Sum)
        incomplete = @($items | Where-Object exit_status -ne 'Submitted').Count
        promptTokens = [int](($items | Measure-Object -Property prompt_tokens -Sum).Sum)
        outputTokens = [int](($items | Measure-Object -Property output_tokens -Sum).Sum)
        reasoningTokens = [int](($items | Measure-Object -Property reasoning_tokens -Sum).Sum)
        patchMedian = Get-Percentile -Values @($items.patch_lines | ForEach-Object { [double]$_ }) -Percentile 0.5
        f2pPassed = [int](($items | Measure-Object -Property f2p_passed -Sum).Sum)
        f2pTotal = [int](($items | Measure-Object -Property f2p_total -Sum).Sum)
        p2pPassed = [int](($items | Measure-Object -Property p2p_passed -Sum).Sum)
        p2pTotal = [int](($items | Measure-Object -Property p2p_total -Sum).Sum)
        regressions = [int](($items | Measure-Object -Property regressions -Sum).Sum)
        oom = @($items | Where-Object oom -eq 'True').Count
        timeout = @($items | Where-Object timeout -eq 'True').Count
        peakVram = [int](($items | Measure-Object -Property peak_vram_mib -Maximum).Maximum)
        peakRam = [double](($items | Measure-Object -Property peak_ram_gib -Maximum).Maximum)
        coldLoadMedian = Get-Percentile -Values $coldLoads -Percentile 0.5
        offloadedLayers = (@($items.offloaded_layers | Where-Object { $_ } | Sort-Object -Unique) -join ', ')
        wallSum = [double]$wall
    })
}

$decision = 'Недостаточно данных: основной прогон ещё не завершён.'
if ($attempts.Count -eq 24) {
    $quality = $stats | Sort-Object @{Expression = 'resolved'; Descending = $true}, @{Expression = 'tasksPerHour'; Descending = $true} | Select-Object -First 1
    $fast = $stats | Sort-Object @{Expression = 'tasksPerHour'; Descending = $true} | Select-Object -First 1
    if ($quality.model -eq $fast.model) {
        $decision = "Основной профиль: **$($quality.name)** — он одновременно дал максимум успешных попыток и максимальный throughput."
    } else {
        $gap = [int]$quality.resolved - [int]$fast.resolved
        if ($gap -ge 2) {
            $decision = "Единственного победителя нет: **$($fast.name)** остаётся fast profile, а **$($quality.name)** — quality profile."
        } elseif ($gap -eq 1) {
            $decision = "Предварительный выбор по tasks/hour: **$($fast.name)**. Разница качества — одна попытка, поэтому вывод требует большей выборки."
        } else {
            $decision = "Основной профиль по tasks/hour: **$($fast.name)**; число успешных попыток одинаковое."
        }
    }
}

$taskLines = if ($null -ne $selected) { @($selected.tasks | ForEach-Object { "- ``$($_)``" }) -join "`n" } else { '- ещё не зафиксированы' }
$tableLines = [Collections.Generic.List[string]]::new()
$tableLines.Add('| Модель | Успехи | Уникальные | pass@1 | pass@2 | задач/час | median | p95 | Bash/API steps | Регрессии | OOM/timeout | Peak VRAM |')
$tableLines.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
foreach ($item in $stats) {
    $tableLines.Add(('| {0} | {1}/{2} | {3}/4 | {4:P0} | {5:P0} | {6:N2} | {7:N1}s | {8:N1}s | {9} | {10} | {11}/{12} | {13} MiB |' -f $item.name, $item.resolved, $item.attempts, $item.unique, $item.pass1, $item.pass2, $item.tasksPerHour, $item.medianWall, $item.p95Wall, $item.steps, $item.regressions, $item.oom, $item.timeout, $item.peakVram))
}

$secondaryLines = [Collections.Generic.List[string]]::new()
$secondaryLines.Add('| Модель | Cold load median | Peak RAM | F2P | P2P | Тест-команды | Format/incomplete | Tokens prompt/output/reasoning | Patch median | Offload |')
$secondaryLines.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---|')
foreach ($item in $stats) {
    $secondaryLines.Add(('| {0} | {1:N1}s | {2:N2} GiB | {3}/{4} | {5}/{6} | {7} | {8}/{9} | {10}/{11}/{12} | {13:N0} lines | {14} |' -f $item.name, $item.coldLoadMedian, $item.peakRam, $item.f2pPassed, $item.f2pTotal, $item.p2pPassed, $item.p2pTotal, $item.testCommands, $item.formatErrors, $item.incomplete, $item.promptTokens, $item.outputTokens, $item.reasoningTokens, $item.patchMedian, $item.offloadedLayers))
}

$report = @"
# mini-swe-agent: LowGPU vs два Q4

Статус: **$($attempts.Count) из 24 зачётных попыток**. Данные собраны $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K').

## Вывод

$decision

## Итоговые метрики

$($tableLines -join "`n")

## Диагностические метрики

$($secondaryLines -join "`n")

Основная метрика — 3600 × resolved_attempts / total_wall_seconds. Wall time
начинается непосредственно перед запуском mini-swe-agent и заканчивается после
штатного SWE-bench grading. Холодная загрузка llama-server в эту метрику не входит.

## Зафиксированные задачи

$taskLines

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
"@
$report | Set-Content -LiteralPath (Join-Path $paths.Root 'REPORT.md') -Encoding utf8
Write-Host "Report updated: $(Join-Path $paths.Root 'REPORT.md')"
