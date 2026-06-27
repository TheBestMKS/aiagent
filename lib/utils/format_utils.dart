import '../core/models.dart';

String formatDateTime(DateTime dt) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

String formatMessageDateTime(ChatMessage message) {
  if (message.updatedAt.difference(message.createdAt).inMilliseconds.abs() >
      1000) {
    return '${formatDateTime(message.createdAt)} • изм. ${formatDateTime(message.updatedAt)}';
  }
  return formatDateTime(message.createdAt);
}
