{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  # Version and per-system hashes live in hashes.json so update.sh can rewrite
  # them without touching Nix code.
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version hashes;

  arches = {
    "aarch64-linux" = "arm64";
    "x86_64-linux" = "amd64";
  };

  system = stdenvNoCC.hostPlatform.system;
  arch = arches.${system} or (throw "Little Snitch for Linux has no prebuilt release for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "littlesnitch";
  inherit version;

  # Upstream's static musl tarball: usr/bin/littlesnitch, its systemd unit and
  # the license text. Checksums: https://obdev.at/downloads/littlesnitch-linux/littlesnitch-<version>.hashes.txt
  src = fetchurl {
    url = "https://obdev.at/downloads/littlesnitch-linux/littlesnitch-${version}-${arch}-linux-musl.tar.gz";
    hash = hashes.${system};
  };

  sourceRoot = "littlesnitch-${version}";

  # The license allows redistribution only of the unmodified binary, and it is
  # static: never strip or patch it.
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  # The unit keeps upstream's sandboxing; only ExecStart points into the store.
  installPhase = ''
    runHook preInstall
    install -Dm755 usr/bin/littlesnitch "$out/bin/littlesnitch"
    install -Dm644 usr/lib/systemd/system/littlesnitch.service "$out/lib/systemd/system/littlesnitch.service"
    substituteInPlace "$out/lib/systemd/system/littlesnitch.service" \
      --replace-fail /usr/bin/littlesnitch "$out/bin/littlesnitch"
    install -Dm644 usr/share/doc/littlesnitch/copyright "$out/share/doc/littlesnitch/copyright"
    runHook postInstall
  '';

  # Run as is: the binary is static and unpatched.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/littlesnitch" --version | grep -F "Version: $version" >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Network monitor that shows and filters which programs connect where (Linux, eBPF)";
    homepage = "https://obdev.at/products/littlesnitch-linux/";
    license = {
      shortName = "obdev-freeware";
      fullName = "Little Snitch for Linux Proprietary Freeware License";
      url = "https://obdev.at/products/littlesnitch-linux/";
      free = false;
      redistributable = true;
    };
    mainProgram = "littlesnitch";
    platforms = builtins.attrNames hashes;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
