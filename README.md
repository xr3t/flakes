# Flakes

Nix packages by `Prompter`.

> [!WARNING]
> **DYOR (Do Your Own Research).** These packages are written largely with AI
> agents and provided as-is, without warranty. Upstream binaries are fetched
> from their official release pages and pinned by hash, but that only proves
> the download is unchanged, not that the program is safe. Read the package
> definition and the upstream project before installing, especially anything
> that runs as a system service or with root privileges.
>
> See [SECURITY.md](SECURITY.md) for what the pins and checks cover, and to
> report a vulnerability.

## Packages

| Package | Description |
|---|---|
| [1mcp](pkgs/1mcp) | Unified MCP runtime that aggregates MCP servers behind one endpoint, with a NixOS service module |
| [anoa](pkgs/anoa) | Anoa headless browser (CDP, a command per action for agents) from upstream's Linux bundle, run unpatched in an FHS environment; Linux only, no compilation |
| [bend](pkgs/bend) | Bend parallel functional language (runs `.bend` files directly or builds native binaries) from upstream's prebuilt release, with clang on Linux; update check off, no self-update; Apple Silicon macOS and Linux, no compilation |
| [cloudflare-warp](pkgs/cloudflare-warp) | Cloudflare WARP client (`warp-cli`, the `warp-svc` daemon and tray app, or the macOS app) from upstream's deb and installer (unfree), with a nix-darwin/NixOS service module that keeps its update check off; Apple Silicon macOS and Linux, no compilation |
| [codex](pkgs/codex) | OpenAI Codex CLI from upstream's prebuilt npm release; Apple Silicon macOS and Linux, no compilation |
| [cua-driver](pkgs/cua-driver) | Desktop control driver for Hermes' computer_use; telemetry and update check off by default; Linux only, no compilation |
| [muxin](pkgs/muxin) | One desktop app for all your machines and their AI agents (sessions, desktops, logs, files) over ssh, with its CLI and MCP server, from upstream's prebuilt release; Apple Silicon macOS and Linux, no compilation |
| [nh](pkgs/nh) | Nix CLI helper from prebuilt upstream binaries, without Rust compilation |
| [pi](pkgs/pi) | Pi coding agent from published npm packages with Node.js 24 LTS; local assembly, no Pi source compilation |
| [nodejs-24-lts](pkgs/nodejs-24-lts) | Official prebuilt Node.js 24 LTS with independently pinned npm latest; no source compilation |
| [ghostty](pkgs/ghostty) | Ghostty terminal's latest release from upstream's Ghostty.dmg; macOS only, no compilation |
| [ghostty-tip](pkgs/ghostty) | Ghostty's rolling tip build from main, bumped daily |
| [google-chrome](pkgs/google-chrome) | Google Chrome's latest Stable release from Google's signed dmg (unfree); macOS only, no compilation |
| [herdr](pkgs/herdr) | Herdr desktop app, herdr-core (`hc`) and the `herdr` CLI from upstream's prebuilt releases, with a nix-darwin/NixOS module that routes its updates through Nix; Apple Silicon macOS and Linux, no compilation |
| [helium](pkgs/helium) | Helium browser (Chromium-based, private by default) from upstream's signed, notarized dmg on macOS and its binary tarball on Linux, with a Home Manager module that keeps its update check off; Apple Silicon macOS and Linux, no compilation |
| [hermes-agent](pkgs/hermes-agent) | Hermes Agent pinned to upstream's latest stable release tag (`minimal` + telegram, mcp), with upstream's NixOS and Home Manager modules; x86_64 Linux only |
| [littlesnitch](pkgs/littlesnitch) | Little Snitch for Linux network monitor (unfree freeware binary), with a NixOS service module |
| [lite-xl](pkgs/lite-xl) | Lite XL editor from upstream's addons release (language plugins, colour schemes) as Lite XL.app, Apple Silicon only |
| [nullclaw](pkgs/nullclaw) | Small, fully autonomous AI assistant in one static Zig binary, with a Home Manager module that runs it as upstream's user service |
| [nullclaw-chat-ui](pkgs/nullclaw-chat-ui) | NullClaw's web chat UI as static files, to serve from any web server |
| [opencode](pkgs/opencode) | OpenCode 2 AI coding agent from upstream's prebuilt npm release, kept on Nix (no self-update); Apple Silicon macOS and Linux, no compilation |
| [rayfish](pkgs/rayfish) | P2P mesh VPN (iroh), with a nix-darwin/NixOS service module |
| [tailscale](pkgs/tailscale) | Tailscale CLI and node agent (`tailscale`, `tailscaled`, no GUI) from upstream's static build, for NixOS' `services.tailscale`; log upload off by default, no self-update; Linux only, no compilation |
| [utm](pkgs/utm) | UTM virtual machine host for macOS from the upstream release dmg, no compilation |

## Usage

```nix
{
  inputs.xr3t.url = "github:xr3t/flakes";
  inputs.xr3t.inputs.nixpkgs.follows = "nixpkgs";

  # Either take packages straight from the flake (pinned nixpkgs) ...
  environment.systemPackages = [ inputs.xr3t.packages.${system}.rayfish ];

  # ... or build them against your own nixpkgs through the overlay.
  nixpkgs.overlays = [ inputs.xr3t.overlays.default ];
  environment.systemPackages = [ pkgs.xr3t.rayfish ];

  # Packages with a service module:
  modules = [ inputs.xr3t.darwinModules.rayfish ];  # or nixosModules
}
```

Or run one without installing: `nix run github:xr3t/flakes#rayfish -- --version`.

## Outputs

- `packages.<system>.<name>`: only packages that build on `<system>`
- `overlays.default`: adds `pkgs.xr3t.<name>`
- `darwinModules.<name>`, `nixosModules.<name>`: for packages that have a
  `module.nix` (both), `darwin-module.nix` or `nixos-module.nix` (one only)
- `homeManagerModules.<name>`: for packages that have a `home-module.nix`
- `checks.<system>.<name>`: builds every package but the rolling
  `ghostty-tip`; `checks.<system>.formatting`
  checks that every `.nix` file is formatted, `checks.<linux>.nixos-modules`
  that the NixOS modules evaluate
- `formatter`: `nixfmt`

Systems: `aarch64-darwin`, `aarch64-linux`, `x86_64-linux`.

## Updates

Packages follow upstream automatically: a workflow checks for new releases
twice a day and commits them to `main`, and the pinned nixpkgs is bumped
weekly. Pick them up with `nix flake update xr3t`. Updates of root daemons,
network filters and agents, and of nixpkgs, go through a pull request that is
merged once it builds on every system; see [SECURITY.md](SECURITY.md) for what is checked.

## License

Each packaged program keeps its own license, set by its authors. All product
names, logos and trademarks belong to their respective owners and creators.
This repository is not affiliated with or endorsed by them.
