# 要求トレーサビリティ

本表は主要要求と実装・検証箇所を対応付けます。表の存在は試験実施を意味しません。対象VMで実証した結果だけを検証済みとして扱います。

| 要求 | 実装 | 検証 |
|---|---|---|
| Docker Composeを使用 | srcs/docker-compose.yml、Makefile | make config |
| serviceごとに専用container | 各serviceと各Dockerfile | make check、make status |
| penultimate stable Debian/Alpine | digest固定Debian 12 slim | make check、clean build |
| ready-made service image禁止 | 全serviceをlocal Dockerfileでbuild | make check |
| NGINX、TLS 1.2/1.3のみ | NGINX設定、verify-tls.sh | make test |
| WordPress + PHP-FPM | WordPress image、foreground php-fpm | make test |
| MariaDB | MariaDB image、foreground mariadbd | make test |
| DBとWeb fileのnamed volume | mariadb_data、wordpress_data | make doctor、volume inspect |
| /home/login/data配下へ保存 | dedicated Docker data-root | make doctor |
| mandatory volumeのbind mount禁止 | optionなしlocal named volume | make check、make doctor |
| Docker network | edge/frontend/backend bridge | make check |
| crash時再起動 | restart: unless-stopped | make check、fault injection |
| host network/links禁止 | Composeで未使用 | make check、make audit |
| keepalive shell loop禁止 | foreground daemonをexec | make check、PID確認 |
| WordPress管理者と一般user | entrypointの作成・照合 | make test |
| 管理者名にadminを含めない | entrypoint入力拒否 | make test |
| login.42.fr -> local VM address | host-setupまたはOVA nss-myhostname、preflight locality check | make doctor |
| latest禁止 | explicit version/digest | make check |
| Dockerfileにpassword禁止 | file-backed Compose secrets | make check |
| .env使用 | srcs/.env | make config |
| credentialをGitへ保存しない | secrets/.gitignore、audit | make check、make audit |
| mandatory公開は443のみ | NGINXのみports | make check、make test |
| README attribution/sections | README.md | make check |
| user documentation | USER_DOC.md | human review |
| developer documentation | DEV_DOC.md | human review |
| OVAとgeneric Debianのbootstrap分離 | inception-setup vs host-setup | make doctor、docs |
| OVAのsubmit commit非固定 | runtime clone/fast-forward | inception-evaluate |
| future userspace dependency | .inception/host-tools | inception-evaluate |
| Redis secret permission | root bootstrap -> tmpfs ACL -> gosu redis | make bonus、make bonus-test |
| Redis危険command制限 | -@allからのexplicit command allowlist | make check、make bonus-test |
| hidden file direct access拒否 | NGINX dotfile location | make check、runtime HTTP check |
| FTPS write boundary | uploadsのみwrite許可、core/plugin/theme/traversal/rename拒否、uploads PHP実行拒否 | make bonus-test |
| dependency freshness | WordPress公式version-check + upstream archive SHA-256照合 | make dependency-audit、CI |
| WordPress auth salts永続化 | .inception-state/saltsをatomic生成・再利用 | restart test、make test |
| backup restore可能性 | 一時DBへSQL restore、別tmpdirへWordPress archive展開 | make bonus-test |
| crash/partial-state recovery | PID1 kill + WordPress partial publish residueからの再収束 | Submit Compatibility CI |
| storage pressure検知 | Docker data-root block/inode/free-space閾値 | make audit |
| privileged host update provenance | ABI9以降は.inception/host-sourceの40hex commitへ固定 | host ABI CI、inception-host-update |
| bonus全体の実証 | bonus-smoke-test.sh | make bonus-test |
| threat-hypothesis review | security-audit.sh | make audit |

## OVA compatibility contract

公開OVAはassessment sourceを内包しません。submit branchが更新されても通常はOVAを再生成しません。

submit側が守るcontract:

1. host dependencyを増やす場合、.inception/host-toolsへ command と nixpkgs attribute を追加する。
2. host kernel/VirtualBox hardwareに依存しない通常のuserspace変更はrepo内で完結させる。
3. OVAではmake host-setupを呼ばない。
4. make configure、make doctor、make checkがOVAのmanaged Docker data-rootで成立する。
5. domain locality判定は127.0.0.1固定ではなくVM自身のaddressを許可する。

## リリース判定

次を満たすまで検証済みと表現しません。

1. 提出対象と同一内容を新規専用VMへ配置した。
2. empty Docker stateからmandatory imageをbuildした。
3. make check、make doctor、make test が0終了した。
4. persistence、restart、down/up、TLS、公開portを実証した。
5. bonusを主張する場合はmandatory合格後にmake bonusとmake bonus-testを完走した。
6. backupを別の隔離環境へrestoreした。
7. make auditで仮説検証を実施した。
8. 実施者とは別のreviewerが結果とlogを確認した。

## OVA CI gate

OVA imageの変更時は次を要求します。

1. NixOS integration checks
2. baseline tool availability
3. current submitとのconfigure/doctor/check contract
4. current submit mandatory build/up/test
5. current submit bonus/bonus-test
6. OVA manifest digest verification
7. VirtualBox import dry-run
8. split artifact recombination checksum

submitだけが更新された場合、OVA再生成ではなくcompatibility CIを優先します。userspace dependency不足はhost-tools contractで吸収します。
