# 開発者・保守担当者向け文書

## 1. 設計目標

mandatoryのデータ経路は次です。

    client -> NGINX:443 -> WordPress/PHP-FPM:9000 -> MariaDB:3306

MariaDBとWordPressはhostへ公開しません。bonusのRedisもbackend network内だけです。Adminerとstatic siteはloopbackだけ、FTPSのみ指定portを公開します。

この実装では「要件に見える」ことと「実行時に成立する」ことを分離し、静的検査、起動後のsmoke test、bonus integration test、仮説駆動auditの4層で確認します。

## 2. host mode

### 公開universal OVA

OVAはNixOS上にDocker、評価用CLI、network/debug tool、開発tool、inception-setup、inception-evaluate、inception-auditを持ちます。

OVAでは make host-setup を実行しません。

    inception-setup YOUR_LOGIN
    inception-evaluate --prepare

inception-setup は /home/inception/data を /home/YOUR_LOGIN/data へ安全に切替え、Docker data-rootのrealpathが /home/YOUR_LOGIN/data/docker になることを確認します。

domainはNixOSのnss-myhostnameでlocal addressへ解決されます。このためsubmitのpreflightは127.0.0.1固定ではなく、解決されたIPv4がVM自身のinterface/loopback address集合に含まれるかを検証します。

### 汎用Debian VM

    make configure LOGIN=YOUR_LOGIN
    make host-setup LOGIN=YOUR_LOGIN

host-setupは専用VM、rootful Docker、空のDocker stateを要求し、data-rootと/etc/hostsをtransaction的に変更します。OVAを検出すると処理を拒否します。

## 3. OVAとsubmitのforward-compatible contract

OVAはsubmit sourceを内包しません。特定commitもrelease metadataへ固定しません。

inception-evaluateは次を行います。

1. INCEPTION_LOGINとOVA identity stateを検証する。
2. evaluator管理のdisposable checkoutが無ければremote submitをcloneする。
3. 既存checkoutをorigin/submitへresetし、secrets/とgenerated srcs/.env以外の
   stale untracked stateを除去する。
4. .inception/host-abiを読み、必要ならinception-host-updateでNixOS runtimeを更新する。
5. .inception/host-contract.json で architecture、Docker/Compose最低version、公開TCP port/range、loopback-only portを宣言する。
5. .inception/host-toolsを安全なidentifier pairとして検証する。
6. OVAに不足commandがあれば対応するnixpkgs packageをephemeral shellへ追加する。
7. project固有処理を submit/.inception/evaluate へ委譲する。
8. submit側ABIがprepare/mandatory/bonus/full/auditの状態遷移を所有する。

host-toolsはshellとしてsourceしません。各行をcommand名とnixpkgs attributeの2つのidentifierとしてparseし、許可文字以外を拒否します。これによりsubmit更新が任意host command injectionになる経路を作りません。

このcontractでOVA再importなしに吸収できる変更:
- Dockerfile、Compose、NGINX、PHP、MariaDB、WordPress設定
- shell/Python検証script
- 通常のuserspace CLI依存
- mandatory/bonus test拡張
- documentation
- image/application version更新
- host ABI更新で表現できるNixOS package、daemon、firewall、sysctl、kernel設定

OVA再生成が本当に必要になり得る変更:
- x86_64以外へのarchitecture変更
- VirtualBox virtual hardware definitionの変更
- virtual disk image/bootstrap自体の変更
- 既存disk capacityでは更新不能な要求

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

公開OVAはこれらをbuilt-inで提供します。追加commandは .inception/host-tools で宣言できます。

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
- Redis Object Cache 2.6.0のenable/flush lifecycleに必要なFLUSHDBだけ許可
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

OVAでは /home/inception/data が /home/<login>/data への管理symlinkになり、docker infoが論理pathを表示してもrealpathでsubject pathへ到達します。

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

## 12. CI release gate

OVA CIは次を別々に通す必要があります。

1. Nix evaluation/build test
2. NixOS boot test
3. OVA baseline command contract
4. current submit checkoutとのdoctor/check contract test
5. current submit Docker build/up/test
6. current submit bonus/bonus-test
7. OVA manifest digest validation
8. VirtualBox dry-run import
9. split artifact recombination hash validation

submitが変わってもOVA image sourceが変わらない限り、既存OVAは利用できます。CIはsubmit compatibilityを継続監視し、互換性が壊れた場合に「OVAを作り直す」のではなく、まずsubmit側contractまたはephemeral dependency宣言で解決できるかを判定します。

host-level requirementを変更する場合のルール:
- .inception/host-contract.json を変更する。
- .inception/host-abi を必ず増加させる。
- main側の同じABIでNixOS runtime capabilityを実装する。
- Submit Compatibility CIがmain runtimeのarchitecture、Docker/Compose version、firewall port/rangeをnix evalで照合する。
- mainのruntime-affecting fileを変更する場合もOVA Source CIがhost ABI bumpを要求する。
- したがって通常のapplication/container変更ではOVA再生成もhost ABI更新も不要。host capability変更時も既存OVAはinception-host-updateで追従する。
