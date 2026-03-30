{
  description = "Nix User Repository";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      manifest = (builtins.fromJSON (builtins.readFile ./repos.json)).repos;
      overlay = final: prev: {
        nur = import ./default.nix {
          nurpkgs = prev;
          pkgs = prev;
        };
      };

      lockedRevisions = (builtins.fromJSON (builtins.readFile ./repos.json.lock)).repos;
      repoSource =
        name: attr:
        import ./lib/repoSource.nix {
          inherit
            name
            attr
            manifest
            lockedRevisions
            lib
            ;
          fetchgit = builtins.fetchGit or lib.id;
          fetchzip = builtins.fetchTarball or lib.id;
        };
      # Lazily evaluate each repo with pkgs = null; the result is only forced
      # when a specific repo's attribute is accessed.
      repos = lib.mapAttrs (
        name: attr:
        import ./lib/evalRepo.nix {
          inherit name lib;
          inherit (attr) url;
          src = repoSource name attr + ("/" + (attr.file or ""));
          pkgs = null;
        }
      ) manifest;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = builtins.filter (
        system: builtins.hasAttr system nixpkgs.legacyPackages
      ) nixpkgs.lib.platforms.all;
      flake = {
        overlays = {
          default = overlay;
        };
        modules = lib.genAttrs [ "nixos" "homeManager" "darwin" ] (_: {
          default = {
            nixpkgs.overlays = [ overlay ];
          };
        });
        repos = lib.mapAttrs (
          name: _:
          let
            r = repos.${name};
          in
          {
            modules = {
              nixos = r.nixosModules or r.modules or { };
              homeManager = r.homeModules or { };
              darwin = r.darwinModules or { };
              flake = r.flakeModules or { };
            };
            overlays = r.overlays or { };
          }
        ) manifest;
      };
      imports = [
        inputs.flake-parts.flakeModules.modules
      ];
      perSystem =
        { pkgs, ... }:
        {
          formatter = pkgs.treefmt.withConfig {
            runtimeInputs = with pkgs; [
              nixfmt-rfc-style
            ];

            settings = {
              on-unmatched = "info";
              tree-root-file = "flake.nix";

              formatter = {
                nixfmt = {
                  command = "nixfmt";
                  includes = [ "*.nix" ];
                };
              };
            };
          };
          # legacyPackages is used because nur is a package set
          # This trick with the overlay is used because it allows NUR packages to depend on other NUR packages
          legacyPackages = (pkgs.extend overlay).nur;
        };
    };
}
