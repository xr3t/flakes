# cloudflare-warp

A Nix package and service module for the
[Cloudflare WARP client](https://one.one.one.one/) (the Cloudflare One Client,
formerly 1.1.1.1 with WARP): `warp-cli`, the `warp-svc` daemon and the tray
app on Linux, `Cloudflare WARP.app` and its daemon on macOS. One `module.nix`
covers both nix-darwin (launchd) and NixOS (systemd).

The package installs upstream's prebuilt client and compiles nothing. The
pinned release (`version` in `hashes.json`) is for:

| System | Upstream file | Checked against |
|---|---|---|
| `x86_64-linux` | the `.deb` for Ubuntu noble, from Cloudflare's download service (the file in the `pkg.cloudflareclient.com` apt repository) | the sha256 that apt index lists |
| `aarch64-linux` | the same, for arm64 | the same |
| `aarch64-darwin` | `Cloudflare_WARP_<version>.pkg` (macOS 14 or later) | nothing: Cloudflare lists no checksum for it, so it is pinned by the hash of the download |

On Linux the binaries are patched with `autoPatchelfHook` to run on NixOS and
any other distribution. On macOS the signed app bundle is copied out of the
installer's payload untouched (`dontFixup`: patching would break its code
signature and the system extension inside it) into `$out/Applications`, with
`warp-cli`, `warp-dex` and `warp-diag` in `$out/bin`.

## License: unfree

The client is proprietary. This flake's own `packages` allow it. Through the
overlay, allow it in your nixpkgs:

```nix
nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "cloudflare-warp" ];
```

## Usage

```nix
{
  inputs.xr3t.url = "github:xr3t/flakes";
  inputs.xr3t.inputs.nixpkgs.follows = "nixpkgs";

  # nix-darwin
  darwinConfigurations.<host> = nix-darwin.lib.darwinSystem {
    modules = [
      inputs.xr3t.darwinModules.cloudflare-warp
      { services.cloudflare-warp.enable = true; }
    ];
  };

  # NixOS
  nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
    modules = [
      inputs.xr3t.nixosModules.cloudflare-warp
      { services.cloudflare-warp.enable = true; }
    ];
  };
}
```

