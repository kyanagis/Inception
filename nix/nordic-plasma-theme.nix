{
  fetchFromGitHub,
  gzip,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "nordic-plasma-theme";
  version = "1.0.1-5078055";

  src = fetchFromGitHub {
    owner = "EliverLara";
    repo = "Nordic-kde";
    rev = "5078055624735a48699c758aa55edec5fd859e48";
    hash = "sha256-NJTF8v1MjXBOmEX/YmUpMeRrtlOOVOljNQZzOw5p4OE=";
  };

  nativeBuildInputs = [ gzip ];

  postPatch = ''
    gzip -cd widgets/panel-background.svgz > widgets/panel-background.svg
    substituteInPlace widgets/panel-background.svg \
      --replace-fail 'stop-color:#000;stop-opacity:.2' 'stop-color:#000;stop-opacity:.08' \
      --replace-fail 'stop-color:#000;stop-opacity:.1' 'stop-color:#000;stop-opacity:.04' \
      --replace-fail 'stop-color:#000;stop-opacity:.05' 'stop-color:#000;stop-opacity:.02' \
      --replace-fail 'stop-color:#000;stop-opacity:.025' 'stop-color:#000;stop-opacity:.01' \
      --replace-fail 'opacity:0.7;fill:#2f343f;fill-opacity:1' 'opacity:0;fill:#2f343f;fill-opacity:0'
    gzip -n -9 widgets/panel-background.svg
    mv widgets/panel-background.svg.gz widgets/panel-background.svgz
  '';

  installPhase = ''
    runHook preInstall
    theme="$out/share/plasma/desktoptheme/Nordic"
    mkdir -p "$theme"
    cp -r LICENSE README.md colors dialogs icons metadata.desktop preview widgets "$theme/"
    runHook postInstall
  '';

  meta = {
    description = "Nordic Plasma theme with transparent-panel patch";
    homepage = "https://github.com/EliverLara/Nordic-kde";
    license = lib.licenses.cc-by-sa-40;
    platforms = lib.platforms.linux;
  };
}
