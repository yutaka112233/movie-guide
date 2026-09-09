# 映画ガイド（movie-guide）

大人向け・こども向け（小学生以下）の上映作品を、**ムビチケ前売券の販売期間**と
**入場者特典**を中心にまとめて表示するローカルWebアプリです。
2週間に1回、Claude Code が自動で情報を取り直します。

隣のフォルダにある `weekend-events`（週末おでかけイベント）と**同じ作りかた・同じ操作**です。
すでにそちらを使っている場合、新しく覚えることは「TMDbのAPIキー」だけです。

---

## 0. このPCの環境（確認済み）

| 項目 | 内容 |
| --- | --- |
| OS | Windows 11 Home |
| PowerShell | Windows PowerShell 5.1 |
| Git | インストール済み（`weekend-events` で使用中） |
| スケジューラ | **タスクスケジューラ** |
| ローカルサーバーのポート | **8766**（週末おでかけの 8765 とは別。同時に起動できます） |

---

## 1. ファイル構成

```
movie-guide/
├── index.html                  表示用ページ ★普段はこれを見る
├── movies.json                 映画データ（自動更新される本体）
├── movies.js                   movies.json と同じ内容の予備データ（自動生成）
├── prompt.md                   Claudeへの調査・更新指示書 ★条件を変えたいときはここ
├── update.bat                  隔週更新の入り口 ★データを取り直すときに使う
├── serve.bat                   ページを開く ★普段はこれをダブルクリック
├── set-apikey.bat              TMDb APIキーの設定 ★最初に1回だけ使う
├── icon-180.png                iPhoneホーム画面アイコン（180×180）
├── config.local.sample.json    APIキー設定のひな形（見本。編集しなくてよい）
├── config.local.json           あなたのTMDb APIキー（set-apikey.bat が作る／GitHubには上がりません）
├── .gitignore                  GitHubに上げたくないものの除外設定
├── tools/
│   ├── update.ps1              更新処理の本体（バックアップ・検証・復元・通知・push）
│   ├── set-apikey.ps1          APIキーの確認と保存
│   └── serve.ps1               ローカルサーバー
└── logs/                       実行ログ（90日ではなく180日保存）
```

### なぜファイルが2種類（.json と .js）あるのか

`index.html` を**ダブルクリックで開く**と、ブラウザの制限で `movies.json` を読み込めません。
そのため同じ内容を `movies.js` としても書き出し、そちらから読めるようにしています。
`movies.js` は `update.bat` が自動で作るので、手で編集しないでください。

---

## 2. 使い方（毎回これだけ）

1. **`serve.bat` をダブルクリック** → ブラウザで http://localhost:8766/ が開きます
2. 見終わったら、黒いウィンドウを閉じる

`index.html` を直接ダブルクリックしても表示できます（`serve.bat` が使えないときの予備手段）。

**iPhoneで見る場合：** GitHub Pagesでの公開設定が必要です。本README「9.」を参照してください。

### 画面でできること

| 操作 | 内容 |
| --- | --- |
| 上の3つの大きなタブ | **すべて / 大人向け / こども向け（小学生以下）** の切り替え |
| 絞り込み「公開」 | すべて / 公開中 / 近日公開。**どれか1つだけ**選べます（押すと前の選択が外れます） |
| 絞り込み「条件」 | ムビチケ販売中 / 入場者特典あり / 日本語吹替あり。**複数選ぶと「すべて満たす」**で絞り込みます。もう一度押すと解除 |
| 横浜周辺の劇場 | 絞り込みには使いません（横浜周辺で観られない作品はほぼ無いため）。確認できた場合だけ、カード内に劇場名を表示します |
| 🎁 入場者特典 | 黄色の枠で、カードの中でいちばん目立つように表示されます |
| 🎫 ムビチケ前売券 | 水色の枠で販売期間を表示。販売終了・未確認のときはグレーになります |
| ⚠️ 要確認 | 情報が確認できていない作品はカード全体がピンク色になり、理由が表示されます |

