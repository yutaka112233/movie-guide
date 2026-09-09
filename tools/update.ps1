# ============================================================
#  update.ps1 - movies.json を隔週で自動更新する
#  ※ 直接これを実行してもよいですが、通常は update.bat から呼ばれます。
# ============================================================

# ---------------- 設定 ----------------

# Claude Code の実行ファイル。空なら自動で探します。
# 自動検出がうまくいかない場合はここにフルパスを書いてください。
$ClaudeBin = ''

# 権限プロンプトで止まってしまう場合は $true にしてください。
# （このフォルダ専用の自動実行のため許容できますが、意味は理解した上で使ってください）
$SkipPermissions = $false

# Claude の実行を打ち切るまでの上限（分）
# 映画は1本ずつ公式サイトを見て特典・ムビチケを確認するため、週末イベントより長めにしてある。
$TimeoutMinutes = 35

# ログの保存日数
$LogRetentionDays = 180

# 成功後に GitHub へ自動 push するか。
# リポジトリが未作成（.git が無い）、または git remote が未設定の場合は
# この値に関わらず自動的にスキップされる（README『GitHub Pagesで公開する』参照）。
$AutoPushToGitHub = $true

# --------------------------------------

$ErrorActionPreference = 'Stop'
# このスクリプトは tools\ の中にあるので、その親フォルダが作業対象になる
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $root

$jsonPath   = Join-Path $root 'movies.json'
$jsPath     = Join-Path $root 'movies.js'
$backupPath = Join-Path $root 'movies.json.bak'
$promptPath = Join-Path $root 'prompt.md'
$configPath = Join-Path $root 'config.local.json'
$logDir     = Join-Path $root 'logs'
$today      = Get-Date -Format 'yyyy-MM-dd'
$logPath    = Join-Path $logDir "$today.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Show-Toast {
    param([string]$Title, [string]$Message, [string]$Level = 'Info')
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = if ($Level -eq 'Error') {
            [System.Drawing.SystemIcons]::Error
        } else {
            [System.Drawing.SystemIcons]::Information
        }
        $icon.Visible = $true
        $tip = if ($Level -eq 'Error') {
            [System.Windows.Forms.ToolTipIcon]::Error
        } else {
            [System.Windows.Forms.ToolTipIcon]::Info
        }
        $icon.ShowBalloonTip(10000, $Title, $Message, $tip)
        Start-Sleep -Seconds 8
        $icon.Dispose()
    } catch {
        # 通知に失敗しても本処理は成功扱いのままにする
        Write-Host "通知の表示に失敗しました: $($_.Exception.Message)"
    }
}

# movies.json が「壊れていないか」を検証する。
# 問題なければ $null、問題があればその内容を文字列で返す。
function Get-JsonProblem {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return 'movies.json が存在しません' }

    $raw = Get-Content -Raw -Encoding UTF8 -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'movies.json が空です' }

    try {
        $j = $raw | ConvertFrom-Json
    } catch {
        return "JSONとして解析できません: $($_.Exception.Message)"
    }

    if (-not $j.updatedAt)    { return 'updatedAt がありません' }
    if ($j.updatedAt -notmatch '^\d{4}-\d{2}-\d{2}$') { return "updatedAt の形式が不正です: $($j.updatedAt)" }
    if (-not $j.targetPeriod) { return 'targetPeriod がありません' }
    if (-not $j.criteria)     { return 'criteria がありません' }
    if ($null -eq $j.movies)  { return 'movies がありません' }

    $movies = @($j.movies)
    if ($movies.Count -lt 1) { return 'movies が空です' }

    for ($i = 0; $i -lt $movies.Count; $i++) {
        $m = $movies[$i]
        if ([string]::IsNullOrWhiteSpace([string]$m.title)) { return "movies[$i] の title が空です" }
        if (@('kids', 'adult', 'both') -notcontains [string]$m.audience) {
            return "movies[$i] ($($m.title)) の audience が不正です: $($m.audience)"
        }
        if (@('now', 'soon') -notcontains [string]$m.status) {
            return "movies[$i] ($($m.title)) の status が不正です: $($m.status)"
        }
        # ポスターは TMDb 以外のドメインを入れない約束にしている（prompt.md 参照）
        $p = [string]$m.posterUrl
        if ($p -and $p -notmatch '^https://image\.tmdb\.org/') {
            return "movies[$i] ($($m.title)) の posterUrl が TMDb の画像URLではありません: $p"
        }
    }
    return $null   # 問題なし
}

