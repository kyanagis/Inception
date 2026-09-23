# 利用者・管理者向け運用手順

この文書は `submit` ブランチに含まれる Inception 提出物だけを対象にします。

## 1. 提供サービス

通常の `make up` では mandatory の3サービスだけを起動します。

| サービス | 役割 | ホスト公開 |
|---|---|---|
| NGINX | TLS終端、静的配信、PHP-FPMへの中継 | TCP 443 |
| WordPress | CMSとPHP-FPM | なし |
| MariaDB | WordPressデータベース | なし |

`make bonus` は Redis、明示FTPS、静的サイト、Adminer、定期バックアップも起動します。Adminerと静的サイトは `127.0.0.1` のみにbindし、Redisはホストへ公開しません。

## 2. 初回セットアップ

専用の Debian VM と rootful Docker を使用してください。共用ホストや、別用途のcontainer/image/volume/custom networkが存在するDocker daemonでは `host-setup` を実行しないでください。

```sh
git clone --branch submit --single-branch https://github.com/kyanagis/Inception.git
cd Inception

make configure LOGIN=YOUR_LOGIN
make host-setup LOGIN=YOUR_LOGIN
make check
make doctor
make up
make test
```

`make configure` は `srcs/.env` を生成します。`make host-setup` は専用VMであることを確認し、Docker data-rootと `/etc/hosts` を安全側に検証しながら構成します。危険な既存Docker状態やストレージ移行を検知した場合は停止します。

YOUR_LOGIN が `kyanagis` の場合、主な値は次のようになります。

```text
DOMAIN_NAME=kyanagis.42.fr
```

Dockerの永続データは `/home/YOUR_LOGIN/data` 以下に配置されます。

## 3. 開始・停止・状態確認

```sh
make up
make bonus
make stop
make start
make restart
make down
make status
make logs
```

`make up` はmandatoryのみを起動し、bonus serviceが残っている場合は停止します。`make bonus` はbonusを含む全serviceを起動します。

正常なmandatory環境では `mariadb`、`wordpress`、`nginx` がrunningかつhealthyです。異常時は削除や再初期化の前に、時刻、実行コマンド、`make status`、必要最小限のlogを記録してください。

## 4. Webアクセス

Web site:

```text
https://YOUR_LOGIN.42.fr
```

管理画面:

```text
https://YOUR_LOGIN.42.fr/wp-admin/
```

自己署名証明書を無条件に承認せず、fingerprintを確認してください。

```sh
openssl x509 -in secrets/tls_certificate.pem \
  -noout -subject -issuer -dates -fingerprint -sha256
```

NGINXはTLS 1.2と1.3だけを受け付けます。port 80はmandatory entry pointではありません。

## 5. 認証情報

認証情報はリポジトリ直下の `secrets/` にローカル生成されます。

| ファイル | 用途 |
|---|---|
| `db_password.txt` | WordPress用DBユーザー |
| `db_root_password.txt` | MariaDB root |
| `db_backup_password.txt` | backup専用DBユーザー |
| `wp_admin_password.txt` | WordPress管理者 |
| `wp_user_password.txt` | WordPress一般ユーザー |
| `redis_password.txt` | Redis WordPress ACLユーザー |
| `ftp_password.txt` | FTPSユーザー |
| `tls_private_key.pem` | HTTPS秘密鍵 |
| `tls_certificate.pem` | HTTPS証明書 |
| `ftps_private_key.pem` | FTPS秘密鍵 |
| `ftps_certificate.pem` | FTPS証明書 |

`secrets/` はGit対象外です。passwordやprivate keyをチャット、issue、log、shell history、screenshotへ転記しないでください。

既存volumeがある状態でsecretだけを消して再生成すると、保存済み認証情報と一致しなくなるためentrypointは安全側に停止します。

## 6. Mandatory検証

```sh
make check
make doctor
make up
make test
make audit
make dependency-audit
```

各コマンドの目的:

- `make check`: Compose、Dockerfile、secret、capability、TLS、Redis ACL、ドキュメント等の静的contractを検証する。
- `make doctor`: VM、Docker、保存先、必要tool、host側前提を検証する。
- `make test`: mandatory stackを起動し、NGINX → WordPress → MariaDBの実動作と主要な権限境界を確認する。
- `make audit`: privileged/host namespace、backend port公開、credential環境変数、tracked secret、read-only rootfs、`no-new-privileges`、Docker storage pressure等を仮説単位で確認する。
- `make dependency-audit`: pinしているWordPress versionがupstreamでcurrentかを確認し、archiveのSHA-256も再検証する。

## 7. Bonus検証

```sh
make bonus
make bonus-test
```

`bonus-test` は次を実証します。

1. 8 serviceが期待どおり稼働している。
2. healthcheck対象がhealthyである。
3. Redisがhostへ公開されず、認証付きで応答する。
4. WordPress Redis Object Cacheが実際にRedisへread/writeできる。
5. Adminerは `127.0.0.1:8080` のみへ公開される。
6. static siteは `127.0.0.1:8081` のみへ公開される。
7. FTPSで証明書検証と実認証が成立する。
8. FTPS userはuploadsへ書込み・読戻し・削除できる。
9. FTPS userによるcore/plugin/themeへの書込み、path traversal、uploadsからprotected directoryへのrenameが拒否される。
10. uploadsへ配置したPHPがNGINXで実行されない。
11. 実backupを作成しmanifest検証が成功する。
12. backupから隔離用databaseへSQLを復元し、WordPress files archiveも展開・検証できる。

## 8. 永続化

mandatoryのnamed volume:

```text
inception_mariadb_data
inception_wordpress_data
```

bonus:

```text
inception_backup_data
```

これらはDockerのnative named volumeです。Docker daemonのdata-rootを `/home/YOUR_LOGIN/data/docker` 以下に配置することで、実データを必要なlearner pathの下へ保持します。

volume内部をhostから直接編集しないでください。`make stop`、`make down`、VM rebootではvolume dataは残ります。

## 9. バックアップ

```sh
make bonus
make backup-now
make backup-list
make backup-verify BACKUP=YYYYMMDDTHHMMSSZ-XXXXXXXXXX
```

`make backup-verify` はmanifest、hash、archive構造を確認します。`make bonus-test` はさらに、最新backupのSQLを `--network none` の使い捨てMariaDBへ実際にrestoreし、`wp_options` とsite URLを検証します。WordPress files archiveも別の一時directoryへ展開して主要fileを確認します。

backup作成成功とrestore可能性は別の性質なので、運用上重要なbackupは定期的に別環境でもrestoreしてください。

## 10. 障害時の基本原則

1. 症状、時刻、直前変更、影響範囲を記録する。
2. `make status` と必要最小限のlogを保存する。
3. secretやdatabase内容がlogに含まれないことを確認する。
4. 原因不明のまま `fclean` やvolume削除をしない。
5. `make audit` で境界条件を再確認する。
6. backupをverifyしてから復旧する。

## 11. 破壊的操作

```sh
make fclean
```

project container、project image、named volume dataを削除します。実行前にbackupが存在するだけでなく、必要ならrestore testまで成功していることを確認してください。
