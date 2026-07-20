#Requires -Version 5.1
# DESTRUCTIVE: restore + docker restart — НЕ запускается по умолчанию
# Запуск вручную: Invoke-Pester -Path tests\Backup.Destructive.Tests.ps1 -Tag Destructive
# Или: .\test-backup-restore.ps1 -AllowRestore

# описание с тегом Destructive
Describe 'Backup/Restore destructive' -Tag 'Destructive' {
    # предупреждение
    BeforeAll {
        # корень
        $script:Root = Split-Path -Parent $PSScriptRoot
        # модуль
        Import-Module (Join-Path $script:Root 'modules\HermesHomeServer.psm1') -Force
        # явное предупреждение в консоль
        Write-Warning 'Destructive tests can stop/restart hermes-home and restore data from backup.'
    }

    # обёртка: вызываем старый smoke только с -AllowRestore
    It 'прогоняет test-backup-restore.ps1 -AllowRestore' {
        # путь к скрипту
        $scriptPath = Join-Path $script:Root 'test-backup-restore.ps1'
        # файл должен существовать
        Test-Path $scriptPath | Should -BeTrue
        # запускаем с явным разрешением restore
        & $scriptPath -AllowRestore
        # код выхода
        $LASTEXITCODE | Should -Be 0
    }
}
