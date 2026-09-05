# flake-parts module for opi project shells.
#
# Usage (in a flake that imports opi-flakes.flakeModules.opi):
#   perSystem = { pkgs, ... }: {
#     opi.shells.default.packages = [ pkgs.jq ];
#     opi.layers.geo = {
#       packages = [ pkgs.gdal ];
#       env.PROJ_DATA = "${pkgs.proj}/share/proj";
#     };
#     opi.shells.geo.layers = [ "geo" ];
#   };
#
# Each `opi.shells.<name>` entry materializes as devShells.<name>,
# wrapping the opi base shell:
#
#   shell = base + layers (in listed order) + own packages/env/shellHook
#
# Because these are typed flake-parts options, multiple imported modules
# can contribute to the same shell or layer (packages append, env merges
# recursively) without any single call site owning it.
#
# Two composition styles:
#   - Adjacent shells: separate `opi.shells` entries for independent
#     kinds of work. Each is base + its own opts; they do not include
#     each other's extras.
#   - Layered shells: shared bundles defined as `opi.layers.<name>` and
#     referenced by one or more shells via `layers = [ ... ]`. Use this
#     when shells should share a common set of packages/env/hooks.
#
# The base shell is auto-wired from an `opi-flakes` input when present,
# and can always be set explicitly to override.
#
# Predefined layers from opi-flakes (layers/: geo, shiny) are merged
# in as defaults; projects can include, extend, or override them.
{ flake-parts-lib, inputs, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, system, ... }:
    let
      opiFlakes = inputs.opi-flakes or null;

      defaultBase =
        if opiFlakes != null && opiFlakes ? base then
          opiFlakes.base.devShells.${system}.default
        else
          throw "opi.shells.<name>.base: no opi-flakes input found in this flake; set base explicitly to an opi base devShell";

      # Predefined layers shipped with opi-flakes, as module definitions
      # for opi.layers. env values are wrapped in mkDefault so projects
      # can override them without conflicting definitions.
      shippedLayers = lib.mapAttrs (
        _: entry:
          lib.recursiveUpdate entry
            { env = lib.mapAttrs (_: lib.mkDefault) (entry.env or { }); }
      ) (import ../layers pkgs);


      entrySubmodule = {
        options = {
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages added on top of the base shell.";
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

      # Compose a shell from base passthru + layers (in listed order) +
      # the shell's own opts. Layers first, own opts last. env values
      # here are evaluated option values (mkDefaults already resolved),
      # so plain attrset merging is safe.
      composeShell =
        base: appliedLayers: cfg:
        pkgs.mkShell {
          inherit (cfg) name;
          inputsFrom = [ base ];
          packages = (lib.concatMap (l: l.packages) appliedLayers) ++ cfg.packages;
          env = lib.mergeAttrsList (
            [ (base.shellEnv or { }) ] ++ map (l: l.env) appliedLayers ++ [ cfg.env ]
          );
          shellHook =
            (base.shellHook or "")
            + lib.concatMapStrings (l: l.shellHook) appliedLayers
            + cfg.shellHook;
        };
    in
    {
      options.opi.layers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule entrySubmodule);
        default = { };
        description = "Named bundles of packages/env/shellHook that shells can include via opi.shells.<name>.layers. Predefined ones (geo, shiny) ship with opi-flakes.";
      };

      config.opi.layers = shippedLayers;

      options.opi.shells = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                base = lib.mkOption {
                  type = lib.types.package;
                  default = defaultBase;
                  description = "The opi base devShell to wrap. Defaults to the base devShell of the caller's opi-flakes input.";
                };

                name = lib.mkOption {
                  type = lib.types.str;
                  default = "opi-${name}-shell";
                  description = "Name of the resulting devShell.";
                };

                layers = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "opi.layers entries applied to this shell, in list order, before the shell's own opts.";
                };

                packages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                  description = "Extra packages added on top of the base shell and layers.";
                };

                env = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Extra environment variables (values must be strings). Overrides same-named base.shellEnv and layer vars.";
                };

                shellHook = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  description = "Extra shell hook lines, run after the base shell's and layers' setup.";
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
            appliedLayers = map (
              layerName:
                config.opi.layers.${layerName}
                  or (throw "opi.shells.${shellName}.layers: unknown layer '${layerName}'")
            ) cfg.layers;

            # shellEnv/shellHook passthru are the opi base shell's contract
            # with this module (see base/flake.nix). A shell missing them is
            # not an opi base shell; fail loudly rather than silently dropping
            # R_HOME/FONTCONFIG_FILE and the base setup hook.
            isOpiBase = base ? shellEnv && base ? shellHook;
          in
          lib.throwIf
            (!isOpiBase)
            "opi.shells.${shellName}.base: not an opi base shell (missing shellEnv/shellHook passthru); use an opi base devShell"
            (composeShell base appliedLayers cfg)
      ) config.opi.shells;
    }
  );
}
