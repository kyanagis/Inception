# References:
# - Nix flakes: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake
# - NixOS module system: https://nixos.org/manual/nixos/stable/#sec-writing-modules
# - NixOS VirtualBox image: https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/virtualbox-image.nix

{
  description = "Reproducible VirtualBox NixOS VM for the 42 Inception project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    desktop-config = {
      url = "git+ssh://git@github.com/kyanagis/nixos-config.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.plasma-manager.follows = "plasma-manager";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      nixpkgs,
      desktop-config,
      home-manager,
      plasma-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      hostName = "inception";
      userName = "inception";
      pkgs = nixpkgs.legacyPackages.${system};
      baseModule = import ./nix/base.nix { inherit hostName userName; };
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
          (import "${desktop-config}/modules/system/desktop.nix")
          hostBootModule
        ];
      };
      vbox = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
          (import "${desktop-config}/modules/system/desktop.nix")
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit userName;
                inputs = {
                  inherit desktop-config home-manager plasma-manager;
                };
              };
              sharedModules = [
                plasma-manager.homeModules.plasma-manager
              ];
              users.${userName} = {
                imports = [
                  "${desktop-config}/modules/home/git.nix"
                  "${desktop-config}/modules/home/kitty.nix"
                  "${desktop-config}/modules/home/plasma.nix"
                  "${desktop-config}/modules/home/vim.nix"
                  "${desktop-config}/modules/home/wallpaper.nix"
                ];

                home = {
                  packages = with pkgs; [
                    bibata-cursors
                    papirus-nord
                    plasma-panel-colorizer
                    (callPackage "${desktop-config}/packages/nordic-plasma-theme.nix" { })
                  ];

                  username = userName;
                  homeDirectory = "/home/${userName}";
                  stateVersion = "26.05";
                };

                xdg.configFile."autostart/inception-setup.desktop".text = ''
                  [Desktop Entry]
                  Type=Application
                  Name=Configure Inception 42 Login
                  Comment=Configure /home/<login>/data and <login>.42.fr
                  Exec=/run/current-system/sw/bin/inception-setup --first-login
                  Terminal=false
                  X-KDE-autostart-after=panel
                '';

                home.file."Desktop/INCEPTION-SETUP.txt".text = ''
                  Inception VM 利用手順
                  =====================

                  共通のOSアカウント名は inception、初期パスワードも inception です。

                  初回ログイン時に表示される設定画面へ、自分の42ログインを入力してください。
                  設定画面を閉じた場合や、あとから変更する場合は次を実行できます。

                      inception-setup YOUR_42_LOGIN

                  これにより、次のパス・ドメイン・環境変数が設定されます。

                    /home/YOUR_42_LOGIN/data
                    YOUR_42_LOGIN.42.fr
                    INCEPTION_LOGIN, DOMAIN_NAME, INCEPTION_DATA_DIR

                  設定後は新しいターミナルを開いてください。

                  Microsoft Visual Studio CodeとGoogle Chromeは、公開OVAには同梱していません。
                  必要な場合はインターネット接続後、各ソフトウェアのライセンスを確認したうえで
                  次のコマンドをターミナルから実行してください。

                      NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#vscode
                      NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure nixpkgs#google-chrome

                  インストール後にアプリ一覧へ表示されない場合は、一度ログアウトして
                  ログインし直してください。
                '';

                xdg = {
                  enable = true;
                  userDirs = {
                    enable = true;
                    createDirectories = true;
                  };
                };

                programs.home-manager.enable = true;
              };
            };
          }
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