> **親子どちらでも楽しめる作品は、大人向け・こども向けの両方に出ます。**
> どちらか一方にしか出ない作品は、その対象に絞られているという意味です。

---

## 3. TMDbのAPIキーを取得する（最初に1回だけ）

ポスター画像は **TMDb（The Movie Database）** という映画データベースの無料APIから取得します。
非営利での利用が公式に認められており、配給会社のサイトから画像を直接借りてくるより安全です。

**キーが無くても更新は動きます**（ポスターの代わりに、色付きのタイトル表示になります）。
ポスターを出したい場合だけ、以下を行ってください。所要5分・無料です。

### 手順A：TMDbでキーを発行する（PCのブラウザで行ってください／スマホ非対応）

1. https://www.themoviedb.org/signup を開き、アカウントを作る
   - Username（好きな名前）・Password・Email を入れて登録
   - 登録後、**確認メールが届くのでリンクをクリックして有効化**する（これをしないとAPI申請に進めません）
2. ログインした状態で https://www.themoviedb.org/settings/api を開く
   - （画面から行く場合：右上の丸いアイコン →「Settings」→ 左メニュー「API」）
3. **「Request an API Key」**（または「Create」）をクリック
4. プランを選ぶ画面で **「Developer」** を選ぶ（無料。ずっと無料です）
5. 利用規約が出るので、下までスクロールして **「Accept」**
6. 申請フォームを埋める。個人利用なら次の内容で通ります

   | 項目 | 入れる内容 |
   | --- | --- |
   | Type of Use | **Personal** （無ければ Website） |
   | Application Name | `Movie Guide` |
   | Application URL | `https://localhost` （公開URLが無くてもこれでOK） |
   | Application Summary | `A personal, non-commercial page that lists movies currently showing in Japan for my family, with poster images from TMDB.` |
   | 住所・氏名など | 自分の情報を入れる（TMDbの管理用で、公開はされません） |

7. 送信すると、すぐに **API Key (v3 auth)** が発行されます
8. `https://www.themoviedb.org/settings/api` に **「API Key (v3 auth)」** という欄があるので、
   その **英数字32文字** をコピーする

> **重要：2種類のキーが表示されます。**
> - ✅ **API Key (v3 auth)** … 短い英数字32文字。**こちらを使います**
> - ❌ API Read Access Token (v4 auth) … `eyJ...` で始まるとても長い文字列。使いません

### 手順B：コピーしたキーをこのアプリに登録する

**`set-apikey.bat` をダブルクリック**してください。黒いウィンドウが開くので、

1. `APIキー:` と出たら、**右クリックで貼り付け** → Enter
2. 自動でTMDbに接続して、そのキーが本当に使えるか確認します
3. `OK: キーは有効です。` と出れば完了。`config.local.json` が自動で作られます

ファイルを手で作ったり、JSONを編集したりする必要はありません。
間違ったキー（v4のほう）を貼ってしまった場合も、その場で教えてくれます。

> **APIキーは他人に見せないでください。**
> `config.local.json` は `.gitignore` で除外してあるので GitHub には上がりません。
> さらに念のため、更新処理はキーが `movies.json` に混入していないかを毎回チェックし、
> 混入していたら更新を失敗扱いにして push を止めます。

---

## 4. Claude Code CLI の準備

`weekend-events` がすでに動いているなら、**この作業は不要**です（同じ仕組みを使います）。
初めて設定する場合は `weekend-events\README.md` の「3. Claude Code CLI の準備」を参照してください。

---

## 5. 手動で更新を試す

1. **`update.bat` をダブルクリック**
2. 黒いウィンドウで処理が進みます（**10〜30分ほどかかります**）
   - 作品ごとに公式サイトを見てムビチケ・特典を確認するため、週末おでかけより時間がかかります
