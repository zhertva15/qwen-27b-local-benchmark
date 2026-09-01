$ErrorActionPreference = 'Stop'

$llamaServer = 'C:\AI\Qwen3.8-27B-Uncensored\llama.cpp-b10734\llama-server.exe'
$model = 'C:\AI\Qwen3.8-27B-Uncensored\models\Qwen3.8-27B-Uncensored-FP8.i1-Q4_K_M.gguf'

if (-not (Test-Path -LiteralPath $llamaServer)) {
    throw "llama-server.exe not found: $llamaServer"
}
if (-not (Test-Path -LiteralPath $model)) {
    throw "Q4 model not found: $model"
}

& $llamaServer `
    --model $model `
    --alias qwen38-27b-q4 `
    --host 127.0.0.1 `
    --port 8081 `
    --api-key local-qwen-key `
    --ctx-size 16384 `
    --parallel 1 `
    --fit on `
    --fit-target 1024 `
    --fit-ctx 8192 `
    --flash-attn on `
    --cache-type-k q8_0 `
    --cache-type-v q8_0 `
    --threads 8 `
    --threads-batch 16 `
    --batch-size 1024 `
    --ubatch-size 512 `
    --jinja `
    --reasoning-format none
