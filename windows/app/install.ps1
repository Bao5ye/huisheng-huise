# 绘声绘色 安装：复制到本机程序目录，创建桌面和开始菜单快捷方式。不需要管理员权限。
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = '安装 绘声绘色' } catch { }

function Done([string]$msg, [string]$color) {
  Write-Host ''
  Write-Host $msg -ForegroundColor $color
  Write-Host ''
  try { [void](Read-Host '按回车键关闭此窗口') } catch { }
}

try {
  $Src = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
  $Dst = Join-Path $env:LOCALAPPDATA 'Programs\TongHuiFang'

  Write-Host ''
  Write-Host '  正在安装 绘声绘色 ……' -ForegroundColor Cyan
  Write-Host ('  安装位置：' + $Dst)

  if ($Src.TrimEnd('\') -ne $Dst.TrimEnd('\')) {
    if (Test-Path $Dst) { try { Remove-Item -Path $Dst -Recurse -Force } catch { } }
    if (-not (Test-Path $Dst)) { [void](New-Item -ItemType Directory -Path $Dst -Force) }
    Copy-Item -Path (Join-Path $Src '*') -Destination $Dst -Recurse -Force
  }
  # 去掉“来自网络”的标记，避免每次启动都弹安全提示
  Get-ChildItem -Path $Dst -Recurse -File | ForEach-Object { try { Unblock-File -Path $_.FullName } catch { } }

  $Target = Join-Path $Dst 'Start.bat'
  $Icon   = Join-Path $Dst 'app\tonghuifang.ico'
  $shell  = New-Object -ComObject WScript.Shell
  $places = @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))
  foreach ($dir in $places) {
    if (-not (Test-Path $dir)) { continue }
    $old = Join-Path $dir '童绘坊.lnk'
    if (Test-Path $old) { Remove-Item $old -Force }   # 清理旧版名称的快捷方式
    $lnk = $shell.CreateShortcut((Join-Path $dir '绘声绘色.lnk'))
    $lnk.TargetPath = $Target
    $lnk.WorkingDirectory = $Dst
    $lnk.WindowStyle = 7
    $lnk.Description = '绘声绘色 儿童 AI 绘本工坊'
    if (Test-Path $Icon) { $lnk.IconLocation = $Icon + ',0' }
    $lnk.Save()
  }

  Write-Host ''
  Write-Host '  安装完成！桌面和开始菜单里已经有“绘声绘色”图标。' -ForegroundColor Green
  Write-Host '  现在为你启动一次，第一次使用请在首页保存 DeepSeek 和 MiniMax 两把密钥。'
  Write-Host '  卸载：打开安装位置，双击 Uninstall.bat。'
  Start-Process -FilePath $Target -WorkingDirectory $Dst -WindowStyle Minimized
  Start-Sleep -Seconds 5
} catch {
  Done ('  安装失败：' + $_.Exception.Message + '。可以改为直接双击 Start.bat 免安装运行。') 'Red'
}