# TMDb の APIキーが movies.json に混入していないか確認する。
# config.local.json は .gitignore で除外しているが、movies.json は公開リポジトリに
# push されるため、キーが紛れ込んだまま公開されるのを防ぐ。
function Test-KeyLeak {
    param([string]$JsonPath, [string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        $cfg = Get-Content -Raw -Encoding UTF8 -Path $ConfigPath | ConvertFrom-Json
    } catch {
        Write-Log "config.local.json を読めませんでした（キー混入チェックはスキップ）: $($_.Exception.Message)" 'Yellow'
        return $null
    }
    $key = [string]$cfg.tmdbApiKey
    if ([string]::IsNullOrWhiteSpace($key) -or $key.Length -lt 8) { return $null }

    $raw = Get-Content -Raw -Encoding UTF8 -Path $JsonPath
    if ($raw -like "*$key*") {
        return 'movies.json に TMDb のAPIキーが含まれています。公開リポジトリに push される前に取り除いてください。'
    }
    return $null
}

# index.html をダブルクリック（file://）で開いたときは、ブラウザの制限で
# movies.json を fetch できない。そのため同じ内容を movies.js としても書き出し、
# index.html はそちらを <script> で読み込めるようにしている。
function Write-JsMirror {
    param([string]$JsonPath, [string]$JsPath, [string]$VarName)
    $name = Split-Path -Leaf $JsonPath
    $raw = Get-Content -Raw -Encoding UTF8 -Path $JsonPath
    $body = "/* 自動生成ファイル - 直接編集しないでください。$name から自動生成されます。 */`r`n" +
            "window.$VarName = $raw;`r`n"
    [System.IO.File]::WriteAllText($JsPath, $body, (New-Object System.Text.UTF8Encoding($false)))
}

function Find-ClaudeBin {
    if ($ClaudeBin -and (Test-Path $ClaudeBin)) { return $ClaudeBin }
    if ($env:CLAUDE_BIN -and (Test-Path $env:CLAUDE_BIN)) { return $env:CLAUDE_BIN }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Claude デスクトップアプリに同梱されている claude.exe を探す。
    #
    # 注意: デスクトップアプリは MSIX（パッケージ化アプリ）のため、%APPDATA%\Claude は
    # アプリの中からしか見えない仮想パスになっている。タスクスケジューラはコンテナの外で
    # 動くので、そこからは実体パス（LocalCache 配下）を見に行く必要がある。
    # 両方を候補にすることで、手動実行でも自動実行でも見つかるようにしている。
    $bases = @()
    $bases += (Join-Path $env:APPDATA 'Claude\claude-code')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem -Path $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
            ForEach-Object { $bases += (Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude-code') }
    }

    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        $found = Get-ChildItem -Path $base -Filter 'claude.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    Write-Log "探索したパス: $($bases -join ' / ')" 'Yellow'
    return $null
}

# 成功後に呼ぶ。movies.json / movies.js の変更を GitHub へ push する。
# 以下の場合は「失敗」ではなく静かにスキップする：
#   - まだ git リポジトリになっていない（.git が無い）
#   - リモート origin が設定されていない
#   - 前回から変更が無い
# push 自体が失敗しても、隔週更新そのものは成功扱いのままにする。
function Push-ToGitHub {
    param([string]$Root, [string]$TargetPeriod, [int]$Count)

    # このスクリプト全体は $ErrorActionPreference = 'Stop' で動いている。
    # git コマンドを 2>&1 で受けると、PowerShell 5.1 は stderr の各行
    # （CRLF/LF変換の警告など、実際にはエラーではないもの）を NativeCommandError
    # として扱うため、'Stop' 環境下では警告1行でこの関数全体が例外終了してしまう。
    # ここだけ 'Continue' に戻し、警告はログに残しつつ処理を続けられるようにする。
    $ErrorActionPreference = 'Continue'

    if (-not (Test-Path (Join-Path $Root '.git'))) {
        Write-Log "このフォルダはまだGitリポジトリではないため push をスキップします（README『iPhoneで見る／GitHub Pagesで公開する』参照）" 'Gray'
        return
    }

    Push-Location $Root
    try {
        $remotes = git remote 2>&1
        if ($LASTEXITCODE -ne 0 -or -not ($remotes -contains 'origin')) {
            Write-Log "git remote 'origin' が未設定のため push をスキップします" 'Gray'
            return
        }

        git add -A -- . ':!logs' ':!movies.json.bak' ':!config.local.json' 2>&1 | ForEach-Object { Write-Log "  git: $_" 'Gray' }

        $status = git status --porcelain 2>&1
        if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
            Write-Log "GitHubへの変更なし（push スキップ）" 'Gray'
            return
        }

        $commitMsg = "隔週更新: $TargetPeriod ($Count 本) [$(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
        git commit -m $commitMsg 2>&1 | ForEach-Object { Write-Log "  git: $_" 'Gray' }
        if ($LASTEXITCODE -ne 0) {
            Write-Log "git commit に失敗しました。push は行いません。" 'Yellow'
            return
        }

        $pushOut = git push 2>&1
        $pushOut | ForEach-Object { Write-Log "  git: $_" 'Gray' }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "GitHubへ push しました" 'Green'
        } else {
            Write-Log "git push に失敗しました（終了コード $LASTEXITCODE）。ネットワークまたは認証情報を確認してください。" 'Yellow'
        }
    } catch {
        Write-Log "GitHub push処理でエラーが発生しました（更新自体は成功扱いのまま続けます）: $($_.Exception.Message)" 'Yellow'
    } finally {
        Pop-Location
    }
}

