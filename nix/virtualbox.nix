# References:
# - NixOS VirtualBox image: https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/virtualbox-image.nix

{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:

let
  cfg = config.virtualbox;
in
{
  imports = [
    "${modulesPath}/virtualisation/virtualbox-image.nix"
  ];

  image.baseName = "inception";
  virtualisation.diskSize = 30720;

  # The nixpkgs channel source contains hundreds of thousands of small files
  # and is unnecessary in this project VM. Omitting it prevents cptofs from
  # spending hours copying unrelated source files.
  system.build.image = lib.mkForce (
    import "${modulesPath}/../lib/make-disk-image.nix" {
      name = cfg.vmDerivationName;
      baseName = config.image.baseName;
      inherit pkgs lib config;
      partitionTableType = "legacy";
      inherit (config.virtualisation) diskSize;
      additionalSpace = "${toString cfg.baseImageFreeSpace}M";
      copyChannel = false;
      postVM = ''
        export HOME=$PWD
        export PATH=${pkgs.virtualbox}/bin:$PATH

        echo "converting image to VirtualBox format..."
        VBoxManage convertfromraw $diskImage disk.vdi

        echo "creating VirtualBox VM..."
        vmName="${cfg.vmName}";
        VBoxManage createvm --name "$vmName" --register --ostype Linux26_64
        VBoxManage modifyvm "$vmName" \
          --memory ${toString cfg.memorySize} \
          ${lib.cli.toCommandLineShellGNU { } cfg.params}
        VBoxManage storagectl "$vmName" ${lib.cli.toCommandLineShellGNU { } cfg.storageController}
        VBoxManage storageattach "$vmName" --storagectl ${cfg.storageController.name} \
          --port 0 --device 0 --type hdd --medium disk.vdi

        echo "exporting VirtualBox VM..."
        mkdir -p $out
        fn="$out/${config.image.fileName}"
        VBoxManage export "$vmName" --output "$fn" --options manifest ${lib.escapeShellArgs cfg.exportParams}
        ${cfg.postExportCommands}
        rm -v $diskImage

        mkdir -p $out/nix-support
        echo "file ova $fn" >> $out/nix-support/hydra-build-products
      '';
    }
  );

  # Keep the Plasma look and daily-use tools while dropping unrelated apps.
  services.desktopManager.plasma6.enableQt5Integration = lib.mkForce false;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    aurorae
    plasma-browser-integration
    kwin-x11
    qttools
    elisa
    gwenview
    okular
    khelpcenter
    baloo-widgets
    dolphin-plugins
    ffmpegthumbs
    krdp
    plasma-keyboard
    qtvirtualkeyboard
  ];

  fonts.packages = lib.mkForce (
    with pkgs;
    [
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ]
  );

  documentation = {
    enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };

  virtualbox = {
    memorySize = 4096;
    vmName = "Inception";
    params = {
      cpus = 4;
      ioapic = "on";
    };
  };
}
