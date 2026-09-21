# 利用者・管理者向け運用手順

## 1. 提供サービス

通常の make up では mandatory の3サービスだけを起動します。

| サービス | 役割 | ホスト公開 |
|---|---|---|
| NGINX | TLS終端、静的配信、PHP-FPMへの中継 | TCP 443 |
| WordPress | CMSとPHP-FPM | なし |
| MariaDB | WordPressデータベース | なし |

make bonus は Redis、明示FTPS、静的サイト、Adminer、定期バックアップも起動します。Adminerと静的サイトは127.0.0.1だけへbindし、Redisはホストへ公開しません。

## 2. 初回起動: 公開OVA

公開OVAでは Docker daemon、Docker data-root、42用データディレクトリの切替機構がOS側に組み込まれています。make host-setup は実行しないでください。

最初に42 loginを設定します。

    inception-setup YOUR_LOGIN

新しいTerminalを開いて、次を確認します。

    echo "$INCEPTION_LOGIN"
    echo "$DOMAIN_NAME"
    echo "$INCEPTION_DATA_DIR"
    docker info --format '{{.DockerRootDir}}'
    readlink -f /home/inception/data/docker

YOUR_LOGIN=kyanagis の場合、期待される論理値は次です。

    INCEPTION_LOGIN=kyanagis
    DOMAIN_NAME=kyanagis.42.fr
    INCEPTION_DATA_DIR=/home/kyanagis/data

DockerRootDirは /home/inception/data/docker と表示される場合がありますが、/home/inception/data は /home/kyanagis/data へ向く管理symlinkです。realpath後の実体は /home/kyanagis/data/docker になります。

推奨手順は次です。

    inception-evaluate --prepare

これは current submit branch を取得またはfast-forwardし、対象checkoutを構成し、doctor/checkを実行します。OVAは特定のsubmit commitへ固定されていません。

手動で行う場合:

    cd /home/inception
    git clone --branch submit --single-branch       https://github.com/kyanagis/Inception.git Inception-submit
    cd Inception-submit
    make configure LOGIN="$INCEPTION_LOGIN"
    make doctor
    make check

その後:

    make up
    make test

## 3. 初回起動: 汎用Debian VM

公開OVA以外の専用Debian VMでは次を使います。

    make configure LOGIN=YOUR_LOGIN
    make host-setup LOGIN=YOUR_LOGIN
    make check
    make doctor
    make up
    make test

host-setup はroot権限でDocker daemonの保存先と /etc/hosts を変更します。共用ホストでは実行しないでください。既存コンテナ、イメージ、volume、custom networkがあるDocker daemonでは安全側に停止します。

## 4. 開始・停止・状態確認

    make up
    make bonus
    make stop
    make start
    make restart
    make down
    make status
    make logs

make up はmandatoryのみを起動し、bonus serviceが残っている場合は停止します。make bonus は全serviceを起動します。

正常なmandatory環境では mariadb、wordpress、nginx がrunningかつhealthyです。異常時は削除や再初期化の前に、時刻、実行コマンド、make status、必要最小限のlogを記録してください。

## 5. Webアクセス

Web site:

    https://YOUR_LOGIN.42.fr

管理画面:

    https://YOUR_LOGIN.42.fr/wp-admin/

自己署名証明書を無条件に承認せず、fingerprintを確認してください。

    openssl x509 -in secrets/tls_certificate.pem       -noout -subject -issuer -dates -fingerprint -sha256

NGINXはTLS 1.2と1.3だけを受け付けます。port 80はmandatory entry pointではありません。

## 6. 認証情報

認証情報はリポジトリ直下のsecretsディレクトリへローカル生成されます。

| ファイル | 用途 |
|---|---|
| db_password.txt | WordPress用DBユーザー |
| db_root_password.txt | MariaDB root |
| db_backup_password.txt | backup専用DBユーザー |
| wp_admin_password.txt | WordPress管理者 |
| wp_user_password.txt | WordPress一般ユーザー |
| redis_password.txt | Redis WordPress ACLユーザー |
| ftp_password.txt | FTPSユーザー |
| tls_private_key.pem | HTTPS秘密鍵への管理link |
| tls_certificate.pem | HTTPS証明書への管理link |
| ftps_private_key.pem | FTPS秘密鍵 |
| ftps_certificate.pem | FTPS証明書 |

secretsはGit対象外です。passwordやprivate keyをチャット、issue、log、shell history、screenshotへ転記しないでください。

既存volumeがある状態でsecretだけを消して再生成すると、保存済み認証情報と一致しなくなるためentrypointは安全側に停止します。

## 7. 検証

mandatory:

    make check
    make doctor
    make up
    make test
    make audit

make audit は「安全そう」という主張ではなく、想定攻撃経路を仮説として扱います。privileged/host namespace、backend port公開、credential環境変数、tracked secret、read-only rootfs、no-new-privileges等を静的・実行時に確認します。

bonus:

    make bonus
    make bonus-test

bonus-test は次を実証します。

1. 8 serviceが期待どおり稼働している。
2. healthcheck対象がhealthyである。
3. Redisがhostへ公開されず認証付きで応答する。
4. WordPress Redis object cacheが利用可能である。
5. Adminerは127.0.0.1:8080だけへ公開される。
6. static siteは127.0.0.1:8081だけへ公開される。
7. explicit FTPSでTLS証明書検証が成立する。
8. 実backupを作成しmanifest検証が成功する。

## 8. 永続化

mandatoryのnamed volume:

    inception_mariadb_data
    inception_wordpress_data

bonus:

    inception_backup_data

公開OVAではDocker data-rootの実体が /home/YOUR_LOGIN/data/docker へ到達するようOS側で構成されます。volume内部をhostから直接編集しないでください。

make stop、make down、VM rebootではvolume dataは残ります。

## 9. バックアップ

    make bonus
    make backup-now
    make backup-list
    make backup-verify BACKUP=YYYYMMDDTHHMMSSZ-XXXXXXXXXX

backup作成成功だけではrestore可能性を保証しません。定期的に別の隔離環境へ復元し、投稿、user、添付ファイル、URL、DB整合性を確認してください。

## 10. 破壊的操作

    make fclean

project container、project image、named volume dataを削除します。実行前にbackupが存在するだけでなく、検証済みであることを確認してください。

## 11. OVAをsubmit変更から独立させる仕組み

OVAには評価対象sourceを焼き込みません。inception-evaluate は毎回remote submitを参照します。

submit branchの .inception/host-tools は command と nixpkgs package の安全な対応表です。将来、通常のuserspace依存が増えた場合はsubmit側だけでこのcontractを更新でき、OVA側にcommandがなければ evaluator が一時的なNix shellで補います。

この仕組みで、Dockerfile、Compose、shell、WordPress設定、テスト、通常のCLI依存追加などのsubmit変更はOVA再生成理由になりません。カーネル機能、CPU architecture、VirtualBox hardware、root filesystem容量そのものを変更する要求は例外です。

## 12. 障害時の基本原則

1. 症状、時刻、直前変更、影響範囲を記録する。
2. make status と必要最小限のlogを保存する。
3. secretやdatabase内容がlogに含まれないことを確認する。
4. 原因不明のままfcleanやvolume削除をしない。
5. make auditで境界条件を再確認する。
6. backupを隔離環境でverifyしてから復旧する。
