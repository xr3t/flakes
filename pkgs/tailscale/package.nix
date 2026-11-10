{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  getent,
  iproute2,
  iptables,
  procps,
  shadow,
}:

let
  # Version and per-system hashes live in hashes.json so update.sh can rewrite
  # them without touching Nix code.
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version hashes;

  # Upstream's static Linux builds: the tarball pkgs.tailscale.com/stable lists
  # beside its .sha256. There is no CLI-only build for macOS (only the app).
  arches = {
    "aarch64-linux" = "arm64";
    "x86_64-linux" = "amd64";
  };

  system = stdenvNoCC.hostPlatform.system;
  arch = arches.${system} or (throw "Tailscale has no prebuilt CLI release for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "tailscale";
  inherit version;

  src = fetchurl {
    url = "https://pkgs.tailscale.com/stable/tailscale_${version}_${arch}.tgz";
    hash = hashes.${system};
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 tailscaled "$out/libexec/tailscale/tailscaled"
    install -Dm755 tailscale "$out/libexec/tailscale/tailscale"

    # What tailscaled runs from PATH (routes, firewall rules, user lookups).
    # Logs upload to Tailscale unless TS_NO_LOGS_NO_SUPPORT is set, to
    # anything, by the unit, /etc/default/tailscaled or the shell.
    makeWrapper "$out/libexec/tailscale/tailscaled" "$out/bin/tailscaled" \
      --prefix PATH : ${
        lib.makeBinPath [
          getent
          iproute2
          iptables
          shadow
        ]
      } \
      --suffix PATH : ${lib.makeBinPath [ procps ]} \
      --set-default TS_NO_LOGS_NO_SUPPORT true

    # `tailscale update` would replace the binaries (it falls back to a
    # tarball update where it finds no package manager); the flake updates
    # them instead.
    makeWrapper "$out/libexec/tailscale/tailscale" "$out/bin/tailscale" \
      --run ${lib.escapeShellArg ''
        skip=
        for arg in "$@"; do
          if [ -n "$skip" ]; then skip=; continue; fi
          case $arg in
            --socket|-socket) skip=1 ;;
            -*) ;;
            update)
              echo "tailscale: installed through Nix; update the flake input that provides it instead" >&2
              exit 1
              ;;
            *) break ;;
          esac
        done
      ''}

    # Upstream's units, run from the store. The unit loads
    # /etc/default/tailscaled for the port and extra flags, which the package
    # does not ship: PORT gets upstream's default there instead, and a drop-in
    # (nixpkgs' services.tailscale writes one) overrides it.
    install -Dm444 -t "$out/lib/systemd/system" systemd/tailscaled.service \
      systemd/tailscale-wait-online.service systemd/tailscale-online.target
    substituteInPlace "$out/lib/systemd/system/tailscaled.service" \
      --replace-fail "EnvironmentFile=/etc/default/tailscaled" "Environment=PORT=41641" \
      --replace-fail "/usr/sbin/" "$out/bin/"
    substituteInPlace "$out/lib/systemd/system/tailscale-wait-online.service" \
      --replace-fail "/usr/bin/" "$out/bin/"

    mkdir -p "$out/share/bash-completion/completions" \
      "$out/share/fish/vendor_completions.d" "$out/share/zsh/site-functions"
    "$out/libexec/tailscale/tailscale" completion bash > "$out/share/bash-completion/completions/tailscale"
    "$out/libexec/tailscale/tailscale" completion fish > "$out/share/fish/vendor_completions.d/tailscale.fish"
    "$out/libexec/tailscale/tailscale" completion zsh > "$out/share/zsh/site-functions/_tailscale"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for tool in tailscale tailscaled; do
      "$out/bin/$tool" --version | head -n1 | grep -qx "$version"
    done
    if "$out/bin/tailscale" update; then
      echo "tailscale update was not refused" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Tailscale CLI and node agent (tailscale, tailscaled) from upstream's static builds, without a GUI";
    homepage = "https://tailscale.com/";
    changelog = "https://tailscale.com/changelog";
    license = lib.licenses.bsd3;
    mainProgram = "tailscale";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames hashes;
  };
}
