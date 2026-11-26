@echo off
setlocal
cd /d "%~dp0"
start "TongHuiFang" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\server.ps1"
