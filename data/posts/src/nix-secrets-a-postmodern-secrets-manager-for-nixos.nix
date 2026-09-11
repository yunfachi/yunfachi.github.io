{ slib, ... }:
{
  title = "nix-secrets - a postmodern secrets manager for NixOS";
  date = "2026-08-08";
  content = ''
    In this post, I'll quickly show you how to use the project ${slib.anchorNewTab "https://github.com/unnamed-systems/nix-secrets" "nix-secrets"} and explain its advantages over other secrets management solutions for Nix(OS), such as sops-nix, agenix, agenix-rekey, and vaultix.

    First of all, nix-secrets is a NixOS module with its own CLI written in Rust (the first advantage - no blazingly fast Bash!) that lets you safely use secrets in your configuration without leaking them.

    > How does it work?
    > You define the configuration for your secrets ONLY in your NixOS configuration (the second advantage - no need for a ".sops.yaml" file or standalone Nix expressions outside your configuration, as with agenix). Then, you open an editor for the secret using our CLI. It encrypts the secret using ${slib.anchorNewTab "https://age-encryption.org/" "age"} and stores it in the directory you specify - we call this the "storage". Finally, nix-secrets decrypts and mounts the secret at the path specified in the configuration. It supports both activation scripts and systemd services when `userborn` or `systemd.sysusers` is used (the third advantage - vaultix doesn't support activation scripts, so you can't use it without `userborn` or `systemd.sysusers`).

    Advantages:

    - Configure secrets entirely in your NixOS configuration - no YAML files or standalone Nix expressions.
    - A CLI and activation mechanism written in Rust with atomic operations - no more slow Bash scripts.
    - Support for templates, placeholders (a feature that lets your CI use placeholders instead of real secrets), and generators.
    - Support for both systemd service activation and activation scripts.

    To start using it, you need to add it to your flake inputs (sorry, there is no non-flake support at the moment, but it's planned for the future):

    ${slib.highlightCode "nix" ''
      # flake.nix
      {
        inputs = {
          nix-secrets.url = "github:unnamed-systems/nix-secrets";
          # nix-secrets.inputs.nixpkgs.follows = "nixpkgs";
        };
      }
    ''}

    Then, you need to import `inputs.nix-secrets.nixosModules.default` into your NixOS configuration. There are several ways to do this: you can add it to the `modules` argument of the `nixosSystem` function, or pass `inputs` through the `specialArgs` argument of `nixosSystem` and then import it in your configuration:

    ${slib.highlightCode "nix" ''
      # configuration.nix
      { inputs, ... }: {
        imports = [ inputs.nix-secrets.nixosModules.default ];
      }
    ''}

    After importing it, you need to enable nix-secrets and configure it. Here's a simple example:

    ${slib.highlightCode "nix" ''
      # configuration.nix
      {
        security.nix-secrets = {
          enable = true;

          storage = ./storage; # You need to create a directory named "storage". If you use Git, don't forget to add a ".gitkeep" file to it.
          # storagePath = "/etc/nixos/storage"; # An absolute path where your storage is located, instead of specifying it manually via the `--storage` argument.

          identityPaths = [
            "/home/<user>/.config/nix-secrets/keys.txt" # You need to create this file by creating the directory `/home/<user>/.config/nix-secrets` and running `nix run github:unnamed-systems/nix-secrets#default -- keygen -o /home/<user>/.config/nix-secrets/keys.txt`.
          ];

          recipientAliases = {
            pc = "age17ctd...usq"; # Paste the value of "Public key" from the output of the command you used to generate the identity file.
            laptop = "age1m2...06s";

            desktops = [ "pc" "laptop" ]; # You can reference aliases too.
          };
          defaultRecipients = [ "desktops" ]; # Add "desktops" to each secret's recipients by default.
        };
      }
    ''}

    At this point, you can rebuild your system to install the `nix-secrets` CLI before continuing.

    Then, you need to define your first secret - for example, a user's password hash (it is more secure not to publish your password hashes):

    ${slib.highlightCode "nix" ''
      # configuration.nix
      { config, ... }: {
        security.nix-secrets.secrets."user/passwordHash" = {
          neededForUsers = true; # This is required because the secret is used to create users. Otherwise, you generally don't need it.
          # owner = "root"; # Default value; can't be anything other than "root" when `neededForUsers = true`.
          # group = "root"; # Default value; can't be anything other than "root" when `neededForUsers = true`.
          # mode = "0400"; # Default value; octal representation of Linux file permissions.
        };

        # nix-secrets will automatically mount the secret's content at its `path` option.
        # You can override the value of `path` if needed.
        users.users.myUser.hashedPasswordFile = config.security.nix-secrets.secrets."user/passwordHash".path;
      }
    ''}

    Once you've added the secret to your configuration, you need to edit its value using the nix-secrets CLI:

    ${slib.highlightCode "sh" ''
      nix-secrets --flake .#myHostName edit user/passwordHash
    ''}

    Don't forget to add the `--storage /path/to/storage` parameter if you haven't configured the `storagePath` option in your configuration (don't confuse it with the `storage` option).

    Then, during a rebuild or at boot, nix-secrets will decrypt the secrets from storage and mount them at their configured paths.

    You can read the full documentation at ${slib.anchorNewTab "https://github.com/unnamed-systems/nix-secrets/tree/master/docs" "github:unnamed-systems/nix-secrets?path=docs"}.
  '';
}
