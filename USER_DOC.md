# 利用者・管理者向け運用手順

## 1. 提供サービス

通常の `make` では次の必須サービスだけを起動します。

| サービス | 役割 | ホスト公開 |
|---|---|---|
| NGINX | TLS終端、静的配信、PHP-FPMへの中継 | TCP 443 |
| WordPress | CMSとPHP-FPM | なし |
| MariaDB | WordPressデータベース | なし |

`make bonus` はRedis、FTPS、静的サイト、Adminer、定期バックアップも起動します。ボーナス環境は追加ポートを使用するため、必要な場合だけ有効化してください。

## 2. 初回起動

専用Debian VMで、リポジトリのルートから実行します。`LOGIN` は対象環境のログイン名へ置き換えます。

```sh
make configure LOGIN=kyanagis
make host-setup LOGIN=kyanagis
make check
make
make test
```

`host-setup` は管理者権限を要求し、Dockerの保存先と `/etc/hosts` を設定します。既存Docker資産があるホストでは安全のため停止します。共用ホストでは実行しないでください。

## 3. 開始・停止・状態確認

```sh
make up       # 必須サービスを構築して起動
make bonus    # ボーナスを含めて構築して起動
make stop     # コンテナを停止（削除しない）
make start    # 既存コンテナを開始
make restart  # 再起動
make down     # コンテナとネットワークを削除、データは保持
make status   # 状態とhealthを表示
make logs     # 直近100行からログを追跡、Ctrl-Cで終了
make test     # 必須サービスの統合検証
```

正常時は `make status` で `mariadb`、`wordpress`、`nginx` が稼働し、healthが `healthy` になります。異常時は変更や削除を行う前に、時刻、実行コマンド、`make status`、必要範囲のログを記録してください。ログに秘密値を貼り付けないでください。

## 4. Webサイトへのアクセス

- Webサイト: `srcs/.env` の `DOMAIN_NAME` に設定したHTTPS URL
- 管理画面: 上記URLの `/wp-admin/`

証明書は初回セットアップ時にローカル生成されます。ブラウザ警告を無条件に無視せず、管理者が次のコマンドで確認した証明書と一致することを確認してください。

```sh
openssl x509 -in secrets/tls_certificate.pem -noout -subject -issuer -dates -fingerprint -sha256
```

## 5. 認証情報の管理

認証情報はリポジトリ直下の `secrets/` に生成されます。

| ファイル | 用途 |
|---|---|
| `db_password.txt` | WordPress用DBユーザー |
| `db_root_password.txt` | MariaDB root |
| `wp_admin_password.txt` | WordPress管理者 |
| `wp_user_password.txt` | WordPress一般ユーザー |
| `ftp_password.txt` | FTPSユーザー |
| `tls_private_key.pem` | TLS秘密鍵への管理リンク |
| `tls_certificate.pem` | TLS証明書への管理リンク |

`secrets/` はGit対象外です。秘密値をチャット、メール、課題提出物、ログへ転載しないでください。権限はディレクトリ0700、パスワードと秘密鍵0600を維持します。秘密値を失った状態で既存ボリュームを起動すると、安全のため認証不一致で停止します。

## 6. データ保持と削除

WordPressとMariaDBはDocker named volumeへ保存されます。専用Docker daemonの実データは `/home/kyanagis/data/docker/volumes/` 以下です。通常はこの内部構造を直接編集しないでください。

`make stop`、`make down`、VM再起動ではデータは残ります。次は不可逆な削除操作です。

```sh
make fclean
```

実行前に対象プロジェクト、バックアップ、復旧可能性を確認してください。`fclean` はプロジェクトのnamed volumeとイメージを削除します。

## 7. バックアップ

バックアップサービスはボーナス環境でのみ使用できます。

```sh
make bonus
make backup-now
make backup-list
make backup-verify BACKUP=YYYYMMDDTHHMMSSZ-XXXXXXXXXX
```

バックアップが作成された事実だけでは復旧可能性を保証しません。定期的に隔離環境で復元演習を行い、Web表示、管理者ログイン、一般ユーザー、投稿、添付ファイル、DB整合性を確認してください。復元の詳細は `DEV_DOC.md` を参照してください。

## 8. 障害時の基本原則

1. 症状、時刻、直前変更、影響範囲を記録する。
2. `make status` と必要最小限のログを保存する。
3. 認証情報や機微情報がログに含まれないことを確認する。
4. 原因不明のまま `fclean`、ボリューム削除、DB直接編集を行わない。
5. バックアップの検証後、隔離環境で復旧手順をリハーサルする。
6. 影響範囲が不明な場合は、技術判断だけで継続せず、定められたインシデント管理責任者へ連絡する。
