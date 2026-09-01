# Восстановление текущей задачи Codex

Этот файл — безопасная карта продолжения. Полный сырой журнал задачи намеренно
не хранится в Git: он содержит внутренний контекст, локальные пути и tool-логи.

## Идентификаторы и страховки

- Codex thread ID: `01a05d27-c52f-7891-bb59-aac28d93f5fd`
- Название: `Установить и сравнить Qwen3.8-27B Q2 и Q4 на RTX 5070 12 ГБ`
- Облачный снимок: <https://chatgpt.com/s/cx_6a97116566188191b0ff7bb2ae90edd8>
- Приватный GitHub: <https://github.com/zhertva15/qwen-27b-local-benchmark>
- Автономный Git-клон: `D:\Qwen_testr-backup\qwen-27b-local-benchmark\`
- Сырой бэкап: `D:\Qwen_testr-backup\codex-session\01a05d27-c52f-7891-bb59-aac28d93f5fd\`
- ZIP-копия сессии: `D:\Qwen_testr-backup\codex-session\01a05d27-c52f-7891-bb59-aac28d93f5fd.zip`
- Проект и архив: `D:\Qwen_testr-backup\mini-swe-benchmark\` и
  `D:\Qwen_testr-backup\mini-swe-benchmark-full.zip`
- Direct IQ4_XS: `D:\Qwen_testr-backup\models\orcarouter_Qwen3.8-27B-Uncensored-IQ4_XS.gguf`

Облачная ссылка имеет режим `public`: любой человек со ссылкой сможет прочитать
снимок. Не публиковать её дополнительно.

## Где остановились

Цель — сравнить три uncensored-профиля на RTX 5070 12 GB через официальный
mini-swe-agent и SWE-bench evaluator:

1. LowGPU IQ3XXXS;
2. текущий FP8-derived Q4_K_M;
3. direct OrcaRouter IQ4_XS.

План: четыре SWE-bench Verified задачи, два seed на модель, всего 24 попытки.
Основная метрика — успешные задачи в час, а не синтетическая скорость генерации.

Текущее состояние на 1 сентября 2026:

- рабочая ветка `main` опубликована в приватном GitHub;
- Docker Desktop установлен на C:;
- WSL ещё не активен и потребует установки/перезагрузки;
- direct OrcaRouter IQ4_XS полностью сохранён на D: (15 567 825 152 байта);
- `mini-swe-benchmark/results/api-preflight.json` создан;
- gold preflight, smoke и 24 основные попытки ещё не выполнены;
- C: используется для быстрого запуска моделей, D: — для постоянного хранения.

## Быстрое продолжение после очистки C:

1. Установить Codex и войти в тот же аккаунт.
2. Клонировать приватный репозиторий:

   ```powershell
   git clone https://github.com/zhertva15/qwen-27b-local-benchmark.git
   ```

3. Открыть клонированную папку в Codex и отправить новый запрос:

   ```text
   Прочитай README.md, SESSION_RECOVERY.md и mini-swe-benchmark/README.md.
   Продолжи подготовленный benchmark с точки, описанной в SESSION_RECOVERY.md.
   Сначала проверь D:\Qwen_testr-backup и не скачивай повторно уже сохранённые модели.
   ```

4. Для просмотра исходной переписки открыть облачный снимок выше.
5. Если нужен проект с D:, вместо клонирования запустить от администратора:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "D:\Qwen_testr-backup\mini-swe-benchmark\Resume-After-Reboot.ps1"
   ```

## Сырой локальный бэкап

Скрипт [recovery/Backup-CodexSession.ps1](recovery/Backup-CodexSession.ps1)
сохраняет на D: актуальный rollout JSONL, индекс сессий, базы состояния,
прикреплённые файлы, контрольные SHA-256 и итоговый ZIP. Он специально не копирует
`auth.json`, `.sandbox-secrets`, браузерный профиль или другие токены.

Автоматический импорт сырого бэкапа обратно в интерфейс Codex официально не
документирован. Поэтому основным способом продолжения считается новый task с
этим recovery-файлом, а сырой бэкап нужен как полный архив и запасной источник.

Перед самой перезагрузкой обновить снимок:

```powershell
powershell -ExecutionPolicy Bypass -File ".\recovery\Backup-CodexSession.ps1"
```
