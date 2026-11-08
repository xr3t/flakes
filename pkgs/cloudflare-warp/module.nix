self:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

# One module for both nix-darwin (launchd) and NixOS (systemd). The platform is
# detected from the declared options rather than `pkgs`, which would recurse.
let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    optionalAttrs
    types
    ;
  cfg = config.services.cloudflare-warp;
  isDarwin = options ? launchd;

  # The client's deployment parameters file (`mdm.xml`), from `settings`.
  # Upstream reads it from the same place whoever writes it (an MDM tool, a
  # script); it must be a regular file, not a link into the store.
  mdmValue =
    v:
    if lib.isBool v then
      (if v then "<true/>" else "<false/>")
    else if lib.isInt v then
      "<integer>${toString v}</integer>"
    else
      "<string>${lib.escapeXML v}</string>";
  mdmXml = lib.concatStrings (
    [ "<dict>\n" ]
    ++ lib.mapAttrsToList (k: v: "  <key>${lib.escapeXML k}</key>\n  ${mdmValue v}\n") cfg.settings
    ++ [ "</dict>\n" ]
  );
  # systemd-tmpfiles takes C-style escapes in a file's contents, and expands
  # % specifiers.
  mdmTmpfiles = lib.replaceStrings [ "\\" "%" "\n" ] [ "\\\\" "%%" "\\n" ] mdmXml;

  daemon = "${cfg.package}/Applications/Cloudflare WARP.app/Contents/Resources/CloudflareWARP";
in
{
  # nixpkgs has a module at the same option path (with other options); this one
  # replaces it on NixOS. Nothing matches on nix-darwin.
  disabledModules = [ "services/networking/cloudflare-warp.nix" ];

  options.services.cloudflare-warp = {
    enable = mkEnableOption "the Cloudflare WARP client daemon";
    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.cloudflare-warp;
      defaultText = literalExpression "xr3t.packages.\${pkgs.stdenv.hostPlatform.system}.cloudflare-warp";
      description = "Cloudflare WARP package to run.";
    };
    settings = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.bool
          types.int
          types.str
        ]
      );
      default = {
        allow_updates = false;
      }
      // optionalAttrs isDarwin { allow_managed_deployments = false; };
      defaultText = literalExpression ''
        { allow_updates = false; }  # and allow_managed_deployments = false on macOS
      '';
      example = literalExpression ''
        {
          allow_updates = false;
          organization = "my-team";
        }
      '';
      description = ''
        Deployment parameters for the client, written to its `mdm.xml`
        (`/var/lib/cloudflare-warp/mdm.xml` on NixOS,
        `/Library/Application Support/Cloudflare/mdm.xml` on macOS); see
        <https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/deployment/mdm-deployment/parameters/>.
        The defaults keep the client from checking for updates, which come
        through Nix (`allow_updates`), and, on macOS, from taking versions
        assigned in the Zero Trust dashboard (`allow_managed_deployments`).
        Setting this replaces the defaults. When it is not empty, this module
        owns the file and overwrites it; `{ }` writes nothing and leaves an
        existing file (and the parameters in it) alone, so you can manage it
        yourself. A parameter the file sets wins over the same setting in the
        Zero Trust dashboard.
      '';
    };
    taskbar.enable = mkOption {
      type = types.bool;
      default = !(cfg.package.headless or false);
      defaultText = literalExpression "true, unless the package is the headless build";
      description = ''
        Start the tray app, `warp-taskbar`, with the graphical session, as
        upstream's deb package does. NixOS only; needs the package without
        `headless = true`.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # warp-cli talks to the running daemon.
    { environment.systemPackages = [ cfg.package ]; }

    (optionalAttrs isDarwin {
      # Upstream's installer loads this daemon (as root, restarted when it
      # exits) from its postinstall script, with the binary in
      # /Applications. Its second job, com.cloudflare.warp.updater, is not
      # loaded: it installs new versions, and those come from Nix.
      launchd.daemons.cloudflare-warp = {
        serviceConfig = {
          Label = "com.cloudflare.1dot1dot1dot1.macos.warp.daemon";
          # The one change for Nix: LaunchDaemons can start before the Nix
          # store is mounted during boot, so wait for it from the system shell
          # instead of letting launchd cache a missing executable.
          ProgramArguments = [
            "/bin/sh"
            "-c"
            ''
              while [ ! -x "${daemon}" ]; do sleep 1; done
              exec "${daemon}"
            ''
          ];
          UserName = "root";
          RunAtLoad = true;
          KeepAlive = true;
          SoftResourceLimits.NumberOfFiles = 32768;
        };
      };

      system.activationScripts.postActivation.text = mkIf (cfg.settings != { }) ''
        # Cloudflare WARP deployment parameters
        mdm_dir="/Library/Application Support/Cloudflare"
        mkdir -p "$mdm_dir"
        if ! /usr/bin/cmp -s ${pkgs.writeText "cloudflare-warp-mdm.xml" mdmXml} "$mdm_dir/mdm.xml"; then
          /usr/bin/install -m 0644 ${pkgs.writeText "cloudflare-warp-mdm.xml" mdmXml} "$mdm_dir/mdm.xml"
        fi
      '';
    })

    (optionalAttrs (!isDarwin) {
      # Upstream's own warp-svc.service from the package (what the deb
      # enables and starts), with ExecStart pointed into the store: its
      # capability bounding set and state directories follow upstream on every
      # bump. The unit has no sandbox.
      systemd = {
        packages = [ cfg.package ];

        services.warp-svc = {
          wantedBy = [ "multi-user.target" ];
          # The daemon's diagnostics look for bound ports with lsof, and run
          # nft by the absolute path /usr/sbin/nft (it would fail on NixOS,
          # which has no such path; the unit sees nftables there).
          path = [ pkgs.lsof ];
          serviceConfig.BindReadOnlyPaths = [ "${pkgs.nftables}/bin/nft:/usr/sbin/nft" ];
        };

        user.services.warp-taskbar.wantedBy = optional cfg.taskbar.enable "graphical-session.target";

        tmpfiles.rules = optional (
          cfg.settings != { }
        ) "f+ /var/lib/cloudflare-warp/mdm.xml 0644 root root - ${mdmTmpfiles}";
      };

      # The tray app's D-Bus activation file, as the deb installs it.
      services.dbus.packages = optional cfg.taskbar.enable cfg.package;
    })
  ]);
}
