# Собирает Windows release и установщик Inno Setup.
# Запуск на Windows-ноутбуке из корня репозитория:
#   powershell -ExecutionPolicy Bypass -File .\scripts\release\build-windows.ps1
#
# Требования:
#   - Flutter SDK в PATH;
#   - Visual Studio 2022 с workload "Desktop development with C++";
#   - Inno Setup 6 (ISCC.exe).

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location (Join-Path $root "apps\client")

Write-Host "Сборка Windows release..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows завершился с ошибкой"
}

$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "ISCC.exe не найден. Установите Inno Setup 6."
}

$iss = Join-Path $root "installer\windows\zadachnik.iss"
Write-Host "Сборка установщика: $iss"
& $iscc $iss
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup завершился с ошибкой"
}

$installer = Get-ChildItem (Join-Path $root "dist\windows") -Filter "*-setup.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $installer) {
    throw "Установщик не найден в dist\windows"
}

$hash = Get-FileHash $installer.FullName -Algorithm SHA256
"$($hash.Hash.ToLower())  $($installer.Name)" |
    Out-File "$($installer.FullName).sha256" -Encoding ascii

Write-Host ""
Write-Host "Готово: $($installer.FullName)"
Write-Host "SHA-256: $($hash.Hash.ToLower())"
Write-Host "Установщик не подписан; SmartScreen может показать предупреждение."
