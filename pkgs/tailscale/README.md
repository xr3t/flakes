# tailscale

The [Tailscale](https://tailscale.com/) command line and node agent, with no
GUI: `tailscale` (the CLI) and `tailscaled` (the daemon) from upstream's static
Linux builds. It installs the tarball that
[pkgs.tailscale.com/stable](https://pkgs.tailscale.com/stable/) lists for
`x86_64-linux` and `aarch64-linux` and compiles nothing; the pinned release is
`version` in `hashes.json`.

**Linux only.** Upstream's only macOS build is the app (a `.zip` or `.pkg`
with a system extension), which is not a CLI install, so this package has none.
For the CLI and daemon on macOS use nixpkgs' `tailscale`, which is built from
source (its binary is in the NixOS cache). nix-darwin's module runs
`tailscaled` through launchd and puts `tailscale` on the `PATH`:

```nix
services.tailscale.enable = true;
```

That package is not this one: it has none of the settings below, so set them
yourself. Set `TS_NO_LOGS_NO_SUPPORT` for the daemon to stop its log upload
(see Updates and telemetry), and use `tailscale set --update-check=false`.

## Usage

```nix
{
  inputs.xr3t.url = "github:xr3t/flakes";
  inputs.xr3t.inputs.nixpkgs.follows = "nixpkgs";

  # NixOS: nixpkgs' module runs the package's own unit.
  services.tailscale = {
    enable = true;
    package = inputs.xr3t.packages.${pkgs.stdenv.hostPlatform.system}.tailscale;
  };
}
```

Then `sudo tailscale up`. This flake has no service module of its own:
`services.tailscale` in nixpkgs takes a `package`, and the package ships
upstream's `tailscaled.service`, `tailscale-wait-online.service` and
`tailscale-online.target` under `lib/systemd/system` for it (`systemd.packages`).

The units are upstream's, with their paths pointing into the store. The one
change: the unit reads the port and extra flags from `/etc/default/tailscaled`,
a file the package does not ship, so `PORT=41641` (upstream's default) is set
in the unit instead; the NixOS module overrides it with `services.tailscale.port`.
Without that module, link the unit and set `PORT` and `FLAGS` with a drop-in.

`tailscaled` runs `ip`, `iptables`, `getent` and shadow's tools by name, so the
package puts them on its `PATH` (as nixpkgs' build does); the NixOS module adds
a few more.

## Updates and telemetry

Updates come through this flake.

- **Self-update: off.** `tailscale update` is refused by a wrapper around the
  CLI. Upstream has no switch for it, and where it finds no package manager it
  replaces the binaries from a tarball, which here would mean the store (it
  only refuses by itself on NixOS). The daemon can run an update that the
  admin console asks for, or the background auto-update preference, only
  through a `tailscale` in a standard system path such as `/usr/bin`; the
  store has none, so that cannot start either. Run
  `libexec/tailscale/tailscale` from the package to bypass the refusal.
- **Log upload: off by default.** `tailscaled` uploads its logs to Tailscale
  (log.tailscale.com). `TS_NO_LOGS_NO_SUPPORT` is upstream's documented switch
  (the same as `--no-logs-no-support`); the package sets it to `true` unless
  the daemon's environment already sets it, and Tailscale cannot give support
  to a node that has it on. To turn uploads back on, set
  `TS_NO_LOGS_NO_SUPPORT=false` in the daemon's environment, e.g. on NixOS
  `systemd.services.tailscaled.environment.TS_NO_LOGS_NO_SUPPORT = "false";`.
- **Update check: on, and the package cannot turn it off.** It is a preference
  kept in the node's state, not a flag or variable: `tailscaled` checks for
  available updates in the background and notifies about them. Turn it off
  with `sudo tailscale set --update-check=false --auto-update=false` (once;
  the state keeps it), and back on with `--update-check`.
  `services.tailscale.extraSetFlags` runs `tailscale set` only together with
  `authKeyFile`.

Connecting contacts Tailscale's control plane by design.

## Maintenance

`update.sh` reads the stable track's tarball version from
`pkgs.tailscale.com/stable/?mode=json` and checks each tarball against the
`.sha256` file beside it (the bare hash).

On a bump, recheck against the new release:

- `TS_NO_LOGS_NO_SUPPORT` in `tailscaled --help` (`--no-logs-no-support`) and in
  the docs, and whether upstream added a switch for the update check;
- the units in the tarball's `systemd` directory (the install step edits the
  `EnvironmentFile=` line and the `/usr/sbin/` and `/usr/bin/` paths and fails
  if they change);
- `tailscale update` still being refused (the install check runs it).
