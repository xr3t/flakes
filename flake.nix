{
  description = "Nix packages by Prompter";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = lib.genAttrs systems;

      # Every directory under pkgs/ is a package: pkgs/<name>/package.nix.
      pkgDirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./pkgs);
      packageNames = builtins.attrNames pkgDirs;

      # Unfree packages this flake's own `packages` allow. Overlay users allow
      # them in their own nixpkgs config.
      allowedUnfree = [
        "cloudflare-warp"
        "cloudflare-warp-headless"
        "google-chrome"
        "littlesnitch"
      ];

      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;
        }
      );

      # All packages built against `pkgs`, in one scope so they can depend on
      # each other by argument name.
      mkPackagesFor =
        pkgs:
        let
          scope = lib.makeScope pkgs.newScope (
            self: lib.genAttrs packageNames (name: self.callPackage ./pkgs/${name}/package.nix { })
          );
        in
        lib.genAttrs packageNames (name: scope.${name});

      # Packages whose evaluation fetches another flake (Hermes). Their
      # platforms are given here, matching their meta.platforms, so listing
      # packages.<system> or using any module never fetches Hermes on other
      # systems.
      fixedPlatforms = {
        hermes-agent = [ "x86_64-linux" ];
      };

      # Only expose packages that build on the given system.
      available =
        system: name: pkg:
        if fixedPlatforms ? ${name} then
          builtins.elem system fixedPlatforms.${name}
        else
          lib.meta.availableOn pkgsFor.${system}.stdenv.hostPlatform pkg && !(pkg.meta.broken or false);

      # Service modules, by file name in pkgs/<name>/: module.nix is exported for
      # both nix-darwin and NixOS, darwin-module.nix / nixos-module.nix for one,
      # home-module.nix for Home Manager.
      modulesFrom =
        file:
        lib.genAttrs (builtins.filter (name: builtins.pathExists ./pkgs/${name}/${file}) packageNames) (
          name: import ./pkgs/${name}/${file} self
        );
      # Rolling builds: upstream replaces the file behind their URL with every
      # build, so a pin fails its hash until the next update. Left out of
      # checks; update.yml builds them when it bumps them.
      rolling = [
        "ghostty-tip"
      ];

      # Used by checks.<system>.nixos-modules. hermes-agent is left out: it is
      # upstream's module, and evaluating it fetches upstream's flake.
      nixosModulesTest =
        system:
        nixpkgs.lib.nixosSystem {
          modules = [
            self.nixosModules."1mcp"
            self.nixosModules.cloudflare-warp
            self.nixosModules.herdr
            self.nixosModules.littlesnitch
            self.nixosModules.rayfish
            {
              nixpkgs.hostPlatform = system;
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              system.stateVersion = "25.11";
              users.users.alice.isNormalUser = true;
              programs.herdr.enable = true;
              services = {
                "1mcp" = {
                  enable = true;
                  user = "alice";
                  settings.mcpServers = { };
                };
                cloudflare-warp.enable = true;
                littlesnitch.enable = true;
                rayfish.enable = true;
              };
            }
          ];
        };
    in
    {
      packages = eachSystem (
        system: lib.filterAttrs (available system) (mkPackagesFor pkgsFor.${system})
      );

      overlays.default = import ./overlays { inherit mkPackagesFor; };

      darwinModules = modulesFrom "module.nix" // modulesFrom "darwin-module.nix";
      nixosModules = modulesFrom "module.nix" // modulesFrom "nixos-module.nix";
      homeManagerModules = modulesFrom "home-module.nix";

      # Every package but the rolling ones, and every .nix file formatted
      # with `nix fmt`.
      checks = eachSystem (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        removeAttrs self.packages.${system} rolling
        // {
          formatting = pkgs.runCommand "formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            find ${self} -name '*.nix' -exec nixfmt --check {} +
            touch "$out"
          '';
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          # A NixOS system with every NixOS module here enabled, evaluated
          # (not built): its drv path is the check's only content.
          nixos-modules = pkgs.writeText "nixos-modules" (
            builtins.unsafeDiscardStringContext (nixosModulesTest system).config.system.build.toplevel.drvPath
          );
        }
      );

      formatter = eachSystem (system: pkgsFor.${system}.nixfmt);
    };
}
