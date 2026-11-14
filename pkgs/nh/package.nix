{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  nix-output-monitor,
  sqlite,
}:
let
  sources = lib.importJSON ./hashes.json;
  inherit (sources) version hashes;
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "nh";
  inherit version;

  src = fetchurl {
    url = "https://github.com/nix-community/nh/releases/download/v${version}/nh-${system}";
    hash = hashes.${system};
  };

  dontUnpack = true;
  dontStrip = true;
  # Preserve the upstream Mach-O binary; only Linux needs loader patching.
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;
  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    sqlite
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/libexec/nh"
    makeWrapper "$out/libexec/nh" "$out/bin/nh" \
      --prefix PATH : ${lib.makeBinPath [ nix-output-monitor ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/nh" --version)" = "nh $version"
    runHook postInstallCheck
  '';

  meta = {
    description = "Yet another Nix CLI helper";
    homepage = "https://github.com/nix-community/nh";
    changelog = "https://github.com/nix-community/nh/releases/tag/v${version}";
    license = lib.licenses.eupl12;
    mainProgram = "nh";
    platforms = builtins.attrNames hashes;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
