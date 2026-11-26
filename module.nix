{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.hyprnix;
  tomlSettingsFormat = pkgs.formats.toml { };

  hyprToolsWithConfig = [
    "hyprlock"
    "hypridle"
    "hyprpaper"
    "hyprsunset"
    "hyprlauncher"
    "hyprtoolkit"
    "hyprpolkitagent"
    "hyprland-qt-support"
    "hyprqt6engine"
  ];

  hyprTools = hyprToolsWithConfig ++ [
    "hyprshot"
    "hyprpicker"
    "hyprcursor"
    "hyprsysteminfo"
    "hyprshutdown"
    "hyprpwcenter"
  ];

  dmList = [
    "sddm"
    "ly"
    "lemurs"
  ];

  configSourceAssertions =
    {
      prefix,
      file,
      raw,
      settings ? null,
      settingsSet ? (settings != null),
      ...
    }:
    [
      {
        assertion =
          lib.count (x: x) [
            (file != null)
            (raw != null)
            settingsSet
          ] <= 1;
        message = ''
          ${prefix}:
          configuration sources are mutually exclusive.
          Choose at most one of: file, raw, settings.
        '';
      }
      {
        assertion = file == null || lib.filesystem.pathIsRegularFile file;
        message = ''
          ${prefix}.file must point to an existing regular file.
        '';
      }
    ];

  hasConfigSource =
    {
      file,
      raw,
      settings ? null,
      settingsSet ? (settings != null),
      ...
    }:
    file != null || raw != null || settingsSet;

  mkConfigSource =
    {
      name,
      file ? null,
      raw ? null,
      settings ? null,
      settingsSet ? (settings != null),
      ...
    }:
    if file != null then
      builtins.path {
        path = file;
        inherit name;
      }
    else if raw != null then
      pkgs.writeText name raw
    else if settingsSet then
      tomlSettingsFormat.generate name settings
    else
      null;

  mkEnableFollowingMain =
    description:
    lib.mkEnableOption description
    // {
      default = cfg.enable;
      defaultText = lib.literalExpression "hyprnix.enable";
    };

  mkToolOption =
    name:
    lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "${name}." // {
            default = false;
            defaultText = lib.literalExpression "false";
          };
          package = lib.mkPackageOption pkgs name { };
        }
        // lib.optionalAttrs (lib.elem name hyprToolsWithConfig) {
          config = lib.mkOption {
            type = lib.types.submodule {
              options = {
                raw = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Inline Configuration content.";
                };
                file = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Path to an existing configuration file.";
                };
              };
            };
            default = { };
            description = "Configuration for ${name}.";
          };
        };
      };
      default = { };
      description = "Options for ${name}.";
    };

  mkDmOption =
    name:
    lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption name // {
            default = false;
            defaultText = lib.literalExpression "false";
          };
          package = lib.mkPackageOption pkgs (lib.optional (name == "sddm") "kdePackages" ++ [ name ]) { };
        }
        // lib.optionalAttrs (name == "sddm") {
          theme = lib.mkOption {
            type = lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = ''
                    sddm theme to use.

                    This applies at `services.displayManager.sddm.theme`.
                    If you use `qylock`, leave this option empty.
                  '';
                };
                packages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                  defaultText = lib.literalExpression "[ ]";
                  description = "A list of sddm packages to install them in your environment.";
                };
              };
            };
            default = { };
            defaultText = lib.literalExpression "{ }";
            description = "Theme Configuration for ${name}.";
          };
        }
        // lib.optionalAttrs (name == "lemurs") {
          config = lib.mkOption {
            type = lib.types.submodule {
              options = {
                file = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Path to a single lemurs TOML file.";
                  example = lib.literalExpression "./lemurs.toml";
                };
                raw = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Inline TOML configuration for lemurs.";
                  example = ''
                    # ...
                    [background]
                    show_background = false
                  '';
                };
                settings = lib.mkOption {
                  inherit (tomlSettingsFormat) type;
                  default = { };
                  defaultText = lib.literalExpression "{ }";
                  description = ''
                    Configuration for lemurs, provided as a Nix
                    attribute set and automatically serialized to TOML.

                    see [lemurs configuration docs](https://github.com/coastalwhite/lemurs/blob/main/extra/config.toml) for available options.
                  '';
                };
              };
            };
            default = { };
            defaultText = lib.literalExpression "{ }";
            description = "";
          };
          variables = lib.mkOption {
            type = lib.types.submodule {
              options = {
                file = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Path to a lemurs variables TOML configuration.";
                };
                raw = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  defaultText = lib.literalExpression "null";
                  description = "Inline lemurs variables TOML configuration.";
                };
                settings = lib.mkOption {
                  inherit (tomlSettingsFormat) type;
                  default = { };
                  defaultText = lib.literalExpression "{ }";
                  description = "Variables configuration for lemurs, serialized automatically to TOML.";
                };
              };
            };
            default = { };
            defaultText = lib.literalExpression "{ }";
            description = "Variables configuration for lemurs.";
          };
        };
      };
    };

  tools = lib.genAttrs hyprTools (name: cfg.tools.${name});
  toolsWithConfig = lib.genAttrs hyprToolsWithConfig (name: cfg.tools.${name});
  enabledTools = lib.filterAttrs (_: tool: tool.enable) tools;

  toolConfigAssertions = lib.concatLists (
    lib.mapAttrsToList (
      name: tool:
      lib.optionals tool.enable (configSourceAssertions {
        prefix = "hyprnix.tools.${name}.config";
        inherit (tool.config) file raw;
      })
    ) toolsWithConfig
  );

  toolConfigSources = lib.filterAttrs (_: source: source != null) (
    lib.mapAttrs (
      name: tool:
      mkConfigSource {
        name = "${name}.conf";
        inherit (tool.config) file raw;
      }
    ) (lib.filterAttrs (_: tool: tool.enable) toolsWithConfig)
  );

  hyprnixTools =
    if toolConfigSources == { } then
      null
    else
      pkgs.runCommand "hyprnix-tools" { } ''
        mkdir -p "$out"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: source: "install -m 0444 ${source} \"$out/${name}.conf\""
          ) toolConfigSources
        )}
      '';

  mkWrappedPackage =
    name: tool:
    let
      pkg = tool.package;
      exe = pkg.meta.mainProgram or name;
    in
    if !(toolConfigSources ? ${name}) then
      pkg
    else
      pkgs.symlinkJoin {
        name = "${name}-with-config";
        paths = [ pkg ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta = pkg.meta or { };
        postBuild = ''
          set -eu
          if [ ! -x "$out/bin/${exe}" ]; then
            echo "error; expected executable ${exe} was not found in ${pkg}" >&2
            exit 1
          fi

          wrapProgram "$out/bin/${exe}" \
            --add-flags ${lib.escapeShellArg "-c ${hyprnixTools}/${name}.conf"}
        '';
      };

  enabledToolPackages = lib.mapAttrsToList mkWrappedPackage enabledTools;
  enabledPluginPackages = lib.optionals (
    cfg.hyprland.plugins.enable && cfg.hyprland.plugins.packages != null
  ) cfg.hyprland.plugins.packages;
  enabledDMs = lib.filter (m: cfg.dm.${m}.enable) dmList;

  lemurs = cfg.dm.lemurs;
  lemursConfig = lemurs.config;
  lemursVariables = lemurs.variables;

  mkLemursSource = name: source: {
    inherit name;
    inherit (source) file raw settings;
    settingsSet = source.settings != { };
  };

  lemursConfigSource = mkLemursSource "lemurs-config.toml" lemursConfig;
  lemursVariablesSource = mkLemursSource "lemurs-variables.toml" lemursVariables;

  lemursConfigStore = mkConfigSource lemursConfigSource;
  lemursVariablesStore = mkConfigSource lemursVariablesSource;

  lemursCustomConfig = hasConfigSource lemursConfigSource || hasConfigSource lemursVariablesSource;

  lemursCommandArgs = [
    (lib.getExe lemurs.package)
  ]
  ++ lib.optionals (lemursConfigStore != null) [
    "--config"
    (toString lemursConfigStore)
  ]
  ++ lib.optionals (lemursVariablesStore != null) [
    "--variables"
    (toString lemursVariablesStore)
  ];

  lemursExecCmd = lib.escapeShellArgs ([ "exec" ] ++ lemursCommandArgs);

  lemursAssertions =
    configSourceAssertions ({ prefix = "hyprnix.dm.lemurs.config"; } // lemursConfigSource)
    ++ configSourceAssertions ({ prefix = "hyprnix.dm.lemurs.variables"; } // lemursVariablesSource)
    ++ [
      {
        assertion = !lemursConfigSource.settingsSet || ((lemursConfig.settings.tty or 1) == 1);
        message = ''
          hyprnix.dm.lemurs: `tty` must be 1 because
          the NixOS display-manager service is fixed to VT1.
        '';
      }
    ];

  hyprlandConfig = cfg.hyprland.config;
  hyprlandEntry = hyprlandConfig.entry;
  hyprlandPathSet = hyprlandConfig.path != null;
  hyprlandRawSet = hyprlandConfig.raw != null && hyprlandConfig.raw != "";
  hyprlandConfigSet = hyprlandPathSet || hyprlandRawSet;

  hyprlandConfigStore =
    if hyprlandPathSet then
      pkgs.runCommand "hyprland-config" { } ''
        mkdir -p "$out"
        cp -a ${lib.escapeShellArg "${hyprlandConfig.path}"}/. "$out/"
        # Checks if entry `hyprland.lua` exists
        if [ ! -f "$out"/${lib.escapeShellArg hyprlandEntry} ]; then
          echo "error: invalid hyprland entry" >&2
          exit 1
        fi
      ''
    else if hyprlandRawSet then
      pkgs.writeTextDir hyprlandEntry hyprlandConfig.raw
    else
      null;

  hyprlandExtraArgs = lib.optionals (hyprlandConfigStore != null) [
    "--config"
    "${hyprlandConfigStore}/${hyprlandEntry}"
  ];

  hyprnixSessionLauncher = pkgs.writeShellScript "hyprnix-session-launcher" ''
    exec /run/current-system/sw/bin/start-hyprland -- ${lib.escapeShellArgs hyprlandExtraArgs}
  '';

  hyprnixSessionName = if cfg.uwsm.enable then "hyprnix-uwsm" else "hyprnix";

  hyprnixPlainSession = pkgs.writeTextFile {
    name = "hyprnix-session";
    destination = "/share/wayland-sessions/hyprnix.desktop";
    text = ''
      [Desktop Entry]
      Name=HyprNix
      Comment=Hyprland launched with the HyprNix configuration
      Exec=${hyprnixSessionLauncher}
      Type=Application
      DesktopNames=Hyprland
    '';
    derivationArgs.passthru.providedSessions = [ "hyprnix" ];
  };

  hyprlandPlugins =
    if enabledPluginPackages != [ ] then
      pkgs.symlinkJoin {
        name = "hyprland-plugins";
        paths = enabledPluginPackages;
      }
    else
      null;

  hyprnixPackages =
    lib.optional (hyprlandPlugins != null) hyprlandPlugins
    ++ enabledToolPackages
    ++ (if cfg.dm.sddm.enable then cfg.dm.sddm.theme.packages else [ ])
    ++ cfg.extraPackages;

  moduleAssertions = [
    {
      assertion = !hyprlandPathSet || lib.filesystem.pathIsDirectory hyprlandConfig.path;
      message = ''
        hyprnix.hyprland.config.path must point to a directory.
      '';
    }
    {
      assertion = !(hyprlandPathSet && hyprlandRawSet);
      message = "hyprnix.hyprland.config: `path` and `raw` are mutually exclusive.";
    }
    {
      assertion = (lib.length enabledDMs) <= 1;
      message = ''
        hyprnix.dm: only one display manager may be enabled at a time.
        Currently enabled: ${lib.concatStringsSep ", " enabledDMs}
      '';
    }
    {
      assertion =
        !(config.programs.qylock.enable or false)
        || !cfg.dm.sddm.enable
        || (cfg.dm.sddm.theme.name == null);
      message = ''
        hyprnix: qylock and SDDM theme cannot be enabled at the same time.
        Disable hyprnix.dm.sddm.theme.name (or set it to null) or disable qylock / SDDM.
      '';
    }
  ]
  ++ toolConfigAssertions
  ++ lemursAssertions;

  moduleWarnings =
    lib.optional (!lemurs.enable && lemursCustomConfig) ''
      hyprnix.dm.lemurs configuration is set but the Lemurs display manager
      is disabled. The configuration will be ignored.
    ''
    ++ lib.optional (!cfg.hyprland.enable && hyprlandConfigSet) ''
      hyprnix.hyprland configuration is set but Hyprland is disabled.
      The configuration will be ignored.
    '';
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
      enable = mkEnableFollowingMain "Hyprland (through `programs.hyprland`).";
      package = lib.mkPackageOption pkgs "hyprland" { };
      plugins = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable Hyprland Plugins.";
            packages = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.package);
              default = null;
              defaultText = lib.literalExpression "null";
              description = ''
                List of Hyprland plugins to install.

                You can mix packages from `pkgs.hyprlandPlugins.*` (nixpkgs)
                and packages coming from the official flake
                `github:hyprwm/hyprland-plugins`.

                **Recommended way to use the official plugins flake**
                (do **not** add `hyprland-plugins` as an input of this module):

                In *your* flake.nix:

                ```
                inputs = {
                  # ...
                  hyprland.url = "github:hyprwm/Hyprland"; # or the one you already use
                  hyprland-plugins = {
                    url = "github:hyprwm/hyprland-plugins";
                    inputs.hyprland.follows = "hyprland";
                  };
                };
                ```

                Then in your configuration:

                ```
                hyprnix.hyprland.plugins = {
                  enable = true;
                  packages = with inputs.hyprland-plugins.packages.''${pkgs.stdenv.hostPlatform.system}; [
                    hyprbars
                    hyprexpo
                    # ...
                  ];
                };
                ```

                The module will create a `symlinkJoin` and set `HYPR_PLUGIN_DIR`
                automatically.
              '';
              example = lib.literalExpression ''
                [ pkgs.hyprlandPlugins.hyprbars ]
                # or with the official flake (see description)
              '';
            };
          };
        };
        default = { };
        defaultText = lib.literalExpression "{ }";
        description = "Hyprland plugins";
      };
      config = {
        entry = lib.mkOption {
          type = lib.types.addCheck lib.types.str (
            e:
            e != ""
            && !(lib.hasPrefix "/" e)
            && !(lib.elem ".." (lib.splitString "/" e))
            && !(lib.hasInfix "\\" e)
            && !(lib.hasInfix "\n" e)
            && !(lib.hasInfix "\r" e)
            && !(lib.hasInfix "\t" e)
          );
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
            hyprnix.hyprland.config.path = ./my-hyprland-config;
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
      enable = mkEnableFollowingMain "launching Hyprland with the Universal Wayland Session Manager.";
      package = lib.mkPackageOption pkgs "uwsm" { };
    };
    portal = {
      package = lib.mkPackageOption pkgs "xdg-desktop-portal-hyprland" { };
    };
    xwayland = {
      enable = mkEnableFollowingMain "XWayland";
      package = lib.mkPackageOption pkgs "xwayland" { };
    };
    dm = lib.mkOption {
      type = lib.types.submodule { options = lib.genAttrs dmList mkDmOption; };
      default = lib.genAttrs dmList (_: { });
      defaultText = lib.literalExpression ''
        lib.genAttrs dmList (_: { })
      '';
      description = "Display Manager options.";
    };
    tools = lib.mkOption {
      type = lib.types.submodule { options = lib.genAttrs hyprTools mkToolOption; };
      default = lib.genAttrs hyprTools (_: { });
      defaultText = lib.literalExpression ''
        lib.genAttrs hyprTools (_: { })
      '';
      description = "Hyprland ecosystem tools.";
    };
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
        assertions = moduleAssertions;
        warnings = moduleWarnings;
        environment.systemPackages = hyprnixPackages;
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

            security.rtkit.enable = lib.mkDefault true;
          }
          (lib.mkIf (cfg.hyprland.plugins.enable && hyprlandPlugins != null) {
            environment.sessionVariables = {
              HYPR_PLUGIN_DIR = "${hyprlandPlugins}";
            };
          })
          (lib.mkIf cfg.uwsm.enable (
            lib.mkMerge [
              { programs.uwsm.package = cfg.uwsm.package; }
              (lib.mkIf hyprlandConfigSet {
                programs.uwsm.waylandCompositors.hyprnix = {
                  prettyName = "HyprNix";
                  comment = "Hyprland managed by UWSM, launched with the HyprNix configuration";
                  binPath = hyprnixSessionLauncher;
                };
              })
            ]
          ))
          (lib.mkIf hyprlandConfigSet (
            lib.mkMerge [
              { services.displayManager.defaultSession = lib.mkDefault hyprnixSessionName; }
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
        };
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
          settings = cfg.dm.lemurs.config.settings;
        };
        services.displayManager.generic.execCmd = lib.mkIf lemursCustomConfig (lib.mkForce lemursExecCmd);
      })
    ]
  );
}
