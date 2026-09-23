# Inception Universal OVA

[日本語](README.ja.md)

This branch builds the reusable VirtualBox environment used to evaluate and work on the Inception project.

The appliance deliberately does not contain or pin the assessed source tree. The primary workflow is:

    inception-setup YOUR_42_LOGIN
    mkdir ~/inception-evaluation
    cd ~/inception-evaluation
    git clone --branch submit --single-branch https://github.com/kyanagis/Inception.git Inception
    cd Inception
    make

Clone into a newly-created empty directory as required by the evaluation sheet. The
repository may live in any empty directory; `/home/YOUR_42_LOGIN` is reserved for
the mandatory persistent data path, not for the repository. The clone generates its
runtime `srcs/.env` from the OVA identity and verifies the appliance host ABI automatically.

For a complete mandatory and bonus validation:

    inception-evaluate --full

The OVA contains Docker/Compose, Nix, jq, Python, C/C++ build tools, GDB, strace, shellcheck, nmap, tcpdump, socat, Git, ripgrep, rsync, tmux, Firefox, VSCodium, Meld, Kitty, Vim, Xfce Terminal, Mousepad, and the `inception-audit` hypothesis-driven diagnostic runner.

Ordinary future changes to the `submit` branch do not require rebuilding the appliance. Project-specific behavior lives behind `submit/.inception/evaluate`. Missing userspace commands can be supplied through `.inception/host-tools`, while host-level changes are applied in-place with `inception-host-update` using `nixosConfigurations.inception-runtime`.

Host-runtime changes are normally applied in place with `inception-host-update`; a kernel change requires one reboot after the switch. Rebuilding the OVA is reserved for changes that cannot be expressed safely in-place, such as CPU architecture, VirtualBox virtual hardware, disk image layout/capacity, or bootstrap content required before the updater can run.

CI gates an OVA build on:

1. NixOS integration tests.
2. Universal tooling availability.
3. The current `submit` mandatory stack.
4. The current `submit` bonus stack.
5. Hypothesis-driven security checks.
6. OVA manifest verification.
7. VirtualBox dry-run import.
8. Split-artifact recombination checksum verification.

Ordinary `main` pushes do not rebuild the appliance. OVA publication is explicit (`workflow_dispatch`) or version-tag driven. The published `ova-latest` is then re-downloaded and smoke-tested independently.
