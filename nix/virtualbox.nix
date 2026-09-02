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
  userName = "inception";
  kittyConf = pkgs.writeText "inception-kitty.conf" ''
    confirm_os_window_close 0
    enable_audio_bell no
    editor vim
  '';
  vimConf = pkgs.writeText "inception-vimrc" ''
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
    if has('termguicolors') | set termguicolors | endif
    syntax enable
    filetype plugin indent on
    highlight Normal guifg=#C8C8C8 guibg=#000000 ctermfg=252 ctermbg=0
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
  zshConf = pkgs.writeText "inception-zshrc" ''
    bindkey -e
    bindkey '^I' expand-or-complete
    setopt COMPLETE_IN_WORD AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS
    setopt APPEND_HISTORY EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST
    setopt HIST_FIND_NO_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
    setopt HIST_SAVE_NO_DUPS SHARE_HISTORY INTERACTIVE_COMMENTS NO_BEEP
    HISTSIZE=100000
    SAVEHIST=100000
    HISTFILE="$HOME/.zsh_history"
    zstyle ':completion:*' menu select
    zstyle ':completion:*' group-name ""
    zstyle ':completion:*' squeeze-slashes true
    zstyle ':completion:*' special-dirs true
    zstyle ':completion:*' completer _complete _match _approximate
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
    autoload -Uz compinit
    compinit
    alias ..='cd ..'
    alias ...='cd ../..'
    alias c=clear
    alias ll='ls -lah'
    alias la='ls -A'
    alias l='ls -lAh'
    alias ports='ss -tulpn'
    alias vimdiff='vim -d'
    PROMPT='%n@%m:%~ %# '
  '';
  xfceShortcuts = pkgs.writeText "inception-xfce4-keyboard-shortcuts.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfce4-keyboard-shortcuts" version="1.0">
      <property name="commands" type="empty">
        <property name="custom" type="empty">
          <property name="&lt;Super&gt;Return" type="string" value="kitty"/>
        </property>
      </property>
    </channel>
  '';
  xfceSession = pkgs.writeShellScript "inception-xfce-session" ''
    # LightDM autologin can reach the X session before the per-user D-Bus
    # environment is usable.  Give XFCE its own session bus deterministically.
    unset DBUS_SESSION_BUS_ADDRESS
    export XDG_CONFIG_DIRS="${pkgs.xfce4-session}/etc/xdg:/etc/xdg:/run/current-system/sw/etc/xdg"
    export XDG_DATA_DIRS="${pkgs.xfce4-session}/share:/run/current-system/sw/share:/usr/local/share:/usr/share"
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.bash}/bin/bash -c '
      ${pkgs.xfconf}/lib/xfce4/xfconf/xfconfd &
      xfconfd_pid=$!
      trap "kill $xfconfd_pid 2>/dev/null || true" EXIT
      for attempt in $(seq 1 50); do
        ${pkgs.xfconf}/bin/xfconf-query -c xfce4-session -l >/dev/null 2>&1 && break
        sleep 0.1
      done
      exec ${pkgs.xfce4-session}/bin/startxfce4
    '
  '';
in
{
  imports = [
    "${modulesPath}/virtualisation/virtualbox-image.nix"
  ];

  image.baseName = "inception";
  virtualisation.diskSize = 30720;

  services = {
    xserver.enable = true;
    xserver.displayManager.lightdm.enable = true;
    displayManager.defaultSession = "xfce";
    xserver.desktopManager.xfce.enable = true;
    # LightDM does not always inherit the XFCE session paths in appliance
    # images; make them explicit so xfce4-session can locate xfconf and its
    # D-Bus session configuration.
    xserver.displayManager.sessionCommands = ''
      export XDG_CONFIG_DIRS="${pkgs.xfce4-session}/etc/xdg:/etc/xdg:$XDG_CONFIG_DIRS"
      export XDG_DATA_DIRS="${pkgs.xfce4-session}/share:${pkgs.xfce4-session}/share:$XDG_DATA_DIRS"
    '';
    dbus.enable = true;
  };

  programs.xfconf.enable = true;

  environment = {
    sessionVariables = {
      XDG_CONFIG_DIRS = lib.mkForce "${pkgs.xfce4-session}/etc/xdg:/etc/xdg";
      XDG_DATA_DIRS = lib.mkForce "${pkgs.xfce4-session}/share:/usr/local/share:/usr/share";
    };
    etc."xdg/autostart/inception-setup.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Configure Inception 42 Login
      Comment=Configure /home/<login>/data and <login>.42.fr
      Exec=/run/current-system/sw/bin/inception-setup --first-login
      Terminal=false
      OnlyShowIn=XFCE;
    '';
    systemPackages = with pkgs; [
      kitty
      vim
    ];
  };

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

  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml".source =
    xfceShortcuts;
  environment.etc."kitty/kitty.conf".source = kittyConf;
  environment.etc."vimrc".source = vimConf;
  environment.etc."zsh/inception.zshrc".source = zshConf;

  systemd.services.inception-user-config = {
    description = "Install portable shell, Kitty, and Vim configuration";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.config
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.cache
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.local
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.local/share
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.local/state
      install -d -o ${userName} -g users -m 0755 /home/${userName}/.config/kitty
      if [ ! -e /home/${userName}/.config/kitty/kitty.conf ]; then
        install -o ${userName} -g users -m 0644 ${kittyConf} /home/${userName}/.config/kitty/kitty.conf
      fi
      if [ ! -e /home/${userName}/.vimrc ]; then
        install -o ${userName} -g users -m 0644 ${vimConf} /home/${userName}/.vimrc
      fi
      if [ ! -e /home/${userName}/.zshrc ]; then
        install -o ${userName} -g users -m 0644 ${zshConf} /home/${userName}/.zshrc
      fi
      install -o ${userName} -g users -m 0755 ${xfceSession} /home/${userName}/.xsession
    '';
  };

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
