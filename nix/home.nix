# Self-contained Home Manager configuration for the public Inception VM.
# This intentionally contains only non-sensitive UI/tool preferences.

{ lib, pkgs, ... }:

let
  wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/DarkestHour/contents/images/1920x1080.jpg";
in
{
  home.sessionVariables.KDE_COREDUMP_NOTIFY = "0";

  programs.git = {
    enable = true;
    ignores = [ "compile_commands.json" ];
    iniContent = {
      branch.sort = "-committerdate";
      commit.verbose = true;
      diff.algorithm = "histogram";
      fetch.prune = true;
      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      push.autoSetupRemote = true;
      rerere = {
        enabled = true;
        autoupdate = true;
      };
      tag.sort = "version:refname";
      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      dark = true;
      features = "decorations";
      line-numbers = true;
      navigate = true;
      side-by-side = true;
      syntax-theme = "Nord";
      decorations = {
        commit-decoration-style = "bold #88c0d0 box ul";
        file-decoration-style = "#4c566a ul";
        file-style = "bold #81a1c1";
      };
    };
  };

  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };

    settings = {
      background = "#000000";
      background_opacity = "0.78";
      foreground = "#c8c8c8";

      color0 = "#000000";
      color1 = "#cd0000";
      color2 = "#00cd00";
      color3 = "#cdcd00";
      color4 = "#5f87af";
      color5 = "#af5faf";
      color6 = "#00afaf";
      color7 = "#c8c8c8";
      color8 = "#666666";
      color9 = "#ff5f5f";
      color10 = "#5fff5f";
      color11 = "#ffff5f";
      color12 = "#87afd7";
      color13 = "#d787d7";
      color14 = "#5fd7d7";
      color15 = "#ffffff";

      cursor = "#c8c8c8";
      cursor_text_color = "#000000";
      cursor_shape = "block";
      cursor_blink_interval = 0;

      selection_background = "#404040";
      selection_foreground = "#ffffff";

      active_border_color = "#808080";
      inactive_border_color = "#303030";
      tab_bar_style = "hidden";

      confirm_os_window_close = 0;
      enable_audio_bell = false;
      hide_window_decorations = "no";
      scrollback_lines = 100000;
      window_padding_width = 6;
    };

    shellIntegration.mode = "enabled";
  };

  home.file.".vimrc".text = ''
    set nocompatible
    set encoding=utf-8
    set background=dark
    set number
    set relativenumber
    set cursorline
    set scrolloff=5
    set sidescrolloff=5
    set nowrap
    set hidden
    set autoread
    set splitright
    set splitbelow
    set wildmenu
    set showcmd
    set ruler
    set laststatus=2
    set backspace=indent,eol,start
    set ignorecase
    set smartcase
    set incsearch
    set hlsearch
    set mouse=a
    set tabstop=4
    set shiftwidth=4
    set softtabstop=4
    set noexpandtab
    set nomodeline
    set noexrc

    if has('termguicolors')
      set termguicolors
    endif

    syntax enable
    filetype plugin indent on

    highlight Normal guifg=#C8C8C8 guibg=#000000 ctermfg=252 ctermbg=0
    highlight NormalNC guifg=#C8C8C8 guibg=#000000 ctermfg=252 ctermbg=0
    highlight EndOfBuffer guifg=#000000 guibg=#000000 ctermfg=0 ctermbg=0
    highlight LineNr guifg=#606060 guibg=#000000 ctermfg=241 ctermbg=0
    highlight CursorLine guibg=#101010 ctermbg=NONE
    highlight CursorLineNr guifg=#FFFFFF guibg=#000000 gui=bold cterm=bold
    highlight StatusLine guifg=#000000 guibg=#C8C8C8 gui=NONE
    highlight StatusLineNC guifg=#808080 guibg=#181818 gui=NONE

    set statusline=%f%m%r%h%w\ %=%y\ %l:%c\ %p%%

    let mapleader=" "
    nnoremap <silent> <leader>w :write<CR>
    nnoremap <silent> <leader>q :quit<CR>
    nnoremap <silent> <leader>h :nohlsearch<CR>
    nnoremap <C-h> <C-w>h
    nnoremap <C-j> <C-w>j
    nnoremap <C-k> <C-w>k
    nnoremap <C-l> <C-w>l

    augroup ctf_filetypes
      autocmd!
      autocmd FileType python setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
      autocmd FileType c,cpp setlocal tabstop=4 shiftwidth=4 softtabstop=4 noexpandtab
      autocmd FileType asm setlocal tabstop=8 shiftwidth=8 softtabstop=8 noexpandtab
    augroup END
  '';

  programs.plasma = {
    enable = true;
    overrideConfig = false;

    workspace = {
      theme = "Nordic";
      colorScheme = "BreezeDark";
      iconTheme = "Papirus-Dark";
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
      };
      widgetStyle = "Breeze";
      windowDecorations = {
        library = "org.kde.breeze";
        theme = "Breeze";
      };
      splashScreen.theme = "org.kde.breeze.desktop";
      soundTheme = "freedesktop";
      wallpaper = lib.mkForce wallpaper;
      wallpaperFillMode = "preserveAspectCrop";
    };

    session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";

    kscreenlocker = {
      autoLock = true;
      lockOnResume = true;
      timeout = 5;
      passwordRequired = true;
      passwordRequiredDelay = 0;
      appearance.wallpaper = wallpaper;
    };

    krunner.shortcuts.launch = [ ];

    powerdevil = {
      AC = {
        autoSuspend.action = "nothing";
        dimDisplay = {
          enable = true;
          idleTimeout = 240;
        };
        turnOffDisplay = {
          idleTimeout = 1800;
          idleTimeoutWhenLocked = 60;
        };
        whenLaptopLidClosed = "sleep";
        inhibitLidActionWhenExternalMonitorConnected = true;
        powerProfile = "performance";
      };

      battery = {
        autoSuspend = {
          action = "sleep";
          idleTimeout = 900;
        };
        dimDisplay = {
          enable = true;
          idleTimeout = 180;
        };
        turnOffDisplay = {
          idleTimeout = 300;
          idleTimeoutWhenLocked = 30;
        };
        whenLaptopLidClosed = "sleep";
        inhibitLidActionWhenExternalMonitorConnected = true;
        powerProfile = "balanced";
      };

      lowBattery = {
        autoSuspend = {
          action = "sleep";
          idleTimeout = 300;
        };
        dimDisplay = {
          enable = true;
          idleTimeout = 60;
        };
        turnOffDisplay = {
          idleTimeout = 120;
          idleTimeoutWhenLocked = 20;
        };
        whenLaptopLidClosed = "sleep";
        powerProfile = "powerSaving";
      };

      batteryLevels = {
        lowLevel = 15;
        criticalLevel = 5;
        criticalAction = "shutDown";
      };

      general.pausePlayersOnSuspend = true;
    };

    panels = [
      {
        location = "bottom";
        height = 32;
        floating = true;
        alignment = "center";
        lengthMode = "fill";
        opacity = "translucent";

        widgets = [
          {
            plasmaPanelColorizer = {
              general = {
                enable = true;
                hideWidget = true;
              };
              panelBackground = {
                originalBackground.hide = true;
                customBackground = {
                  enable = true;
                  colorSource = "custom";
                  customColor = "#000000";
                  opacity = 0.5;
                };
              };
              textAndIcons = {
                enable = true;
                colorMode.mode = "static";
                colors = {
                  source = "custom";
                  customColor = "#ffffff";
                  opacity = 1.0;
                };
              };
              blacklist = {
                enable = true;
                widgets = [
                  "luisbocanegra.panel.colorizer"
                  "org.kde.plasma.kickoff"
                  "org.kde.plasma.icontasks"
                  "org.kde.plasma.systemtray"
                  "org.kde.plasma.showdesktop"
                ];
              };
            };
          }
          {
            kickoff = {
              icon = "start-here-kde-symbolic";
              label = "";
              sortAlphabetically = true;
              compactDisplayStyle = true;
              sidebarPosition = "left";
              favoritesDisplayMode = "list";
              applicationsDisplayMode = "list";
              showButtonsFor.custom = [
                "reboot"
                "shutdown"
              ];
              showActionButtonCaptions = false;
              popupWidth = 620;
              popupHeight = 460;
            };
          }
          {
            pager = {
              general = {
                displayedText = "desktopNumber";
                showWindowOutlines = false;
                showApplicationIconsOnWindowOutlines = false;
                navigationWrapsAround = false;
                selectingCurrentVirtualDesktop = "showDesktop";
              };
            };
          }
          {
            iconTasks = {
              launchers = [
                "applications:kitty.desktop"
                "applications:code.desktop"
                "applications:google-chrome-ime.desktop"
                "applications:org.kde.dolphin.desktop"
              ];
              appearance = {
                fill = true;
                iconSpacing = "small";
                rows.multirowView = "never";
              };
            };
          }
          {
            systemTray = {
              icons = {
                spacing = "small";
                scaleToFit = true;
              };
            };
          }
          {
            digitalClock = {
              date = {
                enable = true;
                format = "isoDate";
                position = "besideTime";
              };
              time = {
                format = "24h";
                showSeconds = "never";
              };
              font = {
                family = "JetBrainsMono Nerd Font";
                bold = false;
                size = 9;
              };
            };
          }
          "org.kde.plasma.showdesktop"
        ];
      }
    ];

    kwin = {
      borderlessMaximizedWindows = true;
      virtualDesktops = {
        rows = 1;
        names = [
          "term"
          "code"
          "web"
          "lab"
        ];
      };
      effects = {
        blur.enable = true;
        cube.enable = false;
        shakeCursor.enable = false;
        desktopSwitching.animation = "fade";
        windowOpenClose.animation = "fade";
      };
    };

    shortcuts = {
      "services/kitty.desktop"._launch = "Meta+Return";
      "services/org.kde.konsole.desktop"._launch = [ ];

      kwin = {
        Cube = [ ];
        Overview = "Meta+W";
        "Show Desktop" = "Meta+D";
        "Toggle Taskbar" = "Meta+Alt+B";
        "Window Maximize" = [
          "Meta+Up"
          "Meta+PgUp"
        ];
        "Window Minimize" = [
          "Meta+PgDown"
          "Meta+Down"
        ];
        "Window Quick Tile Bottom" = [ ];
        "Window Quick Tile Top" = [ ];
      };

      plasmashell = {
        "next activity" = "Meta+A";
        "previous activity" = "Meta+Shift+A";
      };
    };

    configFile = {
      kdeglobals.KDE = {
        LookAndFeelPackage = "org.kde.breezedark.desktop";
        AnimationDurationFactor = 0.5;
      };

      "drkonqi-coredump-launcher.notifyrc"."Event/applicationCrash".Action = "None";
      drkonqirc.General.IncludeAll = false;

      kwinrc = {
        Compositing = {
          Backend = "wayland";
          Enabled = true;
        };
        "Effect-kwin4_effect_geometry_change".Duration = 180;
        "Effect-overview".BorderActivate = 9;
        ElectricBorders.TopRight = "KRunner";
        Plugins = {
          dialogparentEnabled = false;
          scaleEnabled = false;
          kwin4_effect_geometry_changeEnabled = true;
          toggle-taskbarEnabled = true;
        };
        Wayland.InputMethod = "/run/current-system/sw/share/applications/fcitx5-wayland-launcher.desktop";
        Xwayland.Scale = 1;
      };
    };
  };
}
