# Inception Universal OVA

[English](README.md)

Inceptionの評価・開発に使う再利用可能なVirtualBox環境です。

このOVAは評価対象のsourceを内包せず、特定の`submit` commitにも固定しません。初回設定後、実行時にcurrent `submit` branchを取得します。

    inception-setup YOUR_42_LOGIN
    inception-evaluate --prepare

mandatoryとbonusをまとめて完全検証する場合:

    inception-evaluate --full

OVAにはDocker/Compose、Nix、jq、Python、C/C++ build tools、GDB、strace、shellcheck、nmap、tcpdump、socat、Git、ripgrep、rsync、tmux、Firefox、VSCodium、Meld、Kitty、Vim、仮説駆動診断用の`inception-audit`を同梱します。

通常の`submit`変更ではOVAを再生成しません。evaluatorはcleanなlocal checkoutを`origin/submit`へfast-forwardします。将来通常のuserspace commandが追加で必要になった場合は、submit側の`.inception/host-tools`でcommandと安全なnixpkgs attributeを宣言でき、不足packageだけephemeral Nix shellで補完します。

guest kernel機能、CPU architecture、VirtualBox hardware定義、base disk容量など、OVAそのもののhost-level要件が変わる場合は再生成対象です。

OVA CIは生成前にcurrent `submit`のmandatory/bonusを実際に起動・検証し、その後manifest、VirtualBox import、split artifact checksumまで確認します。

`main`の成功buildは検証済みartifactを`ova-latest` Releaseへ反映し、version tagはimmutableなversioned releaseを作成します。
