# References:
# - Plasma Login Manager: https://github.com/KDE/plasma-login-manager
# - Plasma Login Manager 6.6 greeter:
#   https://github.com/KDE/plasma-login-manager/blob/Plasma/6.6/src/frontend/greeter/qml/Main.qml

{ kdePackages }:

kdePackages.plasma-login-manager.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp ${./plasma-login-main.qml} src/frontend/greeter/qml/Main.qml
  '';
})
