# 開発者・保守担当者向け文書

## 1. 設計目標

本構成は、要件を再現可能かつ安全側に満たすことを目的とします。必須経路は `client -> NGINX:443 -> WordPress/PHP-FPM:9000 -> MariaDB:3306` です。MariaDBとWordPressはホストへ公開しません。

## 2. 前提条件

- systemdを使用する専用Debian VM
- ローカルrootful Docker Engine 27.0.3以上
- Docker Compose 2.38.2以上
- `jq`、OpenSSL、`flock`、`realpath`、`stat`、`timeout`、GNU coreutils
- `/home/<login>` が存在し、sudoまたはrootを利用可能
- Docker daemonに既存コンテナ、イメージ、volume、カスタムnetworkがないこと

バージョン下限はComposeの `--wait`、JSON出力等、本成果物が検証したCLI挙動を固定するためです。要件を緩和する場合は、対象バージョンで全テストを再実施してください。

## 3. ゼロからの構築

```sh
make configure LOGIN=kyanagis
make host-setup LOGIN=kyanagis
make check
make doctor
make build
make up
make test
```

`configure` は `srcs/.env` のドメイン、保存先、メールアドレスを更新します。`host-setup` は次をトランザクション的に実施します。

1. 専用VM、rootful daemon、空のDocker状態を検査する。
2. `/etc/docker/daemon.json` のdata-rootを `/home/<login>/data/docker` に設定する。
3. 構成済みのドメインを127.0.0.1へ解決する。
4. Dockerを再起動し、失敗時は元の設定へ戻す。

既存Docker資産を自動移行しないのは、暗黙のデータ消失や別プロジェクトへの影響を避けるためです。

## 4. 設定ファイルと秘密情報

`srcs/.env` には公開可能な構成値だけを置きます。パスワード、APIキー、秘密鍵を追加してはいけません。初回 `setup` は暗号学的乱数で64桁hexの秘密値を生成し、自己署名ECDSA証明書を作成します。

秘密情報を変更すると永続データ内の認証情報と不一致になります。既存環境のローテーションは単なるファイル置換ではなく、サービス内の認証情報更新、停止、secret更新、再起動、疎通確認を一つの変更手順として実施してください。現在の自動化は意図的に不一致を検出して停止し、暗黙のローテーションは行いません。

## 5. イメージとサプライチェーン

各Dockerfileはdigest固定したDebian 12 slimを基底とします。WordPress、WP-CLI、Redis plugin、AdminerはバージョンとSHA-256を固定します。更新時は必ず公式配布元から別ディレクトリへ取得し、ハッシュ、アーカイブ内容、リリース情報を確認してからComposeの値を変更します。

2026-09-21時点のWordPressは7.1.1を固定しています。自動更新は再現性を壊すため無効です。セキュリティ更新は、変更要求、ハッシュ更新、クリーンビルド、移行試験、ロールバック確認を伴う管理作業として行います。

## 6. コンテナ防御

- root filesystemはread-only
- 必要な実行時書込みだけnamed volumeまたはtmpfs
- 全capabilityを削除後、必要最小限だけ追加
- `no-new-privileges`
- foreground daemonとinit
- healthcheckと起動依存
- 30秒の停止猶予
- json-fileログを10 MiB×3へ制限
- frontend/backendはinternal bridge
- mandatoryのホスト公開はNGINX 443だけ

これらは多層防御であり、脆弱性がないことを意味しません。

## 7. 永続化

必須named volumeは次の2つです。

- `inception_mariadb_data` -> `/var/lib/mysql`
- `inception_wordpress_data` -> `/var/www`

ボーナスは `inception_backup_data` を追加します。bind mount禁止条件を守るため、Compose volumeにbind driver optionは設定しません。代わりに専用daemonのdata-root全体を `/home/<login>/data/docker` に置きます。

確認方法：

```sh
docker volume inspect inception_mariadb_data inception_wordpress_data
docker info --format '{{.DockerRootDir}}'
```

volume内部をホストから直接変更してはいけません。所有者、管理メタデータ、DB整合性が壊れるためです。

## 8. Makeターゲット

| ターゲット | 動作 |
|---|---|
| `check` | daemon不要の静的検証 |
| `doctor` | daemon、名前解決、data-root、既存volumeを検証 |
| `config` | bonusを含むCompose構文検証 |
| `build` | mandatory 3イメージだけを構築 |
| `bonus-build` | 全イメージを構築 |
| `up` / `bonus` | mandatory / 全サービスを起動 |
| `test` | 静的検証と稼働中mandatoryの統合試験 |
| `down` | コンテナとnetworkを削除、volume保持 |
| `fclean` | volumeとプロジェクトイメージを削除 |

`fclean` は破壊的です。自動ジョブや通常運用中に無条件で呼び出してはいけません。

## 9. 検証プロトコル

リリース候補ごとに専用VMの空状態から次を記録します。

1. `make check`
2. `make doctor`
3. `make build --always-make` 相当のクリーンビルド
4. `make up`
5. `make test`
6. 管理者と一般ユーザーのログイン確認
7. 投稿と添付ファイルを作成
8. `make restart` 後も内容が保持されることを確認
9. `make down`、`make up` 後も保持されることを確認
10. TLS 1.0/1.1拒否、TLS 1.2/1.3許可を確認
11. ホスト公開ポートを確認
12. bonusを別途構築し、各health、FTPS、Redis、Adminer、静的サイト、backupを確認
13. 隔離環境で復元演習

コマンド終了コード、イメージdigest、構成ファイルhash、実施者、日時、VM情報を試験記録へ残します。テスト失敗を再実行だけで消し込まず、原因と是正内容を記録してください。

## 10. バックアップと復元

バックアップはMariaDBのsingle-transaction dumpとWordPressファイルarchive、manifest、SHA-256一覧を生成します。

```sh
make bonus
make backup-now
make backup-list
make backup-verify BACKUP=YYYYMMDDTHHMMSSZ-XXXXXXXXXX
```

DB dumpとファイルarchiveは単一の原子的スナップショットではありません。整合性が重要な復元点を採取するときは、投稿、アップロード、FTPS等の書込みを停止した保守時間帯に実行してください。

復元は破壊的になり得るため自動ターゲットを設けていません。次の承認済みrunbookとして隔離環境で行います。

1. 対象backupを `backup-verify` で検証する。
2. manifestのdomain、DB名、ユーザー、WordPress版、MariaDB major/minorを照合する。
3. 元環境と一致するsecretを安全に用意する。
4. 新規の隔離VMで同一構成をbootstrapする。
5. WordPress、FTP、backup等、DB／ファイルwriterを停止する。
6. SQLを対象DBへimportし、WordPress `html` をarchiveから復元する。
7. 所有者を `www-data:www-data` に戻し、管理用 `.inception-state` を保持する。
8. 起動後にアカウント、URL、投稿、添付ファイルhash、Redis無効時／有効時を検証する。
9. 承認後にのみ本番切替を行う。

本番データを直接上書きする前に、必ず復元先を別環境として検証してください。

## 11. 障害解析と変更管理

原因不明のvolume削除や初期化は行いません。entrypointはidentity、secret、管理markerが一致しない永続データを検出すると、安全側に停止します。これは障害ではなくデータ保護動作です。

変更時は少なくとも次をレビューします。

- 課題要件とのトレーサビリティ
- 公開ポートとnetwork到達性
- secret露出
- 永続データの前方・後方互換性
- rollback可能性
- ベースイメージと配布物の真正性
- healthcheckが実際の準備完了を表すか
- ログに秘密情報・機微情報が出ないか
- backupと復元の実証結果