3. 終わると `[OK] movies.json updated.` と表示され、通知が出ます
4. `serve.bat` でページを開き直すと、新しい内容になっています

処理中に何が起きているか：

| 段階 | 内容 |
| --- | --- |
| バックアップ | `movies.json.bak` に現在の内容を退避 |
| 実行 | `prompt.md` の指示で Claude Code が調査し `movies.json` を書き換える（最大35分） |
| 検証 | JSONとして妥当か／必須項目が揃っているか／ポスターURLがTMDb以外でないか／APIキーが混入していないか |
| 生成 | `movies.js` を作り直す |
| push | GitHubリポジトリが設定済みなら自動で push（未設定なら静かにスキップ） |
| 失敗時 | バックアップから自動で復元し、エラー通知を出す |

---

## 6. 隔週日曜 21時の自動実行

### いま何が登録されているかを見る

**画面で見る場合：** Windowsキー → `タスク スケジューラ` と入力して開く →
左のツリーで **「タスク スケジューラ ライブラリ」** をクリック。
一覧の中に `WeekendEvents-Update`（週末おでかけ）などが並んでいます。
選ぶと下に「トリガー（いつ動くか）」「操作（何を動かすか）」タブが出ます。

**コマンドで見る場合：** PowerShell に貼り付けて実行します。

```
Get-ScheduledTask | Where-Object TaskPath -eq '\' | Get-ScheduledTaskInfo | Format-Table TaskName, LastRunTime, LastTaskResult, NextRunTime -AutoSize
```

`LastTaskResult` が `0` なら前回は成功です。1つのタスクを詳しく見るなら：

```
schtasks /Query /TN "MovieGuide-Biweekly" /V /FO LIST
```

### 登録する

PowerShell を開き、次の1行を実行します（コピーしてそのまま貼り付けてください）。
週末おでかけと同じ形式で、黒いウィンドウが出ないように動きます。

```
schtasks /Create /TN "MovieGuide-Biweekly" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Users\mppwy\OneDrive\ドキュメント\クロードコード\movie-guide\tools\update.ps1\"" /SC WEEKLY /MO 2 /D SUN /ST 21:00 /F
```

| 項目 | 内容 |
| --- | --- |
| タスク名 | `MovieGuide-Biweekly` |
| 実行タイミング | **隔週（2週間に1回）日曜 21:00** |
| 最初の実行 | 登録後、最初に来る日曜の21:00 |
| 週末おでかけとの関係 | `WeekendEvents-Update` は毎週日曜20:00。1時間ずらしてあるので重なりません |
| 画面表示 | 出ません（`-WindowStyle Hidden`）。終わるとトースト通知が出ます |

### 今すぐ試しに動かす

```
schtasks /Run /TN "MovieGuide-Biweekly"
```

### 自動実行をやめる

```
schtasks /Delete /TN "MovieGuide-Biweekly" /F
```

### 注意点

- PCの電源が入っていてサインイン済みのときだけ動きます。日曜21時にPCが落ちていた場合は動きません
- 動かなかった週は、翌日以降に `update.bat` を手で実行すれば大丈夫です
- ページ上部には「最終更新から18日以上経つと黄色い警告バナー」が出るので、
  更新が滞ったことに気づけます

---

## 7. movies.json のデータ構造

`prompt.md` の「movies.json のデータ構造」に、全フィールドの意味と判定基準を書いてあります。
掲載条件（本数、対象エリア、どの情報源を見るかなど）を変えたいときも `prompt.md` を編集してください。

主なフィールド：

| フィールド | 意味 |
| --- | --- |
| `audience` | `kids`（こども向け）/ `adult`（大人向け）/ `both`（親子どちらでも） |
| `status` | `now`（公開中）/ `soon`（近日公開） |
| `mubichike` | ムビチケの販売状況。`available` が `true` のときだけ水色で販売期間を表示 |
| `bonuses` | 入場者特典の配列。第1弾・第2弾があれば分けて記載 |
| `theaters` | 横浜周辺で上映が確認できた劇場名 |
| `needsCheck` / `checkReason` | 確認できていないことがある場合の警告 |

