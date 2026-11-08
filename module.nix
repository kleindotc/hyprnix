{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.hyprnix;
  tomlSettingsFormat = pkgs.formats.toml { };

  stateHome =
    let
      xdg = builtins.getEnv "XDG_STATE_HOME";
    in
    if xdg != "" then xdg else "${builtins.getEnv "HOME"}/.cache/state";

  hyprToolsWithConfig = [
    "hyprlock"
    "hypridle"
    "hyprpaper"
    "hyprsunset"
    "hyprlauncher"
    "hyprpolkitagent"
  ];

  hyprTools = hyprToolsWithConfig ++ [
    "hyprpicker"
    "hyprsysteminfo"
    "hyprshutdown"
    "hyprpwcenter"
  ];

  toolOptions = tool: {
    name = tool;
    value = {
      enable = lib.mkEnableOption "${tool}." // {
        default = false;
        defaultText = lib.literalExpression "false";
        description = "Enable ${tool}.";
      };
      package = lib.mkPackageOption pkgs tool {
        extraDescription = "The ${tool} package to use.";
      };
    }
    // lib.optionalAttrs (lib.elem tool hyprToolsWithConfig) {
      config = {
        raw = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          defaultText = lib.literalExpression "null";
          description = ''
            Inline / multi-line configuration that is written into the
            configuration file when no file is defined in `.config.file`.
          '';
          example = lib.literalExpression ''
            # https://wiki.hypr.land/hypr-ecosystem/user/hypridle/
            listener {
                timeout = 500                            # in seconds.
                on-timeout = notify-send "You are idle!" # command to run when timeout has passed.
                on-resume = notify-send "Welcome back!"  # command to run when activity is detected after timeout has fired.
            }
          '';
        };
        file = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          defaultText = lib.literalExpression "null";
          description = ''
            Path to a configuration file. When set, takes precedence over
            `.config.raw`.
          '';
          example = lib.literalExpression "./path/to/config.conf";
        };
      };
    };
  };

  mkConfigStorePath =
    name: toolCfg:
    if toolCfg.config.file != null then
      pkgs.runCommand "${name}-config" { } ''
        cp ${toolCfg.config.file} $out
      ''
    else if toolCfg.config.raw != null && toolCfg.config.raw != "" then
      pkgs.writeText "${name}.conf" toolCfg.config.raw
    else
      null;

  mkWrappedPackage =
    name: pkg: configPath:
    if configPath == null then
      pkg
    else
      pkgs.symlinkJoin {
        name = "${name}-with-config";
        paths = [ pkg ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/${name} \
            --add-flags "-c ${configPath}"
        '';
      };

  finalToolPackages = lib.mapAttrs (
    name: toolCfg:
    let
      basePkg = toolCfg.package;
      configPath = if lib.elem name hyprToolsWithConfig then mkConfigStorePath name toolCfg else null;
      shouldWrap = configPath != null && lib.elem name hyprToolsWithConfig;
    in
    if shouldWrap then mkWrappedPackage name basePkg configPath else basePkg
  ) cfg.tools;

  dmList = [
    "sddm"
    "ly"
    "lemurs"
  ];
  dmOptions = dmName: {
    name = dmName;
    value = {
      enable = lib.mkEnableOption "Enable the ${dmName} Display Manager.";
      package = lib.mkPackageOption pkgs (
        (lib.optional (dmName == "sddm") "kdePackages") ++ [ dmName ]
      ) { };
    }
    // lib.optionalAttrs (dmName == "sddm") {
      theme = {
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          defaultText = lib.literalExpression "null";
          description = ''
            The sddm theme to use. This applies at
            `services.displayManager.sddm.theme`.

            If you use `qylock`, leave this option empty.
          '';
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          defaultText = lib.literalExpression "[ ]";
          description = "A list of sddm theme packages to install them in your environment.";
        };
      };
    }
    // lib.optionalAttrs (dmName == "lemurs") {
      config = {
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          defaultText = lib.literalExpression "null";
          description = "Path to a single lemurs TOML file (not a directory).";
          example = lib.literalExpression "./lemurs.toml";
        };
        raw = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          defaultText = lib.literalExpression "null";
          description = "Inline TOML configuration for lemurs.";
          example = ''
            # General settings for background style
            [background]
            show_background = false
          '';
        };
        settings = lib.mkOption {
          inherit (tomlSettingsFormat) type;
          default = { };
          defaultText = lib.literalExpression "{ }";
          description = ''
            Configuration for lemurs, provided as a Nix attribute set and automatically
            serialized to TOML.
            See [lemurs configuration documentation](https://github.com/coastalwhite/lemurs/blob/main/extra/config.toml) for available options.
          '';
        };
      };
    };
  };

  lemursDefaults =
    let
      desktops = config.services.displayManager.sessionData.desktops;
    in
    {
      tty = 1;
      system_shell = "${pkgs.bash}/bin/bash";
      initial_path = "/run/current-system/sw/bin";
      x11 = {
        xauth_path = "${pkgs.xauth}/bin/xauth";
        xserver_path = "${pkgs.xorg-server}/bin/X";
        xsessions_path = "${desktops}/share/xsessions";
        xsetup_path = config.services.displayManager.sessionData.wrapper;
      };
      wayland.wayland_sessions_path = "${desktops}/share/wayland-sessions";
    };

  lemursSettings = lib.recursiveUpdate (lib.recursiveUpdate lemursDefaults config.services.displayManager.lemurs.settings) cfg.dm.lemurs.config.settings;

  lemursRawSet = cfg.dm.lemurs.config.raw != null && cfg.dm.lemurs.config.raw != "";
  lemursPathSet = cfg.dm.lemurs.config.path != null;
  lemursUserConfigSet = lemursRawSet || lemursPathSet;

  lemursPathOk =
    lemursPathSet
    && builtins.pathExists cfg.dm.lemurs.config.path
    && lib.filesystem.pathIsRegularFile cfg.dm.lemurs.config.path;

  lemursConfigStore =
    if lemursPathSet then
      pkgs.runCommand "lemurs-config.toml" { } ''
        cp ${lib.escapeShellArg (toString cfg.dm.lemurs.config.path)} $out
      ''
    else if lemursRawSet then
      pkgs.writeText "lemurs-config.toml" cfg.dm.lemurs.config.raw
    else
      tomlSettingsFormat.generate "lemurs-config.toml" lemursSettings;

  enabledDMs = lib.filter (m: cfg.dm.${m}.enable or false) dmList;

  hyprlandEntry = cfg.hyprland.config.entry;
  hyprlandPathSet = cfg.hyprland.config.path != null;
  hyprlandRawSet = cfg.hyprland.config.raw != null && cfg.hyprland.config.raw != "";
  hyprlandConfigSet = hyprlandPathSet || hyprlandRawSet;

  hyprlandConfigStore =
    let
      conf = cfg.hyprland.config;
    in
    if conf.path != null then
      pkgs.runCommand "hyprland-config" { } ''
        mkdir -p $out
        cp -a ${lib.escapeShellArg (toString conf.path)}/. $out/
        # Checks if entry `hyprland.lua` exists.
        if [ ! -f "$out/${hyprlandEntry}" ]; then
          echo "error: hyprnix.hyprland.config.path does not contain '${hyprlandEntry}'" >&2
          exit 1
        fi
      ''
    else if conf.raw != null && conf.raw != "" then
      pkgs.writeTextDir hyprlandEntry conf.raw
    else
      null;
  hyprlandExtraArgs = lib.optionals (hyprlandConfigStore != null) [
    "--config"
    "${hyprlandConfigStore}/${hyprlandEntry}"
  ];

  hyprnixSessionName = if cfg.uwsm.enable then "hyprnix-uwsm" else "hyprnix";

  hyprnixPlainSession = pkgs.writeTextFile {
    name = "hyprnix-session";
    destination = "/share/wayland-session/hyprnix.desktop";
    text = ''
      [Desktop Entry]
      Name=HyprNix
      Comment=Hyprland launched with the HyprNix configuration
      Exec=${lib.getExe' config.programs.hyprland.package "start-hyprland"} -- ${lib.escapeShellArg hyprlandExtraArgs}
      Type=Application
      DesktopNames=Hyprland
    '';
    derivationArgs.passthru.providedSessions = [ "hyprnix" ];
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "hyprnix" "portal" "enable" ]
      "`programs.hyprland` always enables xdg-desktop-portal-hyprland; only `hyprnix.portal.package` can be configured."
    )
  ];

  options.hyprnix = {
    enable = lib.mkEnableOption "HyprNix - Declarative configuration manager for Hyprland.";

    hyprland = {
      enable = lib.mkEnableOption "Hyprland (through `programs.hyprland`)." // {
        default = cfg.enable;
      };
      package = lib.mkPackageOption pkgs "hyprland" { };
      plugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        defaultText = lib.literalExpression "[ ]";
        description = "List of Hyprland plugins (pkgs.hyprlandPlugins.*)";
        example = lib.literalExpression "[ pkgs.hyprlandPlugins.hyprbars pkgs.hyprlandPlugins.hyprfocus ]";
      };
      config = {
        entry = lib.mkOption {
          type = lib.types.str;
          default = "hyprland.lua";
          defaultText = lib.literalExpression "hyprland.lua";
          description = ''
            If for some reason you want rename the entry file
            of your hyprland configuration.

            "hyprland.lua" by default, but you can named whatever
            you want.

            e.g: load, manager, yourmom, ...
          '';
        };
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          defaultText = lib.literalExpression "null";
          description = ''
            Path to a directory containing the Hyprland Lua configuration.
            The directory **must** contain a file named `hyprland.lua` (entry point).

            All files are copied recursively into the Nix store and Hyprland is
            started with '--config'. This registers an extra session called
            "HyprNix" (and selects it as default session), because the stock
            hyprland sessions do not pass '--config'.

            Mutually exclusive with `.config.raw`.
          '';
          example = lib.literalExpression ''
            # a directory with:
            # ./my-hyprland-config
            #   ./hyprland.lua
            #   ./another-config.lua
            #   ./scripts/...
            #   ./configs/...
            hyprnix.core.hyprland.config.path = ./my-hyprland-config;
          '';
        };
        raw = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          defaultText = lib.literalExpression "null";
          description = ''
            Inline content of `hyprland.lua`. Same session handling as `.config.path`.

            Mutually exclusive with `.config.path`.
          '';
          example = lib.literalExpression ''
            hl.config({
              general = {
                gaps_in = 5,
                gaps_out = 20,
              },
            })
          '';
        };
      };
    };
    uwsm = {
      enable = lib.mkEnableOption "launching Hyprland with the Universal Wayland Session Manager." // {
        default = cfg.enable;
      };
      package = lib.mkPackageOption pkgs "uwsm" { };
    };
    portal = {
      package = lib.mkPackageOption pkgs "xdg-desktop-portal-hyprland" { };
    };
    xwayland = {
      enable = lib.mkEnableOption "XWayland" // {
        default = cfg.enable;
      };
      package = lib.mkPackageOption pkgs "xwayland" { };
    };
    dm = lib.listToAttrs (lib.map dmOptions dmList);
    tools = lib.listToAttrs (lib.map toolOptions hyprTools);
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      defaultText = lib.literalExpression "[ ]";
      description = ''
        A list of extra packages needed for your hyprland environment,
        use it to install Qt6 or other modules.

        They are added to `environment.systemPackages`.
      '';
      example = lib.literalExpression "[ pkgs.hyprland-package ]";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = (lib.length enabledDMs) <= 1;
            message = ''
              hyprnix.dm: only one display manager may be enabled at a time.
              Currently enabled: ${lib.concatStringsSep ", " enabledDMs}
            '';
          }
          {
            assertion =
              !(cfg.dm.sddm.enable or false)
              || builtins.getEnv "XDG_STATE_HOME" != ""
              || builtins.getEnv "HOME" != "";
            message = "SDDM: at least one of `XDG_STATE_HOME` or `HOME` must be set.";
          }
          {
            assertion =
              !(config.programs.qylock.enable or false)
              || !(cfg.dm.sddm.enable or false)
              || (cfg.dm.sddm.theme.name == null);
            message = ''
              hyprnix: qylock and SDDM theme cannot be enabled at the same time.
              Disable hyprnix.dm.sddm.theme.name (or set it to null) or disable qylock / SDDM.
            '';
          }
        ]
        ++ (lib.concatLists (
          lib.mapAttrsToList (name: toolCfg: [
            {
              assertion =
                !(lib.elem name hyprToolsWithConfig)
                || (toolCfg.config.raw == null || toolCfg.config.raw == "")
                || toolCfg.config.file == null;
              message = "cfg.hyprnix.tools.${name}: 'raw' and 'file' are mutually exclusive.";
            }
          ]) (lib.attrsets.filterAttrs (name: _: lib.elem name hyprToolsWithConfig) cfg.tools)
        ))
        ++ lib.optionals cfg.hyprland.enable [
          {
            assertion = !(hyprlandPathSet && hyprlandRawSet);
            message = "hyprnix.hyprland.config: `path` and `raw` are mutually exclusive.";
          }
          {
            assertion =
              !hyprlandPathSet || builtins.pathExists (cfg.hyprland.config.path + "/${hyprlandEntry}");
            message = ''
              hyprnix.hyprland.config.path must be a directory containing `${hyprlandEntry}`.
              With flakes, make sure the files are tracked by git.
            '';
          }
        ]
        ++ lib.optionals cfg.dm.lemurs.enable [
          {
            assertion = !(lemursRawSet && lemursPathSet);
            message = "hyprnix.dm.lemurs.config: `path` and `raw` are mutually exclusive.";
          }
          {
            assertion = !lemursPathSet || lemursPathOk;
            message = "hyprnix.dm.lemurs.config.path must point to an existing regular TOML file.";
          }
          {
            assertion = lemursPathSet || lemursRawSet || (lemursSettings.tty or 1) == 1;
            message = ''
              hyprnix.dm.lemurs: `tty` must be 1 because the NixOS
              display-manager service is fixed to VT1.
            '';
          }
        ];

        warnings =
          lib.optional (!cfg.dm.lemurs.enable && lemursUserConfigSet) ''
            `hyprnix.dm.lemurs.config.{path,raw}` is set but `hyprnix.dm.lemurs.enable = false;`
            the configuration is ignored.
          ''
          ++ lib.optional (!cfg.hyprland.enable && hyprlandConfigSet) ''
            `hyprnix.hyprland.config.{path,raw}` is set but `hyprnix.hyprland.enable = false;`
            the configuration is ignored.
          '';
      }
      (lib.mkIf cfg.hyprland.enable (
        lib.mkMerge [
          {
            programs.hyprland = {
              enable = true;
              package = cfg.hyprland.package;
              portalPackage = cfg.portal.package;
              withUWSM = cfg.uwsm.enable;
              xwayland.enable = cfg.xwayland.enable;
            };
            programs.xwayland.package = lib.mkDefault cfg.xwayland.package;

            environment.systemPackages = cfg.hyprland.plugins;

            security.rtkit.enable = lib.mkDefault true;
          }

          (lib.mkIf cfg.uwsm.enable { programs.uwsm.package = cfg.uwsm.package; })
          (lib.mkIf hyprlandConfigSet (
            lib.mkMerge [
              { services.displayManager.defaultSession = lib.mkDefault hyprnixSessionName; }
              (lib.mkIf cfg.uwsm.enable {
                programs.uwsm.waylandCompositors.hyprnix = {
                  prettyName = "HyprNix";
                  comment = "Hyprland managed by UWSM, launched with the HyprNix configuration";
                  binPath = "/run/current-system/sw/bin/Hyprland";
                  extraArgs = hyprlandExtraArgs;
                };
              })
              (lib.mkIf (!cfg.uwsm.enable) {
                services.displayManager.sessionPackages = [ hyprnixPlainSession ];
              })
            ]
          ))
        ]
      ))
      (lib.mkIf cfg.tools.hyprlock.enable {
        security.pam.services.hyprlock = { };
      })
      (lib.mkIf cfg.dm.sddm.enable {
        services.displayManager.sddm = {
          enable = true;
          package = cfg.dm.sddm.package;
          theme = lib.mkIf (cfg.dm.sddm.theme.name != null) cfg.dm.sddm.theme.name;
          wayland.enable = lib.mkDefault true;
          settings = {
            Wayland.SessionLogFile = stateHome + "/sddm/wayland-session.log";
          };
        };
        environment.systemPackages = cfg.dm.sddm.theme.packages;
      })
      (lib.mkIf cfg.dm.ly.enable {
        services.displayManager.ly = {
          enable = true;
          package = cfg.dm.ly.package;
        };
      })
      (lib.mkIf cfg.dm.lemurs.enable {
        services.displayManager.lemurs = {
          enable = true;
          package = cfg.dm.lemurs.package;
        };
        services.displayManager.generic.execCmd = lib.mkForce "exec ${lib.getExe cfg.dm.lemurs.package} --config ${lemursConfigStore}";
      })
      {
        environment.systemPackages =
          cfg.extraPackages
          ++ lib.filter (p: p != null) (
            lib.mapAttrsToList (
              name: toolCfg: if toolCfg.enable then finalToolPackages.${name} else null
            ) cfg.tools
          );
      }
    ]
  );
}
