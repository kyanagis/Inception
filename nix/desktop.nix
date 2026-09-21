# Self-contained desktop configuration for the public Inception VM.
# Keep this file free of user identities, credentials, SSH material, and other secrets.

{ pkgs, ... }:

let
  loginWallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/DarkestHour/contents/images/1920x1080.jpg";
  plasmaLoginManager = pkgs.callPackage ./plasma-login-manager.nix { };
in
{
  # Preserve the minimal lock-screen password field used by the VM without
  # depending on the private desktop configuration repository.
  nixpkgs.overlays = [
    (_final: prev: {
      kdePackages = prev.kdePackages.overrideScope (
        _kdeFinal: kdePrev: {
          plasma-desktop = kdePrev.plasma-desktop.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace desktoppackage/contents/lockscreen/MainBlock.qml \
                --replace-fail \
'            Layout.fillWidth: true' \
'            Layout.fillWidth: true

            background: Item {
                implicitHeight: 36

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#5CFFFFFF"
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: passwordBox.activeFocus ? parent.width : 0
                    height: 2
                    color: "#E8FFFFFF"

                    Behavior on width {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }'
            '';
          });
        }
      );
    })
  ];

  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    displayManager = {
      plasma-login-manager = {
        enable = true;
        package = plasmaLoginManager;
      };
      defaultSession = "plasma";
    };

    desktopManager.plasma6 = {
      enable = true;
      enableQt5Integration = true;
    };

    power-profiles-daemon.enable = true;
    logind.settings.Login.IdleAction = "ignore";

    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };

  environment.etc."plasmalogin.conf".text = ''
    [Greeter]
    ShowClock=false
    WallpaperPluginId=org.kde.image

    [Greeter][Wallpaper][org.kde.image][General]
    FillMode=2
    Image=file://${loginWallpaper}
  '';

  security.rtkit.enable = true;

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-gtk
      ];

      settings = {
        globalOptions = {
          Hotkey = {
            EnumerateWithTriggerKeys = "True";
            EnumerateSkipFirst = "False";
            ModifierOnlyKeyTimeout = "250";
          };
          "Hotkey/TriggerKeys"."0" = "Super+space";
          Behavior = {
            PreeditEnabledByDefault = "True";
            ShowInputMethodInformation = "True";
          };
        };

        inputMethod = {
          "Groups/0" = {
            Name = "デフォルト";
            "Default Layout" = "us";
            DefaultIM = "mozc";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us";
            Layout = "";
          };
          "Groups/0/Items/1" = {
            Name = "mozc";
            Layout = "";
          };
          GroupOrder."0" = "デフォルト";
        };
      };
    };
  };

  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    NIXOS_OZONE_WL = "1";
  };

  fonts = {
    packages = with pkgs; [
      hack-font
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
    ];

    fontconfig = {
      antialias = true;
      hinting = {
        enable = true;
        style = "full";
      };
      subpixel.rgba = "none";

      defaultFonts = {
        monospace = [
          "JetBrainsMono Nerd Font"
          "Noto Sans Mono CJK JP"
          "Hack"
        ];
        sansSerif = [
          "Noto Sans CJK JP"
          "Noto Sans"
        ];
        serif = [
          "Noto Serif CJK JP"
          "Noto Serif"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
