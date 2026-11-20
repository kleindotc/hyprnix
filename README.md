# HyprNix

Declarative NixOS module to configure Hyprland, including Hypr tools,
display managers and advanced customization options.

By: klein.

## Flake Install

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  nixpkgs-unstable.url = "github:nixos/nixpkgs-unstable";
  hyprnix.url = "git+https://codeberg.org/kleindotc/hyprnix";  # or your own fork.
};

outputs = { self, nixpkgs, nixpkgs-unstable, hyprnix, ... }: {
  nixosConfigurations.your-host = nixosSystem {
    modules = [
      ./configuration.nix
      hyprnix.nixosModules.hyprnix
      # an recommended overlay.
      {
        nixpkgs.overlays = [
          (_: prev: {
            unstable = import nixpkgs-unstable {
              inherit system;
              inherit (prev) config;
            };
          })
        ];
      }
    ];
  };
};
```

### Example config

```nix
{
  hyprnix = {
    enable = true;

    # Hyprland
    hyprland = {
      enable = true;
      # if for some reason you want rename the entry file.
      config.entry = "yourmom.lua";
      # path to a directory containing the Hyprland Lua Configuration.
      config.path = ./my-config;
      # Inline config of hyprland.
      # Mutually exclusive with `.config.path`.
      config.raw = ''
        hl.config({
          general = { gaps_in = 5, gaps_out = 20 }
        })
      '';
    };

    # Display Manager
    dm.lemurs.enable = true;

    # Hypr Tools
    tools.hyprlock.enable = true;
    tools.hypridle.enable = true;
    tools.hyprpicker.enable = true;
  };
}
```

---

License: AGPL-3.0-or-later.