# ============================================================
#  本処理
# ============================================================

Add-Content -Path $logPath -Value "" -Encoding UTF8
Write-Log "==================== 隔週更新 開始 ====================" 'Cyan'
Write-Log "作業フォルダ: $root"

$exitCode = 0

try {
    # --- 0. 前提チェック ---
    if (-not (Test-Path $promptPath)) { throw "prompt.md が見つかりません: $promptPath" }

    if (-not (Test-Path $configPath)) {
        Write-Log "config.local.json がありません。ポスター画像なしで更新します（README『TMDbのAPIキー』参照）" 'Yellow'
    }

    $claude = Find-ClaudeBin
    if (-not $claude) {
        throw "Claude Code の実行ファイルが見つかりませんでした。README.md の「Claude Code CLI の準備」を参照してください。"
    }
    Write-Log "Claude Code: $claude"

    # --- 1. バックアップ ---
    if (Test-Path $jsonPath) {
        Copy-Item -Path $jsonPath -Destination $backupPath -Force
        Write-Log "バックアップを作成しました: movies.json.bak" 'Green'
    } else {
        Write-Log "movies.json が存在しないため、バックアップはスキップします" 'Yellow'
    }

    $before = if (Test-Path $jsonPath) {
        (Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json).updatedAt
    } else { $null }

    # --- 2. Claude Code を非対話モードで実行 ---
    $claudeArgs = @('-p', '--output-format', 'text')
    if ($SkipPermissions) {
        $claudeArgs += '--dangerously-skip-permissions'
    } else {
        $claudeArgs += @('--permission-mode', 'acceptEdits')
        $claudeArgs += @('--allowedTools', 'Read,Write,Edit,Glob,Grep,WebSearch,WebFetch')
    }

    $outFile = Join-Path $env:TEMP "mg_out_$PID.txt"
    $errFile = Join-Path $env:TEMP "mg_err_$PID.txt"

    Write-Log "Claude Code を実行します（最大 $TimeoutMinutes 分）..." 'Cyan'
    Write-Log "引数: $($claudeArgs -join ' ')"

    $proc = Start-Process -FilePath $claude `
                          -ArgumentList $claudeArgs `
                          -WorkingDirectory $root `
                          -RedirectStandardInput $promptPath `
                          -RedirectStandardOutput $outFile `
                          -RedirectStandardError $errFile `
                          -NoNewWindow -PassThru

    # PowerShell 5.1 では、ハンドルをここでキャッシュしておかないと
    # 終了後に $proc.ExitCode が取得できない。
    $null = $proc.Handle

    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        try { $proc.Kill() } catch { }
        throw "$TimeoutMinutes 分以内に完了しなかったため中断しました"
    }
    $proc.WaitForExit()
    $claudeExit = $proc.ExitCode
    Write-Log "Claude Code 終了コード: $claudeExit"

    # --- 3. 実行結果をログに保存 ---
    foreach ($pair in @(@('標準出力', $outFile), @('標準エラー出力', $errFile))) {
        $label = $pair[0]; $file = $pair[1]
        if ((Test-Path $file) -and (Get-Item $file).Length -gt 0) {
            Add-Content -Path $logPath -Value "`n---------- $label ----------" -Encoding UTF8
            Get-Content -Raw -Encoding UTF8 $file | Add-Content -Path $logPath -Encoding UTF8
        }
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }

    if ($claudeExit -ne 0) { throw "Claude Code が異常終了しました（終了コード $claudeExit）" }

    # --- 4. 検証 ---
    $problem = Get-JsonProblem -Path $jsonPath
    if ($problem) { throw "movies.json の検証に失敗しました: $problem" }

    $leak = Test-KeyLeak -JsonPath $jsonPath -ConfigPath $configPath
    if ($leak) { throw $leak }

    $j = Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json
    $movies = @($j.movies)
    $count  = $movies.Count
    $kids   = @($movies | Where-Object { $_.audience -eq 'kids'  -or $_.audience -eq 'both' }).Count
    $adult  = @($movies | Where-Object { $_.audience -eq 'adult' -or $_.audience -eq 'both' }).Count
    $ticket = @($movies | Where-Object { $_.mubichike -and $_.mubichike.available -eq $true }).Count
    $bonus  = @($movies | Where-Object { @($_.bonuses).Count -gt 0 }).Count
    $poster = @($movies | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.posterUrl) }).Count
    $needs  = @($movies | Where-Object { $_.needsCheck -eq $true }).Count

    Write-Log "検証OK: $count 本（大人 $adult / こども $kids）" 'Green'
    Write-Log "  対象期間: $($j.targetPeriod) / 次回更新: $($j.nextUpdate)"
    Write-Log "  ムビチケ販売中: $ticket 本 / 入場者特典あり: $bonus 本 / ポスター取得: $poster 本 / 要確認: $needs 本"

    if ($poster -eq 0) {
        Write-Log "注意: ポスター画像が1本も取得できていません。config.local.json の tmdbApiKey を確認してください。" 'Yellow'
    }

    # --- 5. index.html をダブルクリックで開けるように movies.js を生成 ---
    Write-JsMirror -JsonPath $jsonPath -JsPath $jsPath -VarName '__MOVIES__'
    Write-Log "movies.js を生成しました" 'Green'

    if ($j.updatedAt -eq $before) {
        Write-Log "注意: updatedAt が更新前と同じ（$before）です。中身が更新されていない可能性があります。" 'Yellow'
    }
    if ($j.isSampleData -eq $true) {
        Write-Log "注意: isSampleData が true のままです。サンプルデータが残っている可能性があります。" 'Yellow'
    }

    # --- 6. GitHub Pages 用に自動 push（設定済みの場合のみ） ---
    if ($AutoPushToGitHub) {
        Push-ToGitHub -Root $root -TargetPeriod $j.targetPeriod -Count $count
    }

    Write-Log "==================== 隔週更新 成功 ====================" 'Green'
    Show-Toast -Title '映画ガイド' `
               -Message "更新しました: $count 本（大人 $adult / こども $kids）`n特典あり $bonus 本 / ムビチケ $ticket 本$(if ($needs -gt 0) { "`n要確認: $needs 本" })"

} catch {
    $msg = $_.Exception.Message
    Write-Log "エラー: $msg" 'Red'

    # --- 復元 ---
    if (Test-Path $backupPath) {
        $bakProblem = Get-JsonProblem -Path $backupPath
        if ($bakProblem) {
            Write-Log "バックアップも壊れているため復元しませんでした: $bakProblem" 'Red'
        } else {
            Copy-Item -Path $backupPath -Destination $jsonPath -Force
            Write-Log "movies.json をバックアップから復元しました" 'Yellow'
            # 表示用の movies.js も復元後の内容に合わせ直す
            try {
                Write-JsMirror -JsonPath $jsonPath -JsPath $jsPath -VarName '__MOVIES__'
                Write-Log "movies.js も復元後の内容に更新しました" 'Yellow'
            } catch {
                Write-Log "movies.js の再生成に失敗しました: $($_.Exception.Message)" 'Red'
            }
        }
    } else {
        Write-Log "バックアップが無いため復元できませんでした" 'Red'
    }

    Write-Log "==================== 隔週更新 失敗 ====================" 'Red'
    Show-Toast -Title '映画ガイド（更新失敗）' `
               -Message "$msg`n詳細: logs\$today.log" -Level 'Error'
    $exitCode = 1
}

# --- 古いログの整理 ---
try {
    Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

exit $exitCode
