class SecretRedactor {
  const SecretRedactor._();

  static const _sensitiveKeyParts = <String>{
    'api_key',
    'apikey',
    'access_key',
    'private_key',
    'client_secret',
    'authorization',
    'password',
    'passwd',
    'passphrase',
    'refresh_token',
    'access_token',
    'token',
    'secret',
  };

  static bool isSensitiveKey(String key) {
    final normalized = key
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (_sensitiveKeyParts.contains(normalized)) return true;
    if (_sensitiveKeyParts.any((part) => normalized.endsWith('_$part'))) {
      return true;
    }
    if (normalized.startsWith('authorization_') ||
        normalized.startsWith('password_') ||
        normalized.startsWith('passwd_') ||
        normalized.startsWith('passphrase_')) {
      return true;
    }
    if (normalized.startsWith('token_')) {
      return !const {
        'token_count',
        'token_usage',
        'token_budget',
        'token_limit',
        'token_length',
        'token_type',
      }.contains(normalized);
    }
    return false;
  }

  static Object? redactObject(Object? value, {String key = ''}) {
    if (key.isNotEmpty && isSensitiveKey(key)) return '[REDACTED]';
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): redactObject(
            entry.value,
            key: entry.key.toString(),
          ),
      };
    }
    if (value is Iterable) {
      return value
          .map((item) => redactObject(item))
          .toList(growable: false);
    }
    if (value is String) return redact(value);
    return value;
  }

  static String redact(String value) {
    var result = value;
    final patterns = <RegExp>[
      RegExp(
        r'(?:bearer|basic)\s+[a-z0-9._~+\-/=]{8,}',
        caseSensitive: false,
      ),
      RegExp(
        r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        caseSensitive: false,
      ),
      RegExp(r'gh[pousr]_[A-Za-z0-9_]{20,}'),
      RegExp(r'sk-[A-Za-z0-9_-]{16,}'),
      RegExp(r'AIza[0-9A-Za-z_-]{24,}'),
      RegExp(r'xox[baprs]-[A-Za-z0-9-]{10,}'),
      RegExp(r'AKIA[0-9A-Z]{16}'),
      RegExp(
        r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}',
      ),
      RegExp(
        r'([a-z][a-z0-9+.-]*://[^\s:/@]+:)([^\s@]+)(@)',
        caseSensitive: false,
      ),
      RegExp(
        r'''((?:["']?(?:api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token|token|password|passwd|passphrase|secret|authorization)["']?)\s*[:=]\s*)(?:["'][^"'\r\n]*["']|[^\s,;}\]]+)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''((?:["']?(?:smtp|imap|database|redis|postgres|mysql|mongodb)(?:[_-]?(?:url|uri|password|token))?["']?)\s*[:=]\s*)(?:["'][^"'\r\n]*["']|[^\s,;}\]]+)''',
        caseSensitive: false,
      ),
    ];
    for (var index = 0; index < patterns.length; index++) {
      final pattern = patterns[index];
      result = result.replaceAllMapped(pattern, (match) {
        if (index >= patterns.length - 2) {
          return '${match.group(1)}[REDACTED]';
        }
        if (index == patterns.length - 3 && match.groupCount >= 3) {
          return '${match.group(1)}[REDACTED]${match.group(3)}';
        }
        return 'REDACTED_SECRET';
      });
    }
    return result;
  }
}
