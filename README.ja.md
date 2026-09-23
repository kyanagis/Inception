# Inception Universal OVA

[English](README.md)

Inceptionの評価・開発に使う x86_64 VirtualBox環境です。

このOVAは評価対象のsourceを内包せず、特定の`submit` commitにも固定しません。基本手順はこれです。

    inception-setup YOUR_42_LOGIN

    cd /home/inception
    git clone --branch submit --single-branch \
      https://github.com/kyanagis/Inception.git Inception
    cd Inception
    make

`make`はOVAに保存された42 loginを読み、runtime用`srcs/.env`を生成してmandatory stackを起動します。

完全検証:

    make test
    make audit
    make bonus-test

またはOVA管理のdisposable checkoutで:

    inception-evaluate --full

OVAにはDocker/Compose、Nix、jq、Python、C/C++ build tools、GDB、strace、shellcheck、nmap、tcpdump、socat、Git、ripgrep、rsync、tmux、Firefox、VSCodium、Meld、Kitty、Vim、Xfce Terminal、Mousepad、仮説駆動診断用の`inception-audit`を同梱します。

通常の`submit`変更ではOVAを再生成しません。project固有の評価手順は`submit/.inception/evaluate`が所有し、不足userspace commandは`.inception/host-tools`からephemeral Nix shellで補完できます。

host runtime側の更新が必要な場合も、通常は`inception-host-update`でcurrent `main#inception-runtime`へin-place更新します。kernelが変わった場合だけ更新後に1回rebootが必要です。

OVAそのものを焼き直すのは、CPU architecture、VirtualBox仮想hardware、base disk layout/capacity、初回bootに必要なbootstrap内容など、既存guestのin-place更新では表現できない変更を入れる場合です。

OVA Source CIはNixOS/runtime/GUI契約を常時検証します。OVA生成は通常のmain pushでは行わず、明示的なrelease実行またはversion tagでのみ行います。生成時はcurrent `submit`のmandatory/bonus/security検証、OVA manifest、VirtualBox import、split checksumを通過したartifactだけをrelease対象にします。公開後はReleased OVA Smokeで実diskのbootとruntime評価を再検証します。
