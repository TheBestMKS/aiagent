# Исправление сборочного скрипта 1.55.1

В версии 1.55.0 PowerShell не мог разобрать строку сообщения об ошибке:

```powershell
"... $LASTEXITCODE: flutter ..."
```

После имени переменной непосредственно следовало двоеточие, которое PowerShell пытался интерпретировать как часть ссылки на переменную с областью действия.

В версии 1.55.1 код завершения сохраняется отдельно, а сообщение собирается оператором форматирования:

```powershell
$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
  $CommandText = $Arguments -join ' '
  throw ("Flutter command failed with exit code {0}: flutter {1}" -f $ExitCode, $CommandText)
}
```

Это совместимо с Windows PowerShell 5.1 и PowerShell 7 и не зависит от расположения двоеточий в тексте сообщения.
