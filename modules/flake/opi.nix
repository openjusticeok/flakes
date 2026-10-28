# flake-parts module for opi project shells.
#
# Usage (in a flake that imports `<opi>.flakeModules.default`):
#
#   perSystem = { pkgs, ... }: {
#     opi.shells.default = {
#       bundles = [ "geo" ];
#       rPackages = [ "sf" "tidycensus" "tigris" ];
#       packages = [ pkgs.jq ];
#       env.R_MAX_VSIZE = "32Gb";
#     };
#   };
#
# Each `opi.shells.<name>` entry materializes as devShells.<name>: the org
# environment (lib/baseEnvironment.nix) + bundles (in listed order) + the shell's
# own rPackages/packages/env/shellHook. There is no base-shell option to point
# at: lib/mkOpiShell.nix is the only composition path, so every opi shell —
# including the repo's own base shell and the `<pkg>-dev` shells — is built the
# same way.
#
# Because these are typed flake-parts options, multiple imported modules can
# contribute to the same shell or bundle (packages append, env merges
# recursively) without any single call site owning it.
#
#   - Adjacent shells: separate `opi.shells` entries for independent kinds of
#     work; each is the org environment + its own opts.
#   - Bundled shells: shared bundles defined as `opi.bundles.<name>` and
#     referenced by one or more shells via `bundles = [ ... ]`.
#
# The module also owns the package set: it instantiates nixpkgs once with opi's
# version-of-record overlay, so `packages` and `rPackages` in a project always
# come from the same set. Names in `rPackages` resolve against it (CRAN spelling,
# dots map to underscores), so a project can name org packages as well as public
# ones and gets the derivations every opi shell ships.
{
  flake-parts-lib,
  inputs,
  lib,
  ...
}: let
  # The opi flake, when we are imported as `flakeModules.default` from a
  # consumer. In this repo's own flake there is no `opi` input, so the same
  # overlay is assembled from our own inputs — one file either way.
  opi = inputs.opi or null;

  versionOfRecord =
    if opi != null
    then opi.overlays.default
    else import ../../overlays {inherit inputs;};

  mkOpiShell = import ../../lib/mkOpiShell.nix;
in {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }: let
      # Predefined bundles shipped with opi (shells/bundles/), exposed as
      # opi.bundles defaults. Their env values are mkDefault in that file, so a
      # project can override them without a conflicting definition.
      shippedBundles = import ../../shells/bundles {inherit pkgs lib;};

      # The fields a bundle and a shell share. Defined once: a shell is this plus
      # a name and a bundle list, so the two cannot drift (S2).
      entrySubmodule = {
        options = {
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [];
            description = "Nix packages added on top of the org environment.";
          };

          rPackages = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "CRAN package names (resolved against pkgs.rPackages; dots map to underscores, unknown names fail with a request-to-add message).";
          };

          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Environment variables (values must be strings). Applied in order — bundles first, then the shell — so later entries win.";
          };

          shellHook = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Shell hook lines, run after the org environment's setup (bundles first, then the shell's own).";
          };
        };
      };
    in {
      _file = ./opi.nix;

      # The package set every opi shell is built from: one nixpkgs instantiation
      # with the version-of-record overlay, so a project listing `"arrow"` and
      # `pkgs.arrow-cpp` cannot end up with two arrows from two package sets.
      # mkDefault so a consumer that instantiates pkgs itself wins — and is then
      # responsible for applying `opi.overlays.default` to it.
      config._module.args.pkgs = lib.mkDefault (import inputs.nixpkgs {
        inherit system;
        overlays = [versionOfRecord];
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["positron-bin"];
      });

      options.opi.bundles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule entrySubmodule);
        default = {};
        description = "Named bundles of packages/env/shellHook that shells include via opi.shells.<name>.bundles. Predefined ones (geo, shiny) ship with opi.";
      };

      # Shipped bundles are ordinary definitions: a project that defines
      # `opi.bundles.<name>` merges with them (same-named entries merge as
      # submodules, so a project can extend geo rather than replace it).
      config.opi.bundles = shippedBundles;

      options.opi.shells = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            imports = [
              entrySubmodule
              # `name` is the attribute name (attrsOf passes it as a module arg),
              # so it must be an argument of this module, not a lexical value.
              ({name, ...}: {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    default = "opi-${name}-shell";
                    description = "Name of the resulting devShell.";
                  };

                  bundles = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [];
                    description = "opi.bundles entries applied to this shell, in list order, before the shell's own opts.";
                  };
                };
              })
            ];
          }
        );
        default = {};
      };

      config.devShells =
        lib.mapAttrs (
          shellName: cfg: let
            appliedBundles =
              map (
                bundleName:
                  config.opi.bundles.${bundleName}
                  or (throw "opi.shells.${shellName}.bundles: unknown bundle '${bundleName}'")
              )
              cfg.bundles;
          in
            mkOpiShell {
              inherit pkgs lib;
              inherit (cfg) name;

              # Bundles first, then the shell's own opts.
              rPackages = lib.concatMap (b: b.rPackages) appliedBundles ++ cfg.rPackages;
              packages = lib.concatMap (b: b.packages) appliedBundles ++ cfg.packages;
              env = lib.mergeAttrsList (map (b: b.env) appliedBundles ++ [cfg.env]);
              shellHook = lib.concatMapStrings (b: b.shellHook) appliedBundles + cfg.shellHook;
            }
        )
        config.opi.shells;
    }
  );
}
