# 绘声绘色 卸载：删除快捷方式和程序目录；可选删除已保存的密钥
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = '卸载 绘声绘色' } catch { }
$Dst = Join-Path $env:LOCALAPPDATA 'Programs\TongHuiFang'
$Cfg = Join-Path $env:APPDATA 'TongHuiFang'

Write-Host ''
$ans = Read-Host '  确定要卸载 绘声绘色 吗？输入 Y 后按回车确认'
if ($ans -notmatch '^[Yy]') { Write-Host '  已取消。'; Start-Sleep -Seconds 2; exit 0 }

foreach ($dir in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
  foreach ($name in @('绘声绘色.lnk','童绘坊.lnk')) {
    $lnk = Join-Path $dir $name
    if (Test-Path $lnk) { Remove-Item $lnk -Force }
  }
}

$k = Read-Host '  是否同时删除本机保存的 DeepSeek 和 MiniMax 密钥？输入 Y 删除，直接回车保留'
if ($k -match '^[Yy]' -and (Test-Path $Cfg)) { Remove-Item $Cfg -Recurse -Force; Write-Host '  已删除密钥。' }

if (Test-Path $Dst) {
  # 程序目录稍后删除（本窗口关闭后），避免删除正在使用的文件
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'timeout /t 3 /nobreak >nul & rmdir /s /q "' + $Dst + '"') -WindowStyle Hidden
}
Write-Host ''
Write-Host '  卸载完成。' -ForegroundColor Green
Start-Sleep -Seconds 2
