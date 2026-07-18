class UnsupportedSuccessClaimGuard {
  const UnsupportedSuccessClaimGuard._();

  static String? blockReason({
    required String text,
    required bool completionReady,
    required bool hasActionsInResponse,
  }) {
    if (completionReady || hasActionsInResponse) return null;
    final normalized = text
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;

    final claimsMutation = RegExp(
      r'(?:я\s+)?(?:успешно\s+)?(?:заменил|изменил|исправил|создал|записал|обновил)'
      r'|(?:successfully\s+)?(?:changed|replaced|fixed|created|updated|wrote)',
      caseSensitive: false,
    ).hasMatch(normalized);
    final claimsVerification = RegExp(
      r'(?:сборка|компиляция|тесты?)\s+(?:успешн|завершен|пройден)'
      r'|(?:успешно\s+)?(?:собрал|скомпилировал|проверил)'
      r'|build\s+(?:succeeded|successful)|tests?\s+passed',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (!claimsMutation && !claimsVerification) return null;

    return 'UNSUPPORTED_SUCCESS_CLAIM: модель заявила об успешном изменении '
        'или проверке, но в этом ответе не было выполненного инструмента, а '
        'журнал доказательств ещё не подтверждает завершение. Нельзя считать '
        'обычный текст действием. Выполни реальный tool-call или честно укажи '
        'неустранённую проблему.';
  }
}
