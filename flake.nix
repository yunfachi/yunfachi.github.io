{
  description = "My personal website, built with Nix and no JavaSlop";

  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { nixpkgs, self, ... }:
    let
      inherit (nixpkgs) lib;

      systems = lib.systems.flakeExposed;

      eachSystem = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = eachSystem (
        system: pkgs: {
          default = self.packages.${system}.site;
          site = import ./default.nix {
            inherit system pkgs lib;
            flake = self;
          };
        }
      );
    };
}
