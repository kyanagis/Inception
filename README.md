# Inception VirtualBox Appliance

[日本語](README.ja.md)

A NixOS-based VirtualBox appliance for working on the 42 Inception project.
It recreates a personal desktop environment in a simplified form focused on
Inception.

## Getting the OVA

Download the following files from the GitHub Release:

- `inception.ova.part-aa`
- `inception.ova.part-ab`
- `inception.ova.sha256`

[Inception VirtualBox OVA Release](https://github.com/kyanagis/Inception/releases/tag/ova-latest)

Place all three files in the same directory and assemble the OVA:

```sh
cat inception.ova.part-* > inception.ova
```

Verify the assembled file:

```sh
sha256sum -c inception.ova.sha256
```

The result should be:

```text
inception.ova: OK
```

## Importing into VirtualBox

1. Open VirtualBox.
2. Select **File → Import Appliance**.
3. Select the assembled `inception.ova`.
4. Review the VM name, memory, CPU, and storage location.
5. Click **Import**.
6. Start the `Inception` VM after the import completes.

The default configuration is:

- 4 CPUs
- 4 GiB of memory
- NAT networking
- A 30 GiB dynamically allocated virtual disk

### If an Inception VM already exists

An existing VM or virtual disk can cause a `VERR_ALREADY_EXISTS` error during
import. In that case, use a different VM name such as `Inception-clean`, choose
a different VirtualBox storage directory, or inspect the directory left by the
failed import.

If the existing VM contains data you need, do not delete it. Import the new VM
with a different name or storage location.

## First boot setup

The VM automatically logs into the `inception` Plasma user.

Initial password:

```text
inception
```

On first login, enter your 42 login in the setup dialog. If you close the
dialog, run the following command in a terminal:

```sh
inception-setup YOUR_42_LOGIN
```

For example:

```sh
inception-setup kyanagis
```

Open a new terminal after changing the login. The setup creates the following:

```text
/home/YOUR_42_LOGIN/data
YOUR_42_LOGIN.42.fr
```

## Values used for the Inception project

Clone each user's Inception repository inside the VM and use the configured
login in the following locations:

```text
Docker named volume data:
/home/YOUR_42_LOGIN/data

WordPress domain:
YOUR_42_LOGIN.42.fr
```

## Included environment

- NixOS and KDE Plasma
- Docker Engine and Docker Compose
- Git, GNU Make, OpenSSL, curl, Vim, and Kitty
- A simplified personal desktop environment focused on Inception
- A first-login 42 login setup tool

Microsoft Visual Studio Code and Google Chrome are not included because their
licenses do not allow redistribution in a public OVA. If needed, install them
yourself after reviewing their licenses:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#vscode
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#google-chrome
```
