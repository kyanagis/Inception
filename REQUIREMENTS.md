# 要求トレーサビリティ

本表は主要要求と実装・検証箇所を対応付けます。表の存在は試験実施を意味しません。実行結果は対象VMごとに記録してください。

| 要求 | 実装 | 検証 |
|---|---|---|
| Docker Composeを使用 | `srcs/docker-compose.yml`、Makefile | `make config` |
| サービスごとに専用コンテナ | Composeの各serviceと各Dockerfile | `make check`、`make status` |
| penultimate stable Debian/Alpine | digest固定Debian 12 slim | `make check`、クリーンビルド |
| ready-made service image禁止 | 全サービスをローカルDockerfileでbuild | `make check` |
| NGINX、TLS 1.2/1.3のみ | NGINX設定とTLS検証スクリプト | `make test` |
| WordPress + PHP-FPMのみ | WordPress Dockerfile、foreground PHP-FPM | `make test` |
| MariaDBのみ | MariaDB Dockerfile、foreground mariadbd | `make test` |
| DBとWebファイルのnamed volume | `mariadb_data`、`wordpress_data` | `make doctor`、volume inspect |
| `/home/login/data` 配下へ保存 | 専用daemon data-root | `make doctor` |
| bind mount禁止 | optionなしのlocal named volume | `make check`、`make doctor` |
| Docker network | edge/frontend/backend bridge | `make check` |
| crash時再起動 | `restart: unless-stopped` | `make check`、手動障害注入 |
| host network、links禁止 | Composeに未使用 | `make check` |
| 無限loopによる常駐禁止 | foreground daemonをexec | `make check`、PID確認 |
| WordPressに管理者と一般ユーザー | entrypointの作成・照合処理 | `make test` |
| 管理者名にadminを含めない | entrypointの入力拒否 | `make test` |
| 構成済みドメインのローカル名前解決 | configure、host-setup、preflight | `make doctor` |
| `latest` 禁止 | 明示versionとdigest | `make check` |
| Dockerfileにpassword禁止 | Compose secrets | `make check` |
| `.env` 使用 | `srcs/.env` | `make config` |
| credentialをGitへ保存しない | `secrets/` と `.gitignore` | 提出前の人手確認 |
| mandatory公開は443のみ | NGINXだけports指定 | `make check`、`make test` |
| README要件 | `README.md` | `make check`、人手レビュー |
| 利用者文書 | `USER_DOC.md` | 人手レビュー |
| 開発者文書 | `DEV_DOC.md` | 人手レビュー |

## リリース判定

次の全条件を満たすまで「検証済み」と表現してはいけません。

1. 提出対象と同一内容を新規専用VMへ配置した。
2. 空のDocker状態から全イメージを構築した。
3. `make check`、`make doctor`、`make test` が終了コード0になった。
4. 永続化、再起動、停止、再構築、TLS、公開ポートを実証した。
5. bonusを主張する場合はmandatory合格後に全bonusを実証した。
6. バックアップを別の隔離環境へ復元した。
7. 実施者とは別のレビュー担当者が結果とログを確認した。
