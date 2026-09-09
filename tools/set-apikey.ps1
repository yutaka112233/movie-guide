# ============================================================
#  set-apikey.ps1 - TMDb の APIキーを config.local.json に保存する
#  ※ 通常は set-apikey.bat から呼ばれます。
#
#  やっていること:
#    1. キーを入力してもらう
#    2. 実際に TMDb に問い合わせて、そのキーが使えるか確認する
#    3. 問題なければ config.local.json に保存する
# ============================================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$configPath = Join-Path $root 'config.local.json'

# PowerShell 5.1 は既定で古いTLSを使うため、明示的に TLS1.2 を有効にする
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Pause-Exit {
    param([int]$Code = 0)
    Write-Host ""
    Read-Host "Enter キーを押すと閉じます"
    exit $Code
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   TMDb APIキーの設定" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  映画のポスター画像を取得するためのキーを保存します。"
Write-Host "  キーの取り方は README.md の「3. TMDbのAPIキーを取得する」を見てください。"
Write-Host ""

# --- すでに設定済みかを確認 ---
if (Test-Path $configPath) {
    try {
        $cur = Get-Content -Raw -Encoding UTF8 -Path $configPath | ConvertFrom-Json
        $curKey = [string]$cur.tmdbApiKey
    } catch {
        $curKey = ''
    }
    if ($curKey.Length -ge 8) {
        $masked = $curKey.Substring(0, 4) + ('*' * ($curKey.Length - 8)) + $curKey.Substring($curKey.Length - 4)
        Write-Host "  すでにキーが設定されています: $masked" -ForegroundColor Yellow
        Write-Host ""
        $ans = Read-Host "  入れ直しますか？ (y = 入れ直す / それ以外 = やめる)"
        if ($ans -ne 'y' -and $ans -ne 'Y') {
            Write-Host ""
            Write-Host "  変更せずに終了しました。" -ForegroundColor Gray
            Pause-Exit 0
        }
        Write-Host ""
    }
}

# --- 入力 ---
Write-Host "  TMDbの「API Key (v3 auth)」を貼り付けて、Enter を押してください。"
Write-Host "  （右クリックで貼り付けできます。英数字32文字です）"
Write-Host ""
$key = Read-Host "  APIキー"
$key = ($key -replace '\s', '')

if ([string]::IsNullOrWhiteSpace($key)) {
    Write-Host ""
    Write-Host "  何も入力されなかったため、中止しました。" -ForegroundColor Yellow
    Pause-Exit 1
}

# --- 形式チェック ---
if ($key.StartsWith('eyJ')) {
    Write-Host ""
    Write-Host "  これは「API Read Access Token (v4 auth)」のようです。" -ForegroundColor Yellow
    Write-Host "  このアプリが使うのは、その上にある短いほうの" -ForegroundColor Yellow
    Write-Host "  「API Key (v3 auth)」（英数字32文字）です。" -ForegroundColor Yellow
    Write-Host "  TMDbの設定画面に戻って、v3 のほうをコピーし直してください。" -ForegroundColor Yellow
    Pause-Exit 1
}

if ($key -notmatch '^[0-9a-fA-F]{32}$') {
    Write-Host ""
    Write-Host "  入力された文字列が、TMDbのAPIキーの形式（英数字32文字）と違うようです。" -ForegroundColor Yellow
    Write-Host "  入力されたもの: $key" -ForegroundColor Gray
    Write-Host ""
    $ans = Read-Host "  それでもこのまま試しますか？ (y = 試す / それ以外 = やめる)"
    if ($ans -ne 'y' -and $ans -ne 'Y') { Pause-Exit 1 }
}

# --- 実際にTMDbへ問い合わせて確認 ---
Write-Host ""
Write-Host "  TMDbに接続して、キーが使えるか確認しています..." -ForegroundColor Cyan

$testUrl = "https://api.themoviedb.org/3/movie/550?api_key=$key&language=ja-JP"
try {
    $res = Invoke-RestMethod -Uri $testUrl -Method Get -TimeoutSec 20
    Write-Host ""
    Write-Host "  OK: キーは有効です。" -ForegroundColor Green
    Write-Host "  （テスト取得したタイトル: $($res.title)）" -ForegroundColor Gray
} catch {
    $status = $null
    try { $status = [int]$_.Exception.Response.StatusCode } catch { }

    Write-Host ""
    if ($status -eq 401) {
        Write-Host "  NG: TMDbに拒否されました（401）。キーが違う可能性があります。" -ForegroundColor Red
        Write-Host "  TMDbの設定画面から「API Key (v3 auth)」をコピーし直してください。" -ForegroundColor Red
    } else {
        Write-Host "  確認できませんでした: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ネットワークが切れているだけの可能性もあります。" -ForegroundColor Yellow
    }
    Write-Host ""
    $ans = Read-Host "  それでもこのキーを保存しますか？ (y = 保存する / それ以外 = やめる)"
    if ($ans -ne 'y' -and $ans -ne 'Y') {
        Write-Host ""
        Write-Host "  保存せずに終了しました。" -ForegroundColor Gray
        Pause-Exit 1
    }
}

# --- 保存 ---
$json = @"
{
  "tmdbApiKey": "$key"
}
"@
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "  保存しました: config.local.json" -ForegroundColor Green
Write-Host "  （このファイルは .gitignore で除外してあるので、GitHubには上がりません）" -ForegroundColor Gray
Write-Host ""
Write-Host "  次は update.bat をダブルクリックしてください。" -ForegroundColor Cyan
Write-Host "  ポスター画像つきでデータが入り直します（10〜30分ほどかかります）。" -ForegroundColor Cyan
Pause-Exit 0