---

## 8. 設定を変えたいとき

| やりたいこと | 変更する場所 |
| --- | --- |
| 掲載本数・対象・情報源を変える | `prompt.md` |
| 上映館の候補（横浜周辺の劇場）を増やす | `prompt.md` の「5. 横浜周辺で観られるかを調べる」 |
| GitHubへの自動pushを止める | `tools\update.ps1` の `$AutoPushToGitHub = $false` |
| 更新のタイムアウトを変える | `tools\update.ps1` の `$TimeoutMinutes` |
| 「情報が古い」警告が出るまでの日数 | `index.html` の `STALE_DAYS`（初期値18日） |
| ホーム画面アイコンを変える | `icon-180.png` を 180×180 の別画像に差し替える |
| ローカルサーバーのポート | `tools\serve.ps1` の `$port`（初期値8766） |

---

## 9. iPhoneで見る／GitHub Pagesで公開する

やり方は `weekend-events` とまったく同じです。違うのは**リポジトリ名だけ**。

1. https://github.com/new で **`movie-guide`** という名前の **Public** リポジトリを作る
   （Privateだと GitHub Pages が有料になります）
2. PowerShell で以下を実行（`<ユーザー名>` は自分のGitHubユーザー名に置き換え）

```
cd "C:\Users\mppwy\OneDrive\ドキュメント\クロードコード\movie-guide"
git init
git add -A
git commit -m "初回コミット"
git branch -M main
git remote add origin https://github.com/<ユーザー名>/movie-guide.git
git push -u origin main
```

3. GitHubのリポジトリ画面 → **Settings** → **Pages** →
   Branch を `main` / `/(root)` にして **Save**
4. 1〜2分待つと `https://<ユーザー名>.github.io/movie-guide/` で見られるようになります
5. iPhoneのSafariでそのURLを開き、共有ボタン →「ホーム画面に追加」

以後は `update.bat` が動くたびに自動でGitHubにも反映されます。

> **公開に関する注意**
> - GitHub Pages は誰でも見られる公開ページです。個人情報は載せないでください
> - `config.local.json`（APIキー）と `logs/` は `.gitignore` で除外済みです
> - ポスター画像は TMDb のものを使い、ページ下部にクレジットを表示しています

---

## 10. うまくいかないとき

| 症状 | 対処 |
| --- | --- |
| ページに「映画データを読み込めませんでした」と出る | `update.bat` を1回実行して `movies.js` を作る |
| ポスターが出ない（色付きのタイトルだけ） | `set-apikey.bat` を実行してキーが有効か確認 → `update.bat` を再実行 |
| APIキーを入れ直したい | `set-apikey.bat` をもう一度実行すると、入れ直すか聞かれます |
| 一部の作品だけポスターが出ない | TMDbに未登録、または作品を確実に特定できなかった場合です。仕様どおりの動作です |
| 「要確認」の作品が多い | 情報が公開前で確定していないためです。公式サイトのリンクから確認してください |
| 更新が失敗する | `logs\` の当日のログを確認。失敗時は自動でバックアップから復元されているので、表示は壊れません |
| `git push` に失敗する | 更新自体は成功扱いです。手動で `git push` してエラー内容を確認してください |
| ポート8766が使えない | 別のサーバーが起動している可能性。`tools\serve.ps1` の `$port` を変更してください |

---

## 11. 免責

- 掲載内容は自動収集した情報です。**正確性は保証されません**
- **入場者特典は数量限定・なくなり次第終了**が原則です。配布終了していることがあります
- **ムビチケの販売期間は変更されることがあります**
- おでかけ前に、必ず**公式サイト・劇場の公式情報で最新の内容を確認**してください
