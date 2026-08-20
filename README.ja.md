# Inception VirtualBoxイメージ

[English](README.md)

42のInception課題用に、個人的なデスクトップ環境を再構築し、
Inception向けに簡略化したNixOS VirtualBoxアプライアンスです。

## OVAを入手する

GitHub Releaseから次のファイルをダウンロードしてください。

- `inception.ova.part-aa`
- `inception.ova.part-ab`
- `inception.ova.sha256`

[Inception VirtualBox OVA Release](https://github.com/kyanagis/Inception/releases/tag/ova-latest)

3つのファイルを同じディレクトリへ置き、OVAを結合します。

```sh
cat inception.ova.part-* > inception.ova
```

結合後、SHA-256を確認します。

```sh
sha256sum -c inception.ova.sha256
```

次のように表示されれば正常です。

```text
inception.ova: OK
```

## VirtualBoxへインポートする

1. VirtualBoxを起動します。
2. 「ファイル」→「仮想アプライアンスのインポート」を選択します。
3. 結合した`inception.ova`を選択します。
4. VM名、メモリ、CPU、保存先を確認します。
5. 「インポート」を押します。
6. インポート完了後、`Inception` VMを起動します。

初期構成：

- CPU：4
- メモリ：4 GiB
- ネットワーク：NAT
- 仮想ディスク：30 GiB、可変サイズ

### 既存のInception VMがある場合

同じ名前や仮想ディスクが残っていると、`VERR_ALREADY_EXISTS`エラーになることがあります。
その場合は、インポート時のVM名を`Inception-clean`など別名にするか、
VirtualBoxの保存先を別のディレクトリにしてください。

既存VMに必要なデータがある場合は削除せず、別名・別保存先でインポートしてください。

## 初回起動後の設定

VMを起動すると、Plasmaへ`inception`ユーザーで自動ログインします。

初期パスワード：

```text
inception
```

初回ログイン時に、42のログイン名を入力する設定画面が表示されます。
設定画面を閉じた場合は、ターミナルで次を実行してください。

```sh
inception-setup YOUR_42_LOGIN
```

例えば、42ログインが`kyanagis`の場合：

```sh
inception-setup kyanagis
```

設定後は、新しいターミナルを開いてください。

設定される値：

```text
データ保存先:
/home/YOUR_42_LOGIN/data

ドメイン:
YOUR_42_LOGIN.42.fr
```

## Inception課題で使用する値

各利用者は、自分のInceptionリポジトリをVM内へcloneして作業してください。

Docker named volumeの保存先：

```text
/home/YOUR_42_LOGIN/data
```

WordPressのドメイン：

```text
YOUR_42_LOGIN.42.fr
```

## OVAの構成

- NixOSとKDE Plasmaデスクトップ
- Docker EngineとDocker Compose
- Git、GNU Make、OpenSSL、curl、Vim、Kitty
- 個人的なデスクトップ環境を再構築し、Inception向けに簡略化したテーマ、壁紙、操作設定
- 42ログインを登録する初回設定ツール

Microsoft Visual Studio CodeとGoogle Chromeは、ライセンスの都合により公開OVAで
再配布できないため、同梱していません。

必要な場合は、各自のライセンス確認後にインストールしてください。

```sh
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#vscode
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#google-chrome
```
