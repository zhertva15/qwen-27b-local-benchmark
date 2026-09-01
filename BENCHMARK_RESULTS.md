# Qwen3.8-27B Uncensored: RTX 5070 12 GiB results

Tested on 2026-09-01 with an RTX 5070 12 GiB, Intel Core i5-14600KF,
32 GiB system RAM, NVIDIA driver 610.62, and llama.cpp b10734
(`d5d993a09`).

Common settings: 16,384-token context, one server slot, Flash Attention,
Q8_0 K/V cache, 8 generation threads, 16 batch threads, and thinking disabled.
Results below are local measurements, not author claims.

| Model | GGUF size | Loaded VRAM | Decode speed | Prompt speed | Coding smoke test |
|---|---:|---:|---:|---:|---|
| OrcaRouter LowGPU IQ3XXXS | 8.91 GiB | 10,738 MiB used / 1,206 MiB free | 41.31 tok/s | 149.62 tok/s | Pass |
| Unleashed UD-Q2_K_XL, no MTP | 9.21 GiB | 10,877 MiB used / 1,067 MiB free | 40.76 tok/s | 327.46 tok/s | Fail: empty-list bug |
| Unleashed UD-Q2_K_XL, MTP | 9.21 GiB | 11,366 MiB used / 578 MiB free | 42.63 tok/s | 220.48 tok/s | Same bug |
| Earlier FP8-derived Q2_K | 10.12 GiB | 11,329 MiB used / 615 MiB free | 27.5-29.1 tok/s | 244.7-257.0 tok/s | Pass on compact prompt |
| Earlier FP8-derived Q4_K_M, safe target | 15.66 GiB | 10,858-10,897 MiB used | 6.35-6.45 tok/s | 78.86-82.5 tok/s | Pass |

## New model checks

The identical coding prompt requested a normalized, sorted interval-merging
function plus exactly six assertions. LowGPU IQ3XXXS returned a correct function
and completed at 41.31 tok/s. Unleashed generated `merged[-1]` while `merged` was
still empty, so its function raises `IndexError` on the first non-empty input.
This is one deterministic smoke test, not a statistical benchmark, but it is a
material failure on the task.

Both new models:

- emitted a correctly parsed `read_file` function call;
- accepted the tool result in a second turn;
- returned the correct one-sentence file summary.

LowGPU IQ3XXXS is the best result so far for this 12 GiB machine: it is about
42% faster than the earlier Q2 result, leaves twice as much VRAM headroom, and
passed the coding and multi-turn agent checks.

## MTP result

On the 237-token coding response, Unleashed MTP improved decode speed from
40.76 to 42.63 tok/s (+4.6%) and accepted 154 of 166 drafted tokens (92.8%).
On a 1,024-token prose response it fell from 40.65 tok/s without MTP to
35.46 tok/s with MTP (-12.8%); draft acceptance fell to 591 of 862 (68.6%).
MTP also reduced free VRAM from 1,067 MiB to 578 MiB. It therefore remains an
optional launcher switch and is disabled by default.

## Local NVMe versus the club iSCSI disk

Windows identifies C: as a local Patriot P300 NVMe and D: as a TrueNAS iSCSI
SSD. WinSAT sequential-read results were:

| Drive | Sequential read |
|---|---:|
| C: local NVMe | 1,977.75 MB/s |
| D: TrueNAS iSCSI | 113.00 MB/s |

C: was about 17.5 times faster in this storage test. Moving the active Q4 from
D: to C: reduced its cold start from roughly 150 seconds to 52.7 seconds, while
steady decode stayed in the same 6.35-6.45 tok/s range. Disk location therefore
matters heavily for model loading and page faults, but does not remove the Q4
CPU/RAM-offload bottleneck once inference is running.

The persistent archive stays on D:. `sync-models-to-local.ps1` recreates the
fast C: cache if the club resets the local disk after a reboot.

## Earlier functional checks

- The earlier FP8-derived Q2 and Q4 both served an OpenAI-compatible API and
  returned a parsed `read_file` call.
- Earlier Q2 completed a multi-turn tool-result flow correctly.
- On the same compact interval prompt, earlier Q2 and Q4 returned correct
  functions; their measured speeds were 27.48 and 6.79 tok/s respectively.

All coding results here are smoke tests. A larger task suite is required before
treating small quality differences as a reliable model ranking.
