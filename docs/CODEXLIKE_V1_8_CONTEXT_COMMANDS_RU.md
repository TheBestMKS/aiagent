# Исправления v1.8: контекст модели и вывод команд

## 1. Контекст и длина ответа разделены

Раньше агент фактически работал с одним числом `maxContextTokens`. Из-за этого можно было неверно трактовать ситуацию, когда модель поддерживает большой context window (например, 131072 токенов), но ответ обрывается по лимиту генерации (`finish_reason: length`).

Теперь в профиле есть два отдельных параметра:

- `Context window tokens` — максимальный контекст модели;
- `Max output tokens` — максимальная длина ответа модели для одного запроса.

В логах теперь пишется:

```text
CONTEXT BUDGET: contextWindow=... promptTokens≈... requestedMaxOutput=... sentMaxTokens=...
MODEL USAGE: prompt=... completion=... total=...
MODEL FINISH_REASON: ...
```

Если сервер возвращает `finish_reason: length`, агент пишет в лог, что это остановка по длине ответа, а не обязательно ошибка context window.

## 2. Автоматическое определение лимитов стало безопаснее

Если `/v1/models` не отдаёт поля контекста или output limit, агент больше не подставляет случайный низкий лимит. Он использует значения из профиля и пишет в лог:

```text
MODEL LIMITS METADATA: model=... endpoint_ctx=missing endpoint_output=missing using_profile_ctx=... using_profile_output=...
```

Для профилей, найденных через опрос IP/порта, теперь по умолчанию используется:

```text
context window: 131072
max output: 16384
```

## 3. Вывод команд сохраняется полностью

Каждый запуск `run_command` / `run_tests` теперь сохраняет полный вывод команды в файл:

```text
.cppagent/logs/commands/<timestamp>_command.log
```

В основной лог пишется:

```text
RUN COMMAND START: ...
RUN COMMAND RESULT FULL SAVED: ...
RUN COMMAND RESULT: ...
```

В `actions.jsonl` также добавляется `output_log`.

## 4. stdout/stderr передаются модели

Результат команды теперь возвращается модели в явном формате:

```text
COMMAND: ...
WORKDIR: ...
EXIT_CODE: ...
DURATION_MS: ...

[STDOUT]
...

[STDERR]
...
[/STDERR]
FULL_OUTPUT_LOG: ...
```

Если команда завершилась ошибкой, это также попадает в `taskStateJson.last_command_output`, чтобы следующая итерация модели видела причину ошибки и могла исправить код.

## 5. C++ fallback больше не считается успехом при ошибке сборки

Если локальный fallback создал `main.cpp`, но сборка/запуск завершились ошибкой, агент больше не завершает задачу как готовую. Он передаёт вывод команды модели и продолжает цикл исправления.

## 6. Команда сборки C++ на Windows усилена

Для `main.cpp` агент теперь пробует:

1. `g++`, если он есть в PATH;
2. `cl.exe`, если программа запущена из Visual Studio Developer Command Prompt;
3. если компилятора нет — возвращает понятную ошибку в stdout/stderr и передаёт её модели.
