# Inception

[日本語](README.ja.md)

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
