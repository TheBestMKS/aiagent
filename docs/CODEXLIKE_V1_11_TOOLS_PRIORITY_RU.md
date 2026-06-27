# v1.11 — tools priority, среда выполнения и компиляция

## Что исправлено

### 1. Папка `tools` стала частью среды агента

Агент теперь сканирует локальные программы пользователя в папке:

```text
tools/<os>/<arch>
tools/<os>
tools/common/<arch>
tools/common
tools
```

Для Windows x64 основной путь:

```text
tools/windows/x64
```

Найденные программы передаются модели компактно, без перегруза контекста. Если список большой, модель может вызвать инструмент `list_local_tools`.

### 2. Приоритет программ из `tools`

Перед каждым `run_command` агент добавляет папки с найденными программами из `tools` в начало `PATH`.

Это значит, что если пользователь положил, например:

```text
tools/windows/x64/mingw64/bin/g++.exe
tools/windows/x64/python/python.exe
tools/windows/x64/cmake/bin/cmake.exe
```

то команды модели вида `g++ ...`, `python ...`, `cmake ...` сначала будут искать программы в `tools`, а уже потом в системном PATH.

### 3. Агент сообщает модели ОС и архитектуру

В system prompt теперь передаётся компактный блок:

```text
OS: windows; arch: x64; platform folder: tools/windows/x64; app root: ...; project root: ...
```

Модель должна понимать, что работает, например, в Windows x64 и использовать `.exe`, `.bat`, `.cmd`, `cmd.exe`-совместимые команды.

### 4. Улучшен `run_tests` для C++

Раньше автопроверка искала только `main.cpp`, поэтому файл вроде `object_recognition.cpp` не компилировался и агент писал `No default tests detected`.

Теперь агент ищет C++ файлы:

```text
main.cpp
object_recognition.cpp
object_detector.cpp
*.cpp
*.cc
*.cxx
```

И пробует компиляторы в порядке:

```text
g++ из tools/PATH
clang++ из tools/PATH
cl.exe из tools/PATH
```

### 5. Ошибка отсутствия компилятора больше не считается успешной проверкой

Если компилятор не найден, `run_tests` возвращает ненулевой exit code и понятное сообщение, а не `No default tests detected`.

### 6. Новый инструмент `list_local_tools`

Модель может вызвать:

```xml
<tool_call>{"name":"list_local_tools","args":{"purpose":"cpp"}}</tool_call>
```

Чтобы получить список подходящих программ из папки `tools`.

### 7. Прямой ответ пользователю о доступных инструментах

Если пользователь спрашивает: “Какие у тебя есть инструменты для запуска и компиляции программ”, агент теперь отвечает напрямую из своего сканера `tools`, не заставляя модель угадывать.

