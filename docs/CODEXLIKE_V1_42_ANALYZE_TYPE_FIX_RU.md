# AI Agent v1.42 — исправление ошибки analyze

Исправлена ошибка Dart analyzer в `lib/main.dart:6085`, появившаяся в функции удаления дублей строк.

## Что было

В `String.replaceAll` был передан callback, допустимый для `replaceAllMapped`, но не для `replaceAll`. Поэтому Dart выдавал ошибку:

```text
The argument type 'dynamic Function(dynamic)' can't be assigned to the parameter type 'String'
```

## Исправление

Ключ дедупликации теперь нормализует пробелы обычной строковой заменой:

```dart
final key = l.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
```

Это не меняет видимый вывод, но устраняет ошибку компиляции.
