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
# Each `opi.shells.<name>` entry materializes as devShells.<name>, wrapping the
# opi base shell: base + bundles (in listed order) + own rPackages/packages/env.
#
# Because these are typed flake-parts options, multiple imported modules can
# contribute to the same shell or bundle (packages append, env merges
# recursively) without any single call site owning it.
#
#   - Adjacent shells: separate `opi.shells` entries for independent kinds of
#     work; each is base + its own opts.
#   - Bundled shells: shared bundles defined as `opi.bundles.<name>` and
#     referenced by one or more shells via `bundles = [ ... ]`.
#
# The base shell is auto-wired from the `opi` input and can be set explicitly.
# Predefined bundles (shells/bundles/: geo, shiny, quarto) are merged in as
# defaults; projects can include, extend, or override them.
{ flake-parts-lib, inputs, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, system, ... }:
    let
      opi = inputs.opi or null;

      defaultBase =
        if opi != null && opi ? devShells && opi.devShells ? ${system} && opi.devShells.${system} ? base then
          opi.devShells.${system}.base
        else
          throw "opi.shells.<name>.base: no `opi` input with a base devShell found; set base explicitly to an opi base devShell";

      # CRAN-name -> derivation resolver (pkgs.rPackages, dot -> underscore).
      rp = import ../../lib/rPackages.nix { inherit pkgs lib; };

      # Predefined bundles shipped with opi (shells/bundles/), exposed as
      # opi.bundles defaults. env values are mkDefault so projects can override
      # without conflicting definitions.
      shippedBundles = lib.mapAttrs (
        _: entry:
          lib.recursiveUpdate entry
            { env = lib.mapAttrs (_: lib.mkDefault) (entry.env or { }); }
      ) (import ../../shells/bundles pkgs);

      entrySubmodule = {
        options = {
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Nix packages added on top of the base shell.";
          };

          rPackages = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "CRAN package names provided by this bundle (resolved against pkgs.rPackages).";
          };

          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Environment variables (values must be strings). Overrides same-named base.shellEnv vars.";
          };

          shellHook = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Shell hook lines, run after the base shell's built-in setup.";
          };
        };
      };

      # Compose a shell from the base contract + bundles (in listed order) +
      # the shell's own opts. R packages go through buildInputs so R's setup
      # hook populates R_LIBS_SITE (no wrapper shim; Positron-friendly).
      composeShell =
        base: appliedBundles: cfg:
        let
          # R packages contributed by bundles first, then the shell's own.
          allRPackages = lib.concatMap (b: b.rPackages) appliedBundles ++ cfg.rPackages;
        in
        pkgs.mkShell {
          inherit (cfg) name;
          inputsFrom = [ base ];
          buildInputs = rp.resolveMany allRPackages;
          packages = (lib.concatMap (b: b.packages) appliedBundles) ++ cfg.packages;
          env = lib.mergeAttrsList (
            [ (base.shellEnv or { }) ] ++ map (b: b.env) appliedBundles ++ [ cfg.env ]
          );
          # The base shell's own shellHook is included automatically via
          # `inputsFrom = [ base ]` (mkShell concatenates its inputs' shellHooks
          # ahead of ours), so it must NOT be prepended here or it runs twice.
          shellHook =
            lib.concatMapStrings (b: b.shellHook) appliedBundles + cfg.shellHook;
        };
    in
    {
      _file = ./opi.nix;

      options.opi.bundles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule entrySubmodule);
        default = { };
        description = "Named bundles of packages/env/shellHook that shells include via opi.shells.<name>.bundles. Predefined ones (geo, shiny, quarto) ship with opi.";
      };

      config.opi.bundles = shippedBundles;

      options.opi.shells = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                base = lib.mkOption {
                  type = lib.types.package;
                  default = defaultBase;
                  description = "The opi base devShell to wrap. Defaults to the base devShell of the caller's `opi` input.";
                };

                name = lib.mkOption {
                  type = lib.types.str;
                  default = "opi-${name}-shell";
                  description = "Name of the resulting devShell.";
                };

                bundles = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "opi.bundles entries applied to this shell, in list order, before the shell's own opts.";
                };

                rPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "CRAN package names resolved against pkgs.rPackages (dots map to underscores). Unknown names fail with a request-to-add message.";
                };

                packages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                  description = "Extra Nix packages added on top of the base shell and bundles.";
                };

                env = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Extra environment variables (values must be strings). Overrides same-named base.shellEnv and bundle vars.";
                };

                shellHook = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  description = "Extra shell hook lines, run after the base shell's and bundles' setup.";
                };
              };
            }
          )
        );
        default = { };
      };

      config.devShells = lib.mapAttrs (
        shellName: cfg:
          let
            base = cfg.base;
            appliedBundles = map (
              bundleName:
                config.opi.bundles.${bundleName}
                  or (throw "opi.shells.${shellName}.bundles: unknown bundle '${bundleName}'")
            ) cfg.bundles;

            # shellEnv/shellHook passthru are the opi base shell's contract with
            # this module (see shells/base.nix). A base missing them is not an
            # opi base shell; fail loudly rather than silently dropping
            # R_HOME/FONTCONFIG_FILE and the base setup hook.
            isOpiBase = base ? shellEnv && base ? shellHook;
          in
          lib.throwIf
            (!isOpiBase)
            "opi.shells.${shellName}.base: not an opi base shell (missing shellEnv/shellHook passthru); use an opi base devShell"
            (composeShell base appliedBundles cfg)
      ) config.opi.shells;
    }
  );
}
