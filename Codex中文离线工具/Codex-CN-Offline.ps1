#requires -Version 5.1
<#
Codex 中文离线工具
以 Chromium 调试模式启动 Codex，并注入补丁强制侧边栏使用简体中文。
注意：这是离线方案，Codex 必须通过本工具启动才能生效。
#>

[CmdletBinding()]
param(
    [int]$Port = 9333,
    [switch]$AutoStart
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$SDK_KEY = 'client-sYWqzCYMRkUg4DqqiZcR5DGTNl2iD7zNJY0HoeDLzxR'
$ScriptDir = $PSScriptRoot
$Injector = Join-Path $ScriptDir 'inject.js'
$ConfigPath = Join-Path $env:USERPROFILE '.codex\config.toml'

function Write-Status {
    param([string]$Text, [string]$Color = 'Cyan')
    Write-Host $Text -ForegroundColor $Color
}

function Get-CodexInfo {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $pkg) { return $null }
    $exe = Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'
    $aumid = "$($pkg.PackageFamilyName)!App"
    if (Test-Path -LiteralPath $exe) {
        return @{ Exe = $exe; Aumid = $aumid }
    }
    return $null
}

function Ensure-LocaleOverride {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $dir = Split-Path -Parent $ConfigPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $ConfigPath -Value '' -Encoding UTF8
    }
    $raw = [System.IO.File]::ReadAllText($ConfigPath)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^\s*localeOverride\s*=') { continue }
        $keep.Add($line)
    }
    $desktopIdx = -1
    for ($i = 0; $i -lt $keep.Count; $i++) {
        if ($keep[$i].Trim() -eq '[desktop]') { $desktopIdx = $i; break }
    }
    if ($desktopIdx -ge 0) {
        $keep.Insert($desktopIdx + 1, 'localeOverride = "zh-CN"')
    } else {
        if ($keep.Count -gt 0 -and $keep[$keep.Count - 1].Trim() -ne '') { $keep.Add('') }
        $keep.Add('[desktop]')
        $keep.Add('localeOverride = "zh-CN"')
    }
    $text = (($keep -join $nl).TrimEnd()) + $nl
    [System.IO.File]::WriteAllText($ConfigPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Stop-Codex {
    Get-Process -Name 'ChatGPT', 'Codex', 'codex-command-runner' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1500
}

function Test-PortOpen {
    param([int]$PortNumber)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $PortNumber)
        if ($task.Wait(600)) { return $true }
    } catch { }
    finally { $client.Dispose() }
    return $false
}

function Launch-Normal {
    param([string]$Aumid)
    Start-Process 'explorer.exe' -ArgumentList "shell:AppsFolder\$Aumid"
}

function Apply-Chinese {
    Ensure-LocaleOverride

    $info = Get-CodexInfo
    if (-not $info) {
        Write-Status '未找到 Codex 应用包（OpenAI.Codex），无法继续。' 'Red'
        return $false
    }

    Write-Status '正在关闭正在运行的 Codex...' 'Cyan'
    Stop-Codex

    Write-Status '正在以中文模式启动 Codex（调试端口）...' 'Cyan'
    $exe = $info.Exe
    try {
        Start-Process -FilePath $exe -ArgumentList "--remote-debugging-port=$Port" -ErrorAction Stop
    } catch {
        Write-Status "直接启动失败（$($_.Exception.Message)），改用系统方式启动。" 'Yellow'
        Launch-Normal -Aumid $info.Aumid
        Write-Status '已用普通方式启动 Codex，但这种方式无法注入侧边栏中文补丁。' 'Yellow'
        return $false
    }

    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-PortOpen -PortNumber $Port) { $ok = $true; break }
    }
    if (-not $ok) {
        Write-Status '调试端口未能打开，Codex 可能不支持此启动参数。' 'Red'
        Write-Status '已回退为普通启动，侧边栏暂时仍为英文。' 'Yellow'
        Launch-Normal -Aumid $info.Aumid
        return $false
    }

    Write-Status '调试端口已就绪，正在注入中文补丁...' 'Cyan'
    if (-not (Test-Path -LiteralPath $Injector)) {
        Write-Status "缺少注入脚本：$Injector" 'Red'
        return $false
    }
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
    if (-not $node) {
        Write-Status '未找到 Node.js，无法注入补丁。' 'Red'
        return $false
    }

    & $node $Injector $Port
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Status '注入失败：应用已启动，但侧边栏可能仍为英文。' 'Red'
        return $false
    }
    Write-Status '完成！侧边栏应已切换为简体中文。' 'Green'
    return $true
}

function Install-AutoStart {
    $startup = [Environment]::GetFolderPath('Startup')
    if (-not $startup) {
        Write-Status '无法定位 Windows 启动文件夹。' 'Red'
        return
    }
    $lnk = Join-Path $startup 'Codex中文版.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = (Get-Command powershell.exe).Source
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\Codex-CN-Offline.ps1`" -AutoStart"
    $sc.WorkingDirectory = $ScriptDir
    $sc.Description = '以中文模式启动 Codex'
    $sc.Save()
    Write-Status "已设置开机自动启动：$lnk" 'Green'
}

function Uninstall-AutoStart {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = Join-Path $startup 'Codex中文版.lnk'
    if (Test-Path -LiteralPath $lnk) {
        Remove-Item -LiteralPath $lnk -Force
        Write-Status '已取消开机自动启动。' 'Green'
    } else {
        Write-Status '当前没有设置开机自动启动。' 'Yellow'
    }
}

function Show-Menu {
    Write-Host ''
    Write-Host '==============================' -ForegroundColor Cyan
    Write-Host '  Codex 中文离线工具' -ForegroundColor Cyan
    Write-Host '==============================' -ForegroundColor Cyan
    Write-Host '  1. 启动中文版 Codex（推荐）'
    Write-Host '  2. 设置开机自动启动'
    Write-Host '  3. 取消开机自动启动'
    Write-Host '  Q. 退出'
    Write-Host ''
}

if ($AutoStart) {
    $logPath = Join-Path $ScriptDir 'apply.log'
    try {
        Start-Transcript -Path $logPath -Force -ErrorAction Stop | Out-Null
    } catch { }
    Apply-Chinese | Out-Null
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit
}

$choice = ''
while ($choice -notmatch '^[Qq]$') {
    Show-Menu
    $choice = Read-Host '请选择'
    switch ($choice) {
        '1' { Apply-Chinese | Out-Null }
        '2' { Install-AutoStart }
        '3' { Uninstall-AutoStart }
        'Q' { }
        'q' { }
        default {
            if ($choice -notmatch '^[Qq]$') {
                Write-Status '无效选项，请重新输入。' 'Yellow'
            }
        }
    }
}
