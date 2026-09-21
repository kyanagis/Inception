# Inception Universal OVA

[日本語](README.ja.md)

This branch builds the reusable VirtualBox environment used to evaluate and work on the Inception project.

The appliance deliberately does not contain or pin the assessed source tree. After initial setup it fetches the current `submit` branch at runtime:

    inception-setup YOUR_42_LOGIN
    inception-evaluate --prepare

For a complete mandatory and bonus validation:

    inception-evaluate --full

The OVA contains Docker/Compose, Nix, jq, Python, C/C++ build tools, GDB, strace, shellcheck, nmap, tcpdump, socat, Git, ripgrep, rsync, tmux, Firefox, VSCodium, Meld, Kitty, Vim, and the `inception-audit` hypothesis-driven diagnostic runner.

Ordinary future changes to the `submit` branch do not require rebuilding the appliance. The evaluator fast-forwards a clean local checkout to `origin/submit`. If a future revision needs another ordinary userspace command, `.inception/host-tools` can declare the command and a safe nixpkgs attribute; the evaluator supplies missing packages through an ephemeral Nix shell.

An OVA rebuild is still appropriate when the guest itself must change—for example its kernel capabilities, CPU architecture, VirtualBox hardware definition, base disk capacity, or other host-level facilities.

CI gates an OVA build on:

1. NixOS integration tests.
2. Universal tooling availability.
3. The current `submit` mandatory stack.
4. The current `submit` bonus stack.
5. Hypothesis-driven security checks.
6. OVA manifest verification.
7. VirtualBox dry-run import.
8. Split-artifact recombination checksum verification.

Successful `main` builds publish the verified artifact to the `ova-latest` GitHub Release. Version tags produce immutable versioned releases.
