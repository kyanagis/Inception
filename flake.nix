# References:
# - Nix flakes: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake
# - NixOS module system: https://nixos.org/manual/nixos/stable/#sec-writing-modules
# - NixOS VirtualBox image: https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/virtualbox-image.nix

{
  description = "Reproducible VirtualBox NixOS VM for the 42 Inception project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      hostName = "inception";
      userName = "inception";
      pkgs = nixpkgs.legacyPackages.${system};
      projectSource = builtins.path {
        path = ./.;
        name = "inception-project-source";
        filter =
          path: type:
          let
            base = builtins.baseNameOf path;
          in
          base != ".git" && base != "secrets" && base != "result" && !(nixpkgs.lib.hasPrefix "result-" base);
      };
      baseModule = import ./nix/base.nix { inherit hostName projectSource userName; };
      hostBootModule = {
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub.devices = [ "/dev/vda" ];
      };
      host = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
          hostBootModule
        ];
      };
      vbox = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
          ./nix/virtualbox.nix
        ];
      };
    in
    {
      nixosConfigurations.${hostName} = host;

      packages.${system} = {
        default = vbox.config.system.build.image;
        vbox = vbox.config.system.build.image;
      };

      checks.${system} = {
        host = host.config.system.build.toplevel;
        vbox-system = vbox.config.system.build.toplevel;
        boot = import ./nix/check.nix {
          inherit pkgs hostName userName;
        };
      };

      formatter.${system} = pkgs.nixfmt-tree;

    };
}
