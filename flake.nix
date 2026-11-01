{
  description = "HyprNix";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs-unstable";
    qylock = {
      url = "github:Darkkal44/qylock";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      qylock,
      ...
    }:
    {
      nixosModules = {
        default = self.nixosModules.hyprnix;
        hyprnix = import ./module.nix {
          inherit qylock;
        };
      };
    };
}