Then register and connect with `warp-cli` (`warp-cli registration new`,
`warp-cli connect`; it asks you to accept Cloudflare's terms of service).

`darwinModules.cloudflare-warp` and `nixosModules.cloudflare-warp` are the same
module. It detects nix-darwin from the `launchd` option. nixpkgs has its own
`services.cloudflare-warp` module, with other options (`rootDir`, `udpPort`,
`openFirewall`); on NixOS this module replaces it (`disabledModules`), so
importing both is fine but those options are gone.

### Without the tray app (Linux)

The tray app (GTK and WebKitGTK) is most of the closure. For a server, leave it
out; `taskbar.enable` then defaults to `false`:

```nix
{
  services.cloudflare-warp = {
    enable = true;
    package = inputs.xr3t.packages.${pkgs.stdenv.hostPlatform.system}.cloudflare-warp.override {
      headless = true;
    };
  };
}
```

Through the overlay, allow `cloudflare-warp-headless` as well as
`cloudflare-warp` in `allowUnfreePredicate`.

## Options

| Option | Default | Platform | Description |
|---|---|---|---|
| `services.cloudflare-warp.enable` | `false` | both | Run the WARP daemon and put `warp-cli` on `PATH`. |
| `services.cloudflare-warp.package` | this flake's package | both | Package to run. No overlay needed. |
| `services.cloudflare-warp.settings` | `{ allow_updates = false; }`, plus `allow_managed_deployments = false` on macOS | both | The client's [deployment parameters](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/deployment/mdm-deployment/parameters/), written to its `mdm.xml`. Values are booleans, integers or strings. Setting it replaces the defaults; `{ }` writes nothing (see below). |
| `services.cloudflare-warp.taskbar.enable` | `true`, `false` for the headless package | NixOS | Start the tray app with the graphical session, as upstream's deb does. |

`settings` is also how to enroll in a Zero Trust organization declaratively:

```nix
services.cloudflare-warp.settings = {
  allow_updates = false;
  organization = "my-team";
};
```

The module owns the `mdm.xml` it writes and overwrites it on every activation
(`/var/lib/cloudflare-warp/mdm.xml` on NixOS, `/Library/Application
Support/Cloudflare/mdm.xml` on macOS). With `settings = { }` it writes nothing
and leaves an existing file alone, but doesn't remove one it wrote before.
The Linux daemon doesn't pick up an `mdm.xml` that is a link into the store, so
on both systems it is written as a copy.

## Service

- **NixOS:** upstream's own `warp-svc.service` from the package
  (`systemd.packages`; what the deb enables and starts), with `ExecStart`
  pointed into the store, so its capability bounding set and state directories
  follow upstream on every bump. The module adds `lsof` to its `PATH` (the
  daemon's diagnostics use it) and shows it nftables as `/usr/sbin/nft`, which
  it runs by that absolute path. No firewall port is opened: upstream's
  installer doesn't open any. The tray app runs as upstream's
  `warp-taskbar.service` user unit, wanted by `graphical-session.target`, with
  the package bound at `/usr` for it, because it runs `/usr/bin/warp-diag` by
  that path.
- **macOS:** the launchd daemon `com.cloudflare.1dot1dot1dot1.macos.warp.daemon`,
  upstream's plist from the installer's postinstall script (the `CloudflareWARP`
  binary as root, `RunAtLoad`, `KeepAlive`, 32768 open files), except that it
  waits for the Nix store to be mounted at boot. The app starts the tunnel's
  system extension: open `Cloudflare WARP.app` and approve the extension when
  macOS asks. macOS activates a system extension only for an app installed in
  `/Applications`, and whether nix-darwin's copy of the app (under
  `/Applications/Nix Apps`) qualifies is not something this repository checks:
  nothing here starts the daemon or the extension (the install check reads the
  bundle's `Info.plist` and runs nothing).

## Updates and telemetry

Updates come through this flake, so the client's update check is off.

- **Update check: off by default, in the module.** `allow_updates = false` is
  upstream's documented switch for it; the module writes it into `mdm.xml`.
  Without the module, put it there yourself:
  ```xml
  <dict>
    <key>allow_updates</key>
    <false/>
  </dict>
  ```
  To turn the check back on, set `services.cloudflare-warp.settings = { }` (and
  delete the file the module wrote), or set `allow_updates = true`. A parameter
  in `mdm.xml` wins over the same setting in the Zero Trust dashboard.
- **Versions assigned from the Zero Trust dashboard (macOS):** off by default,
  with `allow_managed_deployments = false`, upstream's documented local kill
  switch (macOS and Windows, client 2026.6.0 or later). It only matters on a
  device enrolled in an organization. Upstream's installer also loads a second
  launchd job, `com.cloudflare.warp.updater` (`warp-updater`, not started at
  load), which installs such versions; the module doesn't load it. The tool
  stays in `Cloudflare WARP.app` and unused.
- **Sparkle (macOS):** the app bundle ships with `SUEnableAutomaticChecks`
  false and no feed URL in its `Info.plist`, so the framework doesn't check on
  its own. Nothing in the signed bundle was changed.
- **Linux:** upstream's packaging leaves updates to apt; the client itself only
  offers them while `allow_updates` is on.
- **Crash reporting: on, and upstream documents no switch for it.** The daemon
  starts a crash-reporting component at launch; `warp-svc`, `warp-cli` and
  `warp-diag` embed a Sentry client, and the tray app ships Sentry's native
  SDK with a crash handler. Nothing here turns it off. Registering and
  connecting contact Cloudflare by design.

## Maintenance

`update.sh` takes the version from the apt index for Ubuntu noble and checks
each Linux download against the sha256 it lists. It waits (and changes
nothing) until the macOS installer the download service serves as the latest
GA release is that same version, so one version covers all three systems.
Cloudflare's [release notes](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/download/)
are the changelog.

On a bump, recheck against the new release:

- the deb's `warp-svc.service` and `warp-taskbar.service` (the module uses them
  as shipped), and the absolute paths the binaries run (`/usr/sbin/nft`,
  `/usr/bin/warp-diag`);
- the macOS installer's `postinstall` script and launchd plists (the module
  mirrors the daemon's), and the app's `Info.plist` Sparkle keys;
- the deployment parameters `allow_updates` and `allow_managed_deployments`,
  and whether upstream added a switch for crash reporting.

`warp-svc` ignores `--version` and starts the daemon, so the install check runs
`warp-cli`, `warp-dex` and `warp-diag` instead.
