# 绘声绘色 Windows 本地服务
# 运行环境：Windows PowerShell 5.1（Windows 10/11 自带，无需安装任何软件）
# 作用：在本机 localhost 提供绘本页面，并代为调用 DeepSeek（文字）、Seedream / MiniMax（图片）与腾讯云语音合成（朗读）。
#      密钥用当前 Windows 账户加密（DPAPI）保存在 %APPDATA%\TongHuiFang\config.json，不进入浏览器。
param(
  [int]$Port = 17860,
  [int]$IdleSeconds = 180,
  [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
try { $Host.UI.RawUI.WindowTitle = '绘声绘色 本地服务（关闭此窗口即退出）' } catch { }

$AppDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebFile = Join-Path $AppDir 'web\index.html'
$CfgDir  = Join-Path $env:APPDATA 'TongHuiFang'
$CfgFile = Join-Path $CfgDir 'config.json'

function Unprotect-Key([string]$enc) {
  if ([string]::IsNullOrEmpty($enc)) { return '' }
  try {
    $ss = ConvertTo-SecureString $enc
    $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
  } catch { return '' }
}

function Wait-Exit([string]$msg) {
  Write-Host ''
  Write-Host $msg -ForegroundColor Red
  Write-Host ''
  try { [void](Read-Host '按回车键关闭此窗口') } catch { }
  exit 1
}

if (-not (Test-Path $WebFile)) { Wait-Exit ('找不到页面文件：' + $WebFile + '。请确认解压完整，没有移动 app 文件夹里的内容。') }

# 各请求线程共享的状态
$S = [hashtable]::Synchronized(@{})
$S.Token    = [guid]::NewGuid().ToString('N')
$S.WebFile  = $WebFile
$S.CfgDir   = $CfgDir
$S.CfgFile  = $CfgFile
$S.DsEnc    = ''
$S.MmEnc    = ''
$S.DsKey    = ''
$S.MmKey    = ''
$S.ArkEnc   = ''
$S.ArkKey   = ''
$S.TcIdEnc  = ''
$S.TcId     = ''
$S.TcKeyEnc = ''
$S.TcKey    = ''
$S.ArkUrl   = 'https://ark.cn-beijing.volces.com/api/v3/images/generations'
$S.TtsHost  = 'tts.tencentcloudapi.com'
$S.DsBase   = 'https://api.deepseek.com'
$S.MmUrl    = 'https://api.minimaxi.com/v1/image_generation'
if ($env:THF_DEEPSEEK_BASE) { $S.DsBase = $env:THF_DEEPSEEK_BASE.TrimEnd('/') }
if ($env:THF_MINIMAX_URL)   { $S.MmUrl  = $env:THF_MINIMAX_URL }
if ($env:THF_ARK_URL)       { $S.ArkUrl = $env:THF_ARK_URL }
$S.LastPing = Get-Date

if (Test-Path $CfgFile) {
  try {
    $c = Get-Content -Path $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $S.DsEnc = [string]$c.deepseek
    $S.MmEnc = [string]$c.minimax
    $S.DsKey = Unprotect-Key $S.DsEnc
    $S.MmKey = Unprotect-Key $S.MmEnc
    $S.ArkEnc   = [string]$c.ark
    $S.TcIdEnc  = [string]$c.tcId
    $S.TcKeyEnc = [string]$c.tcKey
    $S.ArkKey   = Unprotect-Key $S.ArkEnc
    $S.TcId     = Unprotect-Key $S.TcIdEnc
    $S.TcKey    = Unprotect-Key $S.TcKeyEnc
  } catch {
    Write-Host '配置文件读取失败，将按未保存密钥处理。' -ForegroundColor Yellow
  }
}

# 找一个空闲端口（只监听本机 localhost，不需要管理员权限，局域网其他电脑无法访问）
$listener = $null
for ($p = $Port; $p -lt ($Port + 20); $p++) {
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add('http://localhost:' + $p + '/')
  try { $l.Start(); $listener = $l; $S.Port = $p; break }
  catch { try { $l.Close() } catch { } }
}
if (-not $listener) { Wait-Exit ('端口 ' + $Port + ' 到 ' + ($Port + 19) + ' 都被占用，无法启动。请重启电脑后再试。') }

# 每个请求在独立线程里处理，长时间的生成不会卡住其他请求
$Handler = {
  param($ctx, $S)
  $ErrorActionPreference = 'Stop'
  $req = $ctx.Request
  $res = $ctx.Response

  function Send-Bytes([int]$code, [string]$type, [byte[]]$bytes) {
    $res.StatusCode = $code
    $res.ContentType = $type
    $res.AddHeader('Cache-Control', 'no-store')
    $res.AddHeader('X-Content-Type-Options', 'nosniff')
    if ($null -eq $bytes) { $bytes = New-Object byte[] 0 }
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
  }
  function Send-Json([int]$code, $obj) {
    $txt = $obj | ConvertTo-Json -Compress -Depth 6
    Send-Bytes $code 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($txt))
  }
  function Get-Status {
    return [ordered]@{
      mode      = 'local'
      text      = ($S.DsKey -ne '')
      image     = ($S.MmKey -ne '')
      ark       = ($S.ArkKey -ne '')
      tts       = ($S.TcId -ne '' -and $S.TcKey -ne '')
      keys      = [ordered]@{ tcId = ($S.TcId -ne ''); tcKey = ($S.TcKey -ne '') }
      textModel = 'deepseek-v4-flash'
      writeModel = 'deepseek-v4-pro'
      needCode  = $false
      codeOk    = $true
    }
  }
  function Protect-Key([string]$t) {
    if ([string]::IsNullOrEmpty($t)) { return '' }
    return (ConvertTo-SecureString $t -AsPlainText -Force | ConvertFrom-SecureString)
  }
  function Save-Config {
    if (-not (Test-Path $S.CfgDir)) { [void](New-Item -ItemType Directory -Path $S.CfgDir) }
    $o = [ordered]@{ deepseek = $S.DsEnc; minimax = $S.MmEnc; ark = $S.ArkEnc; tcId = $S.TcIdEnc; tcKey = $S.TcKeyEnc }
    $o | ConvertTo-Json | Set-Content -Path $S.CfgFile -Encoding UTF8
  }
  function Invoke-Upstream([string]$method, [string]$url, [string]$key, [byte[]]$body, [hashtable]$extra, [string]$ctype) {
    $resp = $null
    try {
      $wr = [System.Net.HttpWebRequest]::Create($url)
      $wr.Method = $method
      $wr.Accept = 'application/json'
      $wr.Timeout = 300000
      $wr.ReadWriteTimeout = 300000
      if ($key) { $wr.Headers.Add('Authorization', 'Bearer ' + $key) }
      if ($null -ne $extra) { foreach ($k in $extra.Keys) { $wr.Headers.Add([string]$k, [string]$extra[$k]) } }
      if ($null -ne $body -and $body.Length -gt 0) {
        if ($ctype) { $wr.ContentType = $ctype } else { $wr.ContentType = 'application/json' }
        $wr.ContentLength = $body.Length
        $rs = $wr.GetRequestStream()
        $rs.Write($body, 0, $body.Length)
        $rs.Close()
      }
      $resp = $wr.GetResponse()
    } catch {
      $ex = $_.Exception
      while ($null -ne $ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
      if ($null -ne $ex -and $null -ne $ex.Response) { $resp = $ex.Response }
      else { return [pscustomobject]@{ Code = 502; Bytes = [Text.Encoding]::UTF8.GetBytes('{"error":"network"}') } }
    }
    $code = [int]$resp.StatusCode
    $ms = New-Object System.IO.MemoryStream
    $st = $resp.GetResponseStream()
    $st.CopyTo($ms)
    $st.Close()
    $resp.Close()
    return [pscustomobject]@{ Code = $code; Bytes = $ms.ToArray() }
  }
  # 腾讯云 API 3.0 签名（TC3-HMAC-SHA256），与赛珍珠讲解机器人使用的算法一致
  function Get-Sha256Hex([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
    return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
  }
  function Get-HmacBytes([byte[]]$hkey, [string]$msg) {
    $hm = New-Object System.Security.Cryptography.HMACSHA256
    $hm.Key = $hkey
    try { $out = $hm.ComputeHash([Text.Encoding]::UTF8.GetBytes($msg)) } finally { $hm.Dispose() }
    return ,$out
  }
  function Invoke-Tc3([string]$secretId, [string]$secretKey, [string]$tcHost, [string]$service, [string]$action, [string]$version, [string]$payload) {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $date = [DateTimeOffset]::FromUnixTimeSeconds($ts).UtcDateTime.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $ct = 'application/json; charset=utf-8'
    $canonical = 'POST' + "`n" + '/' + "`n" + "`n" + 'content-type:' + $ct + "`n" + 'host:' + $tcHost + "`n" + "`n" + 'content-type;host' + "`n" + (Get-Sha256Hex $payload)
    $scope = $date + '/' + $service + '/tc3_request'
    $toSign = 'TC3-HMAC-SHA256' + "`n" + $ts + "`n" + $scope + "`n" + (Get-Sha256Hex $canonical)
    $kDate    = Get-HmacBytes ([Text.Encoding]::UTF8.GetBytes('TC3' + $secretKey)) $date
    $kService = Get-HmacBytes $kDate $service
    $kSigning = Get-HmacBytes $kService 'tc3_request'
    $sig = ((Get-HmacBytes $kSigning $toSign) | ForEach-Object { $_.ToString('x2') }) -join ''
    $hdrs = @{
      'Authorization'  = 'TC3-HMAC-SHA256 Credential=' + $secretId + '/' + $scope + ', SignedHeaders=content-type;host, Signature=' + $sig
      'X-TC-Action'    = $action
      'X-TC-Version'   = $version
      'X-TC-Timestamp' = [string]$ts
    }
    return (Invoke-Upstream 'POST' ('https://' + $tcHost) '' ([Text.Encoding]::UTF8.GetBytes($payload)) $hdrs $ct)
  }

  try {
    $hostHeader = [string]$req.Headers['Host']
    if ($hostHeader -ne ('localhost:' + $S.Port) -and $hostHeader -ne ('127.0.0.1:' + $S.Port)) { Send-Json 403 @{ error = 'host' }; return }
    $path = $req.Url.AbsolutePath

    if ($req.HttpMethod -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
      # 只替换第一处占位符（页面 meta 标签里的那一处）
      $rawHtml = [IO.File]::ReadAllText($S.WebFile, [Text.Encoding]::UTF8)
      $rx = New-Object System.Text.RegularExpressions.Regex('__THF_TOKEN__')
      $html = $rx.Replace($rawHtml, $S.Token, 1)
      Send-Bytes 200 'text/html; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($html))
      return
    }
    if ($path -eq '/favicon.ico') { Send-Bytes 204 'text/plain' $null; return }
    if ($path -eq '/config.js') { Send-Bytes 200 'application/javascript; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes("window.THF_API = '';")); return }
    if (-not $path.StartsWith('/api/')) { Send-Json 404 @{ error = 'not_found' }; return }

    # 每次启动生成的随机口令只写在页面里，其他网站拿不到，也就不能冒用本地服务
    if ([string]$req.Headers['X-App-Token'] -ne $S.Token) { Send-Json 403 @{ error = 'token' }; return }
    $S.LastPing = Get-Date

    if ($path -eq '/api/status' -or $path -eq '/api/ping') { Send-Json 200 (Get-Status); return }

    if ($path -eq '/api/test') {
      if ($S.DsKey -eq '') { Send-Json 412 @{ error = 'no_key' }; return }
      $r = Invoke-Upstream 'GET' ($S.DsBase + '/models') $S.DsKey $null
      $msg = ''
      if ($r.Code -eq 401) { $msg = '密钥无效' }
      elseif ($r.Code -eq 502) { $msg = '连不上 DeepSeek，请检查网络' }
      elseif ($r.Code -ne 200) { $msg = '接口返回 ' + $r.Code }
      Send-Json 200 ([ordered]@{ ok = ($r.Code -eq 200); msg = $msg })
      return
    }

    if ($req.HttpMethod -ne 'POST') { Send-Json 405 @{ error = 'method' }; return }
    $buf = New-Object System.IO.MemoryStream
    $req.InputStream.CopyTo($buf)
    $body = $buf.ToArray()

    if ($path -eq '/api/config') {
      $j = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json
      $names = @($j.PSObject.Properties | ForEach-Object { $_.Name })
      if ($names -contains 'deepseekKey') { $S.DsKey = ([string]$j.deepseekKey).Trim(); $S.DsEnc = Protect-Key $S.DsKey }
      if ($names -contains 'minimaxKey')  { $S.MmKey = ([string]$j.minimaxKey).Trim();  $S.MmEnc = Protect-Key $S.MmKey }
      if ($names -contains 'arkKey')      { $S.ArkKey = ([string]$j.arkKey).Trim();     $S.ArkEnc = Protect-Key $S.ArkKey }
      if ($names -contains 'tcId')        { $S.TcId = ([string]$j.tcId).Trim();         $S.TcIdEnc = Protect-Key $S.TcId }
      if ($names -contains 'tcKey')       { $S.TcKey = ([string]$j.tcKey).Trim();       $S.TcKeyEnc = Protect-Key $S.TcKey }
      Save-Config
      Send-Json 200 (Get-Status)
      return
    }
    if ($path -eq '/api/deepseek/chat/completions') {
      if ($S.DsKey -eq '') { Send-Json 412 @{ error = 'no_key' }; return }
      $r = Invoke-Upstream 'POST' ($S.DsBase + '/chat/completions') $S.DsKey $body
      Send-Bytes $r.Code 'application/json; charset=utf-8' $r.Bytes
      return
    }
    if ($path -eq '/api/seedream/images/generations') {
      if ($S.ArkKey -eq '') { Send-Json 412 @{ error = 'no_key' }; return }
      $r = Invoke-Upstream 'POST' $S.ArkUrl $S.ArkKey $body
      Send-Bytes $r.Code 'application/json; charset=utf-8' $r.Bytes
      return
    }
    if ($path -eq '/api/tts') {
      if ($S.TcId -eq '' -or $S.TcKey -eq '') { Send-Json 412 @{ error = 'no_key' }; return }
      $j = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json
      $text = ([string]$j.text).Trim()
      if ($text.Length -eq 0 -or $text.Length -gt 150) { Send-Json 400 @{ error = 'bad_text' }; return }
      $voice = 403011
      $vv = 0
      if ([int]::TryParse([string]$j.voice, [ref]$vv) -and $vv -gt 0) { $voice = $vv }
      $speed = 0.0
      $sp = 0.0
      if ([double]::TryParse([string]$j.speed, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$sp)) { $speed = [Math]::Max(-2.0, [Math]::Min(6.0, $sp)) }
      $payload = ([ordered]@{ Text = $text; SessionId = [guid]::NewGuid().ToString(); VoiceType = $voice; Codec = 'mp3'; SampleRate = 24000; Speed = $speed; Volume = 0; PrimaryLanguage = 1 }) | ConvertTo-Json -Compress
      $r = Invoke-Tc3 $S.TcId $S.TcKey $S.TtsHost 'tts' 'TextToVoice' '2019-08-23' $payload
      $code = $r.Code
      if ($code -ne 200) { $code = 502 }
      Send-Bytes $code 'application/json; charset=utf-8' $r.Bytes
      return
    }
    if ($path -eq '/api/minimax/image_generation') {
      if ($S.MmKey -eq '') { Send-Json 412 @{ error = 'no_key' }; return }
      $r = Invoke-Upstream 'POST' $S.MmUrl $S.MmKey $body
      Send-Bytes $r.Code 'application/json; charset=utf-8' $r.Bytes
      return
    }
    Send-Json 404 @{ error = 'not_found' }
  } catch {
    try { Send-Json 500 ([ordered]@{ error = 'server'; detail = $_.Exception.Message }) } catch { }
  }
}

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
try { $iss.ExecutionPolicy = 'Bypass' } catch { }
$pool = [runspacefactory]::CreateRunspacePool(1, 10, $iss, $Host)
$pool.Open()
$jobs = New-Object System.Collections.ArrayList
$url = 'http://localhost:' + $S.Port + '/'

Write-Host ''
Write-Host '  绘声绘色 本地服务已启动' -ForegroundColor Green
Write-Host ('  地址：' + $url)
Write-Host ('  DeepSeek：' + $(if ($S.DsKey) { '已保存' } else { '未保存' }) + '    Seedream：' + $(if ($S.ArkKey) { '已保存' } else { '未保存' }) + '    MiniMax：' + $(if ($S.MmKey) { '已保存' } else { '未保存' }) + '    腾讯云语音：' + $(if ($S.TcId -and $S.TcKey) { '已保存' } else { '未保存' }))
Write-Host '  关闭绘本窗口约 3 分钟后，本服务会自动退出；也可以直接关闭这个窗口。'
Write-Host ''

if (-not $NoBrowser) {
  $edge = @(
    ('' + ${env:ProgramFiles(x86)} + '\Microsoft\Edge\Application\msedge.exe'),
    ('' + $env:ProgramFiles + '\Microsoft\Edge\Application\msedge.exe'),
    ('' + $env:LOCALAPPDATA + '\Microsoft\Edge\Application\msedge.exe')
  ) | Where-Object { $_.Length -gt 40 -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  try {
    if ($edge) { Start-Process -FilePath $edge -ArgumentList @('--app=' + $url, '--window-size=1280,900') }
    else { Start-Process $url }
  } catch {
    Write-Host ('  没能自动打开浏览器，请手动在浏览器里打开：' + $url) -ForegroundColor Yellow
  }
}

$stop = $false
try {
  while (-not $stop) {
    $ar = $listener.BeginGetContext($null, $null)
    while (-not $ar.AsyncWaitHandle.WaitOne(1000)) {
      for ($i = $jobs.Count - 1; $i -ge 0; $i--) {
        $jb = $jobs[$i]
        if ($jb.H.IsCompleted) {
          try { [void]$jb.P.EndInvoke($jb.H) } catch { }
          $jb.P.Dispose()
          $jobs.RemoveAt($i)
        }
      }
      if (((Get-Date) - $S.LastPing).TotalSeconds -gt $IdleSeconds) { $stop = $true; break }
    }
    if ($stop) { break }
    $ctx = $listener.EndGetContext($ar)
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($Handler.ToString()).AddArgument($ctx).AddArgument($S)
    [void]$jobs.Add(@{ P = $ps; H = $ps.BeginInvoke() })
  }
} catch {
  Wait-Exit ('本地服务出错：' + $_.Exception.Message)
} finally {
  try { $listener.Stop(); $listener.Close() } catch { }
  try { $pool.Close() } catch { }
}
