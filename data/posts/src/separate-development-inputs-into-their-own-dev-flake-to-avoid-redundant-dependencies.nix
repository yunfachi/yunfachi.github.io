{ slib, ... }:
{
  title = "Separate development inputs into their own `dev` flake to avoid redundant dependencies";
  date = "2026-08-20";
  content = ''
    First of all, this post is aimed at flakes that provide external outputs, like `nixosModules` or `packages` - your private NixOS configuration DOES NOT need this.

    For example, you have a project called `niri-nix`, which introduces Niri's NixOS module and Niri package. But besides nixpkgs, that flake's inputs also include `flake-parts`, `treefmt-nix`, `git-hooks.nix`, and so on. Nix flake inputs are NOT lazily fetched. This means that if you only use, for example, `nixosModules.default` from that flake, and `nixosModules.default` does not mention `treefmt-nix` or any of the other inputs at all, they will still be added to the user's flake lock as dependencies of your flake, and they will still be downloaded.

    > But how can you prevent some inputs from being redundantly and meaninglessly fetched?
    > Implement a separate flake for those inputs - I call it a `dev` flake. The idea is to keep development-only inputs outside of the flake that is consumed by users.

    There are 2 ways to set up a `dev` flake:

    1. Use the `dev` flake for both inputs and logic, while the main flake only needs to integrate the `dev` flake's outputs into itself.
    2. Use the `dev` flake only for inputs, while the logic stays in the main flake.

    Both of these methods will be discussed. But to quickly answer which is the better option: if your `dev` logic is huge, then choose the first option; otherwise, you are good to go with the second one.

    Let's begin with the first option. First, initialize the `dev` flake in the `dev/` directory:

    ${slib.highlightCode "nix" ''
      # dev/flake.nix
      {
        inputs = {
          # By this "hack", you can access your root flake's inputs to deduplicate them
          # in the `dev` flake too. It only works in a git repository.
          # my-project.url = "path:../.";
          # nixpkgs.follows = "my-project/nixpkgs";

          # Nixpkgs is required for flake-parts `perSystem` to work.
          nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

          # Remove this if flake-parts is already used in your root flake
          # or if you want to implement the mechanism yourself.
          flake-parts = {
            url = "github:hercules-ci/flake-parts";
            # inputs.nixpkgs-lib.follows = "nixpkgs";
          };

          # Add any inputs that you want here; `treefmt-nix` is used as an example.
          treefmt-nix = {
            url = "github:numtide/treefmt-nix";
            # inputs.nixpkgs.follows = "nixpkgs";
          };
        };

        # Logic will be written in a separate file.
        outputs = _: { };
      }
    ''}

    Then generate the lock file by running this command in the `dev/` directory: `${slib.highlightCode "sh" "nix flake lock"}`.

    > Can I do this without flake-parts?
    > Yes, but you'll need to implement your own mechanism for separating the `dev` flake's logic into another file. This can be a bit tricky. You may want to consider the second option below instead.

    Now we'll create a ${slib.anchorNewTab "https://github.com/hercules-ci/flake-parts" "flake-parts"} module in it. Don't worry, flake-parts is not required in your root flake:

    ${slib.highlightCode "nix" ''
      # dev/config.nix
      # The content of this file is just an example. You can write anything you want here:
      # https://flake.parts/options/flake-parts.html
      { inputs, ... }: {
        systems = [ "x86_64-linux" ];

        imports = [ inputs.treefmt-nix.flakeModule ];

        perSystem = _: {
          # https://flake.parts/options/treefmt-nix.html
          treefmt = {
            projectRootFile = "flake.nix";

            programs = {
              nixfmt.enable = true;
              deadnix.enable = true;
            };
          };
        };
      }
    ''}

    Finally, you have to export the `dev` outputs to your root flake.
    If you already use `flake-parts` in your root flake, you should use its ${slib.anchorNewTab "https://flake.parts/options/flake-parts-partitions.html" "partitions feature"} instead.
    Otherwise, to avoid adding flake-parts to the root flake's dependencies, write this:

    ${slib.highlightCode "nix" ''
      # flake.nix
      {
        inputs = {
          # You may remove this; read the comments below.
          flake-compat.url = "github:NixOS/flake-compat";

          # ...
        };

        outputs = { flake-compat, self, ... }: let
          # If you have `flake-compat` in your inputs, keep this:
          devFlake = (import flake-compat { src = ./dev; }).defaultNix;

          # But if you don't want `flake-compat` itself to become a dependency of your users, you can fetch the pinned flake-compat implementation directly:
          # devFlake =
          #   (import (builtins.fetchurl {
          #     url = "https://raw.githubusercontent.com/NixOS/flake-compat/f275e157c50c3a9a682b4c9b4aa4db7a4cd3b5f2/default.nix";
          #     sha256 = "sha256:0nycwx0777d451k63ghp6p5lcv791kziqgkvqzmr1qwzywkdk1cj";
          #   }) { src = ./dev; }).defaultNix;

          devOutputs = devFlake.inputs.flake-parts.lib.mkFlake {
            inputs = devFlake.inputs // {
              my-project = self;
              self = devFlake;
            };
          } ./dev/config.nix;
        in {
          # Explicitly inherit outputs to prevent forcing evaluation of the `dev` flake
          # when accessing root flake outputs.
          inherit (devOutputs) checks formatter;

          # Some output that is free from fetching `dev` inputs.
          # nixosModules.default = ...;
        };
      }
    ''}

    Harder than just having `treefmt-nix` in the root flake's inputs? Yes. But better for users? Absolutely.

    This approach is also used in the following projects:

    - ${slib.styledAnchor "https://github.com/unnamed-systems/nix-secrets"} (without flake-parts in the root flake)
    - ${slib.styledAnchor "https://github.com/NixOS/flake-compat"} (without flake-parts in the root flake)
    - ${slib.styledAnchor "https://github.com/hercules-ci/flake-parts"} (with flake-parts in the root flake)

    ---

    Now, let's discuss the second option. First, you need to initialize the `dev` flake:

    ${slib.highlightCode "nix" ''
      # dev/flake.nix
      {
        inputs = {
          # By this "hack", you can access your root flake and its inputs to
          # deduplicate them in the `dev` flake too. It only works in a git repository.
          # my-project.url = "path:../.";
          # nixpkgs.follows = "my-project/nixpkgs";

          # Add any inputs that you want here; `treefmt-nix` is used as an example.
          treefmt-nix = {
            url = "github:numtide/treefmt-nix";
            # inputs.nixpkgs.follows = "nixpkgs";
          };
        };

        # This flake is only for inputs; there is no logic here.
        outputs = _: { };
      }
    ''}

    Then generate the lock file by running this command in the `dev/` directory: `${slib.highlightCode "sh" "nix flake lock"}`.

    And, finally, you have to access the `dev` inputs from the root flake:

    ${slib.highlightCode "nix" ''
      # flake.nix
      {
        inputs = {
          # You may remove this; read the comments below.
          flake-compat.url = "github:NixOS/flake-compat";

          # ...
        };

        outputs = { flake-compat, ... }: let
          # If you have `flake-compat` in your inputs, keep this:
          devInputs = (import flake-compat { src = ./dev; }).defaultNix.inputs;

          # But if you don't want `flake-compat` itself to become a dependency of your users, you can fetch the pinned flake-compat implementation directly:
          # devInputs =
          #   (import (builtins.fetchurl {
          #     url = "https://raw.githubusercontent.com/NixOS/flake-compat/f275e157c50c3a9a682b4c9b4aa4db7a4cd3b5f2/default.nix";
          #     sha256 = "sha256:0nycwx0777d451k63ghp6p5lcv791kziqgkvqzmr1qwzywkdk1cj";
          #   }) { src = ./dev; }).defaultNix.inputs;
        in {
          # Some output that is free from fetching `dev` inputs.
          # nixosModules.default = ...;

          # Actually, read the `treefmt-nix` manual for the proper setup of it; this post is not about how to use `treefmt-nix`.
          formatter = devInputs.treefmt-nix.formatter;
        };
      }
    ''}
  '';
}
