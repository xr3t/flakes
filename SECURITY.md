# Security

This is a personal flake, maintained on a best-effort basis. It repackages
other people's software. Read this before relying on it, especially for the
packages that run as system services.

## Reporting a vulnerability

Report it privately through GitHub: **Security → Report a vulnerability** on
this repository. Don't open a public issue for it.

Report here:

- the Nix code, modules and scripts in this repository (`flake.nix`,
  `pkgs/*/package.nix`, `*module.nix`, `update.sh`, `lib/`);
- the workflows in `.github/workflows/`;
- a pinned hash or URL that downloads something other than upstream's
  official release.

A vulnerability in a packaged program goes to its upstream project, linked
from each package's `meta.homepage`. Tell us too if this flake makes it worse,
for example by exposing it in a module.

Expect an answer within a week or so. Only the latest commit on `main` gets
fixes; there are no release branches.

## Trust model

- **Prebuilt upstream binaries.** Almost every package installs upstream's
  official release as published (GitHub releases, npm, vendor download
  servers). Nothing is audited here.
- **Hashes pin, they don't vouch.** `hashes.json` proves a download is the one
  that was fetched when the update ran, not that it is safe. Where upstream
  publishes more, `update.sh` checks it as well: Node's `SHASUMS256.txt` must
  carry a signature by a Node release key; downloads must match the checksums
  upstream lists beside them (checksum files, package indexes, update
  manifests, Chrome's update server); GitHub release assets must match the
  digest GitHub recorded at upload; and npm packages are pinned by the registry's integrity hash. Every upstream version goes through `check_version`
  (`lib/update.sh`) before it reaches a URL, `hashes.json` or a commit
  message.
- **Rolling builds.** `ghostty-tip` follows upstream builds that are
  replaced in place. Its pin only downloads until the next build.
- **Updates.** New releases are committed to `main` automatically once
  `nix flake check` passes, without review, except for the packages in
  `REVIEW` (root daemons, network filters, agents), whose updates go through
  a pull request that CI merges, also without review, once it builds on Linux
  x86_64, Linux aarch64 and macOS. The pinned nixpkgs, which every package's
  libraries and tools come from, is bumped weekly the same way. See
  [LAYOUT.md](LAYOUT.md) for how the workflow runs.
- **Dependencies follow upstream's lock.** A package assembled from
  upstream's own lockfile installs exactly what that lock names, advisories
  included; they close when upstream ships a new lock and the next update
  picks it up. Nothing is patched here.
- **Updates and telemetry go through Nix.** Packages run as upstream ships
  them, except that self-updates, update checks and telemetry are off wherever
  the package allows it: through upstream's own switch where there is one,
  else an undocumented one (which may stop working on a bump), else a guard
  that refuses the update command. Update checks
  and telemetry are only defaults, which your own config can set back; each
  package's README says what is off and how. An updater built into a signed
  app bundle can only be turned off in the app.
- **Binary cache.** CI pushes only `hermes-agent`'s closure, built from `main`,
  to `ret.cachix.org`; builds of pull requests and `update/<name>` branches
  never reach it. Trusting that cache means trusting this repository's CI.

## CI hardening

- Workflows default to a read-only `GITHUB_TOKEN`; only the update workflow
  can write, to commit updates and open their pull requests, and the check
  workflow's `merge` job, to merge an `update/<name>` pull request it built.
- Secrets reach only the step that uses them (the Cachix push), never a
  whole job.
- Actions are pinned by commit SHA and bumped by Dependabot.

## Service modules

The service modules run each daemon the way upstream's own installer does,
with the binary in the store, and add a sandbox only where upstream ships
one. On macOS (launchd) there is none.

- `littlesnitch`: upstream's own unit, with its capability bounding set and
  sandbox.
- `hermes-agent`: upstream's NixOS module, with its own system user and
  hardening.
- `rayfish`: upstream's unit; root, for its TUN device, routes and resolver,
  and no sandbox.
- `cloudflare-warp`: upstream's own `warp-svc.service` on NixOS, with its
  capability bounding set and no other sandbox, and the daemon's launchd job
  on macOS; root, for its tunnel, routes and DNS.
- `nullclaw` and `1mcp`: no sandbox upstream. `hardening.enable` (off by
  default) adds one: no privilege gain, so no `sudo`; nullclaw can write only
  to its `stateDir` (plus `hardening.readWritePaths`), 1mcp gets a private
  `/tmp` and read-only `/usr`, `/boot` and `/etc`. Turn it on unless the
  agent has to administer the machine.

Agents (`nullclaw`, `hermes-agent`, `codex`, `opencode`, `pi`) run commands a
model chooses. Restrict who can reach them (e.g. nullclaw's `allow_from`) and
what they may do before enabling them, and do it in Nix: an agent can edit a
config file it can write, so put those limits in nullclaw's `settings`
(merged back in on every start) or run Hermes in managed mode
(`nixManagesConfig = true`).

## Secrets

Nothing in the Nix store is secret: it is world-readable. Options such as
`settings` and `environment` end up in the store, so keep tokens and API
keys in the files the modules read at run time (`environmentFile`, Hermes'
`environmentFiles`, nullclaw's `config.json`), ideally managed by sops-nix or
agenix.

This repository is public. Its code, docs and commits carry no private data:
noreply author emails only, and placeholders such as `alice` and
`example.com` in examples.
