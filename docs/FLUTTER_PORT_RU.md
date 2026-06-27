# Flutter port v1.3

Изменения версии:

- локальные профили llama.cpp CPU/Vulkan/CUDA;
- поиск `.gguf` в `models` и `tooling/models`;
- запуск `llama-server` на desktop-платформах;
- расширенные настройки модели, похожие на LM Studio;
- опрос OpenAI-compatible endpoint по IP/портам;
- выпадающий список моделей в чате и кнопка обновления;
- индикатор контекста в чате;
- файловое дерево + редактор справа;
- рекурсивное копирование/перемещение файлов и папок;
- сборка Windows и Android в `distrib`;
- исправлен `build_all.bat`: теперь собирает Windows и Android.

Flutter SDK должен лежать в:

```text
tooling/flutter/flutter/bin/flutter.bat
```
