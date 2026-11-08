{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  cpio,
  dbus,
  desktop-file-utils,
  dpkg,
  gtk3,
  libayatana-appindicator,
  libpcap,
  makeWrapper,
  nftables,
  nss,
  openssl,
  python3,
  tpm2-tss,
  webkitgtk_4_1,
  xar,
  # Leave out the tray app and its GUI libraries (GTK, WebKit): warp-cli and
  # warp-svc only. Linux only; use `.override { headless = true; }`.
  headless ? false,
}:

let
  # Version and per-system hashes live in hashes.json so update.sh can rewrite
  # them without touching Nix code.
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version hashes;

  # Upstream's download service serves the same files as its apt repository
  # (pkg.cloudflareclient.com) and the macOS installer, by version.
  download = "https://downloads.cloudflareclient.com/v1/download";
  sources = {
    "aarch64-darwin" = {
      url = "${download}/macos/version/${version}";
      name = "Cloudflare_WARP_${version}.pkg";
    };
    "aarch64-linux" = {
      url = "${download}/noble-arm/version/${version}";
      name = "cloudflare-warp_${version}_arm64.deb";
    };
    "x86_64-linux" = {
      url = "${download}/noble-intel/version/${version}";
      name = "cloudflare-warp_${version}_amd64.deb";
    };
  };

  system = stdenv.hostPlatform.system;
  source = sources.${system} or (throw "Cloudflare WARP has no prebuilt release for ${system}");
  isDarwin = stdenv.hostPlatform.isDarwin;
in
stdenv.mkDerivation {
  pname = "cloudflare-warp" + lib.optionalString headless "-headless";
  inherit version;

  src = fetchurl {
    inherit (source) url name;
    hash = hashes.${system};
  };

  nativeBuildInputs =
    if isDarwin then
      [
        xar
        cpio
        python3
      ]
    else
      [
        autoPatchelfHook
        dpkg
        makeWrapper
      ]
      ++ lib.optional (!headless) desktop-file-utils;

  buildInputs = lib.optionals (!isDarwin) (
    [
      dbus
      libpcap
      nss
      openssl
      tpm2-tss
      (lib.getLib stdenv.cc.cc)
    ]
    ++ lib.optionals (!headless) [
      gtk3
      libayatana-appindicator
      webkitgtk_4_1
    ]
  );

  # libdartjni.so (the tray app's Flutter runtime) links libjvm.so, which only
  # matters on Android. warp-dex asks for libpcap by its Debian soname, which
  # is replaced below.
  autoPatchelfIgnoreMissingDeps = [
    "libjvm.so"
    "libpcap.so.0.8"
  ];

  unpackPhase =
    if isDarwin then
      ''
        runHook preUnpack
        xar -xf "$src"
        zcat < Cloudflare_WARP_${version}.pkg/Payload | cpio -i
        runHook postUnpack
      ''
    else
      ''
        runHook preUnpack
        dpkg-deb -x "$src" .
        runHook postUnpack
      '';

  dontConfigure = true;
  dontBuild = true;

  # Upstream's signed app bundle: stripping or patching would break its code
  # signature (and the system extension inside it).
  dontFixup = isDarwin;
  # The bundled Sparkle.framework has a dangling XPCServices symlink, as in
  # upstream's own installer.
  dontCheckForBrokenSymlinks = isDarwin;

  installPhase =
    if isDarwin then
      ''
        runHook preInstall
        mkdir -p "$out/Applications" "$out/bin"
        cp -R "Cloudflare WARP.app" "$out/Applications/"
        # What upstream's installer links into /usr/local/bin, minus
        # warp-updater (see the README).
        for tool in warp-cli warp-dex warp-diag; do
          ln -s "$out/Applications/Cloudflare WARP.app/Contents/Resources/$tool" "$out/bin/$tool"
        done
        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        # The deb installs under /bin, /etc, /lib and /usr; everything goes
        # into $out.
        mv usr "$out"
        mv bin etc "$out"/
        mv lib/systemd/system "$out/lib/systemd/"
        patchelf --replace-needed libpcap.so.0.8 ${lib.getLib libpcap}/lib/libpcap.so "$out/bin/warp-dex"

        # Upstream's unit, with ExecStart pointed into the store.
        substituteInPlace "$out/lib/systemd/system/warp-svc.service" \
          --replace-fail "ExecStart=" "ExecStart=$out"
        ${
          if headless then
            ''
              # No tray app: drop it and everything only it uses.
              rm "$out/bin/warp-taskbar"
              rm -r "$out/lib/systemd/user" "$out/etc" "$out/lib/warp" \
                "$out/share/applications" "$out/share/dbus-1" "$out/share/icons"
            ''
          else
            ''
              substituteInPlace "$out"/share/applications/*.desktop \
                "$out/share/dbus-1/services/com.cloudflare.WarpTaskbar.service" \
                --replace-fail "Exec=" "Exec=$out"
              # The tray app runs warp-diag as /usr/bin/warp-diag: show it
              # this package as /usr.
              substituteInPlace "$out/lib/systemd/user/warp-taskbar.service" \
                --replace-fail "ExecStart=" "ExecStart=$out"
              cat >> "$out/lib/systemd/user/warp-taskbar.service" <<EOF

              [Service]
              BindReadOnlyPaths=$out:/usr:
              EOF
            ''
        }
        runHook postInstall
      '';

  postInstall = lib.optionalString (!isDarwin) ''
    # warp-svc runs nft from PATH for some checks, and /usr/sbin/nft for others
    # (the NixOS module binds nftables there).
    wrapProgram "$out/bin/warp-svc" --prefix PATH : ${lib.makeBinPath [ nftables ]}
    ${lib.optionalString (!headless) ''
      wrapProgram "$out/bin/warp-cli" --prefix PATH : ${lib.makeBinPath [ desktop-file-utils ]}
      wrapProgram "$out/bin/warp-taskbar" --prefix LD_LIBRARY_PATH : "$out/lib/warp/lib"
    ''}
  '';

  # For the NixOS module: whether the tray app is part of this build.
  passthru.headless = headless;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${
      if isDarwin then
        ''${python3.interpreter} ${../../lib/check-app.py} "$out/Applications/Cloudflare WARP.app" "$version"''
      else
        # Not warp-svc: it ignores --version and starts the daemon.
        ''
          for tool in warp-cli warp-dex warp-diag; do
            "$out/bin/$tool" --version | grep -qF "$version"
          done
        ''
    }
    runHook postInstallCheck
  '';

  meta = {
    description =
      "Cloudflare WARP client (1.1.1.1 with WARP, Cloudflare One Client) from upstream's packages"
      + lib.optionalString headless ", without the tray app";
    homepage = "https://one.one.one.one/";
    changelog = "https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/download/";
    license = lib.licenses.unfree;
    mainProgram = "warp-cli";
    platforms = builtins.attrNames hashes;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
