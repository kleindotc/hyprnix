{
  description = "HyprNix - A declarative NixOS module to configure Hyprland, including Hypr tools, display managers and advanced customization options.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, ... }@inputs:
    {
      nixosModules = {
        default = self.nixosModules.hyprnix;
        hyprnix = import ./module.nix { };
      };

      formatter = builtins.mapAttrs (_: pkgs: pkgs.nixfmt) inputs.nixpkgs.legacyPackages;
    };
}
