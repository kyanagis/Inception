{ config, pkgs, ... }:

let
  inceptionEvaluate = pkgs.writeShellApplication {
    name = "inception-evaluate";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      docker
      docker-compose
      gawk
      git
      gnumake
      gnugrep
      iproute2
      jq
      nix
      util-linux
    ];
    text = builtins.readFile ./scripts/inception-evaluate.sh;
  };

  inceptionHostUpdate = pkgs.writeShellApplication {
    name = "inception-host-update";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      git
      gnugrep
      nix
    ];
    text = builtins.readFile ./scripts/inception-host-update.sh;
  };

  inceptionAudit = pkgs.writeShellApplication {
    name = "inception-audit";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      docker-compose
      gawk
      git
      gnumake
      gnugrep
      iproute2
      jq
      procps
      util-linux
    ];
    text = builtins.readFile ./scripts/inception-audit.sh;
  };
in
{
  environment.etc."inception-host-abi".text = "5\n";
  environment.etc."inception-kernel-version".text =
    "${config.boot.kernelPackages.kernel.modDirVersion}\n";

  # Broad, license-free baseline.  Ordinary submit changes should consume this
  # environment instead of forcing a new appliance build.  If a future submit
  # revision still needs another userspace command, inception-evaluate can
  # satisfy the repository's .inception/host-tools contract with nix shell.
  environment.systemPackages = with pkgs; [
    inceptionAudit
    inceptionEvaluate
    inceptionHostUpdate

    bashInteractive
    btop
    cmake
    coreutils
    curl
    file
    findutils
    gawk
    gcc
    gdb
    git
    gnumake
    gnugrep
    gnused
    htop
    iproute2
    iputils
    jq
    less
    lsof
    ncdu
    nix
    nmap
    openssl
    pkg-config
    procps
    python3
    ripgrep
    rsync
    shellcheck
    shfmt
    socat
    strace
    tcpdump
    tmux
    tree
    util-linux
    vim
    wget
    which
  ];
}
