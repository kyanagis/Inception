set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

check:
  nix flake check path:. -L

fmt:
  nix fmt

vbox:
  nix build path:.#packages.x86_64-linux.vbox -o result-vbox
