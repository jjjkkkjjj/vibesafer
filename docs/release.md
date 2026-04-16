# リリース手順

`v*` タグを push するだけで GitHub Actions が自動的にビルド・リリースを行います。

---

## 手順（推奨: release.sh を使う）

リポジトリルートにある `release.sh` を使うと、バージョン更新からタグ push まで一括で実行でき、途中で失敗した場合は自動的にロールバックされます。

```bash
# リリース
./release.sh <version>
# 例
./release.sh 0.3.0

# リバート（CI 失敗後などにリリースを取り消す）
./release.sh revert <version>
# 例
./release.sh revert 0.3.0
```

### release — スクリプトが行うこと

| ステップ | 内容 |
|---|---|
| 1 | 作業ツリーのクリーン確認（未コミットの変更があればエラー終了） |
| 2 | `Cargo.toml` の `version` を指定バージョンに更新 |
| 3 | `./cargo-docker test` でテスト実行 |
| 4 | `./cargo-docker clippy -- -D warnings` で lint |
| 5 | `chore: bump version to vX.Y.Z` でコミット |
| 6 | `vX.Y.Z` タグを作成 |
| 7 | `main` ブランチと `vX.Y.Z` タグを `origin` へ push（タグ push が CI のトリガー） |

### revert — スクリプトが行うこと

CI が失敗した後などに、push 済みのリリースを取り消します。

| ステップ | 内容 |
|---|---|
| 1 | リモートタグ `vX.Y.Z` を削除（存在する場合） |
| 2 | ローカルタグ `vX.Y.Z` を削除（存在する場合） |
| 3 | バージョンバンプコミットを `git revert` して `main` に push |

`git revert` を使うため、履歴を書き換えず安全に取り消せます。

### 失敗時のロールバック

スクリプトは `trap EXIT` で任意のエラーを検知し、進行状況に応じてロールバックします。

| 状態 | ロールバック内容 |
|---|---|
| リモートタグ push 済み | `git push origin :refs/tags/vX.Y.Z` でリモートタグを削除 |
| ローカルタグ作成済み | `git tag -d vX.Y.Z` |
| コミット済み | `git reset --soft HEAD~1` |
| `Cargo.toml` 変更済み | `git checkout -- Cargo.toml` |

---

## 手順（手動）

スクリプトを使わずに手動でリリースする場合は以下の手順に従います。

### 1. バージョンを更新

`Cargo.toml` の `version` を更新します。

```toml
# Cargo.toml
version = "0.2.0"
```

### 2. ビルド確認

```bash
./cargo-docker test
./cargo-docker clippy -- -D warnings
```

### 3. コミット → タグ → Push

```bash
git add Cargo.toml
git commit -m "chore: bump version to v0.2.0"

git tag v0.2.0
git push origin main
git push origin v0.2.0   # ← これが CI のトリガー
```

タグは必ず `v` プレフィックスをつける（`v0.2.0` ○ / `0.2.0` ×）。

---

## CI が行うこと

`.github/workflows/release.yml` が起動し、4プラットフォームを並列ビルドします。

| ターゲット | Runner | 成果物 |
|---|---|---|
| `aarch64-apple-darwin` | macos-latest | `vs-vX.X.X-aarch64-apple-darwin.tar.gz` / `vs-aarch64-apple-darwin.tar.gz` |
| `x86_64-apple-darwin` | macos-latest | `vs-vX.X.X-x86_64-apple-darwin.tar.gz` / `vs-x86_64-apple-darwin.tar.gz` |
| `x86_64-unknown-linux-gnu` | ubuntu-22.04 | `vs-vX.X.X-x86_64-unknown-linux-gnu.tar.gz` / `vs-x86_64-unknown-linux-gnu.tar.gz` / `vs-x86_64-linux.deb` |
| `x86_64-pc-windows-msvc` | windows-latest | `vs-vX.X.X-x86_64-pc-windows-msvc.zip` |

各 Unix ターゲットにはバージョン付き（固定 URL 用）とバージョンなし（`latest` URL 用）の 2 つの tarball をアップロードします。

ビルド完了後、GitHub Release が自動作成され各バイナリが添付されます。
リリースノートはコミット履歴から自動生成されます（`generate_release_notes: true`）。

全ジョブ完了後、`dispatch-homebrew` ジョブが `jjjkkkjjj/homebrew-vibesafer` リポジトリへ `repository_dispatch` を送信し、Homebrew フォーミュラが自動更新されます（要 `HOMEBREW_TAP_TOKEN` シークレット）。

---

## トラブルシューティング

**タグを打ち直したい場合（ローカルにのみタグを打った場合）:**

```bash
git tag -d v0.2.0
git tag v0.2.0
git push origin v0.2.0
```

**既に push したタグを修正したい場合（非推奨、注意して実施）:**

```bash
git tag -d v0.2.0
git push origin :refs/tags/v0.2.0   # リモートのタグを削除
git tag v0.2.0
git push origin v0.2.0
```

**CI のログを確認する場所:**

GitHub リポジトリ → Actions タブ → "Release" ワークフロー
