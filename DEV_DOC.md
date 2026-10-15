# 開発者・保守担当者向け文書

## 1. 設計目標

mandatoryのデータ経路は次です。

    client -> NGINX:443 -> WordPress/PHP-FPM:9000 -> MariaDB:3306

MariaDBとWordPressはhostへ公開しません。bonusのRedisもbackend network内だけです。Adminerとstatic siteはloopbackだけ、FTPSのみ指定portを公開します。

この実装では「要件に見える」ことと「実行時に成立する」ことを分離し、静的検査、起動後のsmoke test、bonus integration test、仮説駆動auditの4層で確認します。

## 2. 新規VMからの構築・操作

専用x86_64 Debian VMにGit、sudo、Docker Engine 27.0.3以上、Compose plugin 2.38.2以上と、後述の前提コマンドを用意します。Dockerはrootfulのローカルdaemonを使用し、作業ユーザーが操作できることを確認します。Dockerの導入は [Docker公式Debianインストール手順](https://docs.docker.com/engine/install/debian/) を参照してください。

```sh
git clone --branch submit --single-branch https://github.com/kyanagis/Inception.git
cd Inception
make configure LOGIN=YOUR_LOGIN
make host-setup LOGIN=YOUR_LOGIN
make doctor
make setup
make config
make check
make build
make up
make test
```

`YOUR_LOGIN` は自身の42ログイン名に置き換えます。`host-setup` は既存の無関係なDocker資源がない専用VMで行います。`make setup` は検証後にローカルの `secrets/` と証明書等を生成します。`make up` と `make build` もsetupを依存処理として実行します。

構成の入口は `srcs/docker-compose.yml`、非秘密の環境変数は生成された `srcs/.env`、サービス別Dockerfile・設定・entrypointは `srcs/requirements/`、管理スクリプトは `srcs/tools/` です。パスワードと秘密鍵はGit対象外の `secrets/` に置き、Compose secretsとして必要なコンテナへ渡します。ファイル別用途は [USER_DOC.md](USER_DOC.md) を参照してください。既存データがある場合、secretの再生成だけでは認証情報を更新できません。

Makefileが利用するCompose呼び出しと、資源の確認例です。

```sh
docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml config --quiet
docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml ps
docker volume inspect inception_mariadb_data inception_wordpress_data
make stop
make start
make down
```

`make stop` はコンテナを停止し、`make down` はコンテナとネットワークを削除します。どちらもnamed volumeのデータを残します。再起動は `make start`、削除後の再作成は `make up`、構成を含む再構築は `make build` と `make up` を使います。`make fclean` はプロジェクトのvolumeも削除するため、復元可能なバックアップを確認してから実行します。

## 3. host mode

### 汎用Debian VM

    make configure LOGIN=YOUR_LOGIN
    make host-setup LOGIN=YOUR_LOGIN

host-setupは専用VM、rootful Docker、空のDocker stateを要求し、data-rootと/etc/hostsをtransaction的に変更します。

## 4. 前提command

submit単体の最低contract:

- Docker Engine 27.0.3以上

- Docker Compose 2.38.2以上

- make

- jq

- python3

- ip

- getent

- realpath

- stat

- awk

- grep

- sort

- OpenSSL

- curl

必要なコマンドは専用Debian VMへ事前にインストールします。

## 5. image supply chain

全service Dockerfileはdigest固定Debian 12 slimを基底とします。WordPress、WP-CLI、Redis plugin、Adminerなど外部配布物にはversionとSHA-256を固定します。

更新時:

1. official upstreamを確認する。
2. versionを固定する。
3. artifact hashを独立に検証する。
4. clean buildする。
5. mandatory/bonus testを実行する。
6. rollback対象versionを残す。

latest tagは使いません。

## 6. container boundary

共通防御:

- read_only root filesystem

- no-new-privileges

- cap_drop ALLを基準に必要capabilityだけ追加

- bounded tmpfs

- memory/pids/cpu limits

- foreground daemon

- restart unless-stopped

- bounded json-file logs

- explicit bridge networks

- health checks

RedisだけはCompose file-backed secretの0600 ownership問題を安全に処理するためentrypointをrootで開始します。root phaseではsecretを読み、/run/redis/users.aclをtmpfsへ生成し、CHOWN/DAC_OVERRIDE/SETUID/SETGIDを使った後、gosu redisでdaemonを非root起動します。Composeの init: true によるtiniがUIDの異なるdaemonへ停止signalを転送できるようKILLもRedis/MariaDBだけへ許可します。SYS_ADMINなどの強いcapabilityは静的checkで拒否します。固定UID/GIDは使用しません。

Redis ACL:

- default user off

- random 64-hex password

- WordPress userのみ

- read/write/connection/scripting category

- Redis Object Cache 3.0.0のenable/flush lifecycleに必要なFLUSHDBだけ許可

- FLUSHALL/config/acl/shutdown/module/replication/persistence control commandを明示deny

## 7. WordPress boundary

WordPress設定は次を強制します。

- FORCE_SSL_ADMIN

- DISALLOW_FILE_EDIT

- DISALLOW_FILE_MODS

- WP core auto update無効

- generated random salts

- DB password/Redis passwordはruntime fileから読む

- admin名にadmin文字列を許可しない

- adminと一般userを別accountにする

- core fileをroot:www-dataで非書込み

- uploadsだけwww-dataへ書込み許可

NGINXはuploads内PHP実行、dotfile、wp-config.php、readme.html、license.txtへのdirect accessを拒否します。xmlrpc.phpも拒否します。

## 8. MariaDB state machine

MariaDB entrypointは単純な「directoryが空ならinit」ではありません。

- staging directory

- identity marker

- completion marker

- application/root/backup credential照合

- interrupted bootstrapのrecovery

- unknown dataを自動削除しない

- backup userをapplication userと分離

認証不一致や未知のdataを検出した場合、暗黙のresetより停止を選びます。

## 9. 永続化

mandatory:

- inception_mariadb_data

- inception_wordpress_data

bonus:

- inception_backup_data

volume driverはlocalでdriver optionを持ちません。bind-backed volumeにはしません。

専用Docker daemonのdata-root自体を /home/<login>/data/docker へ置くことで、named volume実体がsubject要求のlearner data path配下へ置かれます。

## 10. verification layers

### static

    make check

確認内容:

- service数とlocal build

- image naming

- read-only/no-new-privileges等の宣言

- mandatory公開port

- secret assignment

- pinned base image

- prohibited keepalive loop

- TLS version

- NGINX defense

- WordPress immutable settings

- Redis privilege drop/ACL

- shell/Python syntax

- repository credential material

### host

    make doctor

確認内容:

- rootful local Docker

- version

- data-root

- volume ownership/driver/path

- domainがVM自身のIPv4へ解決されること

### mandatory runtime

    make up
    make test

確認内容:

- exactly mandatory service set

- health

- only NGINX 443 exposure

- HTTPS

- unknown Host rejection

- xmlrpc denial

- TLS 1.0/1.1 rejection, 1.2/1.3 acceptance

- WordPress users

- core checksums

- file ownership

- site/home URL

- MariaDB authentication

### bonus runtime

    make bonus
    make bonus-test

確認内容:

- full 8 service set

- health

- Redis private/authenticated/object-cache path

- Adminer/static loopback-only

- FTPS certificate verification

- real backup generation and manifest verification

### threat-hypothesis audit

    make audit

auditは「安全」という結論を先に置かず、攻撃仮説をID付きで検証します。現在の主な仮説:

- H01 static policyを迂回する構成が入った

- H02 privileged/host namespace/writable rootfsが入った

- H03 DB/WordPress/Redisがhostへ公開された

- H04 secret/private keyがGit追跡された

- H05 credentialがenvironmentへ入った

- H06 runtime configがdeclared hardeningと異なる

- H07 runtime backend portが公開された

仮説追加時は「攻撃経路 -> 観測点 -> 再現command -> expected failure/containment」を先に書き、checkを後から合わせます。

## 11. backup/recovery

backupはMariaDB single-transaction dump、WordPress file archive、manifest、SHA-256を生成します。

    make bonus
    make backup-now
    make backup-list
    make backup-verify BACKUP=<name>

DB dumpとfilesystem archiveは単一transactionではありません。厳密なrestore pointではwriterを停止したmaintenance windowを使います。

restoreは隔離VMで:

1. manifest/hash verify
2. identity/version照合
3. compatible secretsを安全に用意
4. clean bootstrap
5. writer停止
6. SQL import
7. WordPress archive復元
8. ownership修復
9. account/URL/post/upload/Redis検証
10. 承認後のみ切替
