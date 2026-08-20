# Inception

[English](#inception) | [日本語](#japanese)

This is a 42 Inception project.

The goal is to build a small infrastructure composed of multiple containers,
issue a self-signed TLS certificate, and deploy a web service over HTTPS.

## Environment setup

The published Release contains a NixOS-based VirtualBox appliance for working
on the Inception project.

The OVA provides the basic working environment, including NixOS, KDE Plasma,
Docker, and Docker Compose.

For instructions on downloading, assembling, verifying, and importing the OVA,
as well as completing the initial setup, see the README on the
[`inception-ova` branch](https://github.com/kyanagis/Inception/tree/inception-ova).

The OVA can be downloaded from the following Release:

[Inception VirtualBox OVA Release](https://github.com/kyanagis/Inception/releases/tag/ova-latest)

---

<a id="japanese"></a>

## Inception（日本語）

これは42のInception projectです。

複数のコンテナから構成される小規模なインフラを構築し、
TLS自己証明書を発行してWebサービスをHTTPSで公開することが課題の目的です。

## 環境構築について

公開しているReleaseには、Inception課題を進めるための
NixOSベースのVirtualBox環境を構築したOVAが含まれています。

OVAにはNixOS、KDE Plasma、Docker、Docker Composeなど、
課題を進めるための基本的な作業環境が含まれています。

OVAのダウンロード方法、結合方法、SHA-256の確認方法、
VirtualBoxへのインポート方法、初回設定方法については、
[`inception-ova`ブランチ](https://github.com/kyanagis/Inception/tree/inception-ova)
のREADMEを参照してください。

OVA本体は次のReleaseから取得できます。

[Inception VirtualBox OVA Release](https://github.com/kyanagis/Inception/releases/tag/ova-latest)
