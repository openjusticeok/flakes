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

      # Each shell entry, with its bundles resolved once and reused by both
      # materializations below.
      shellsWithBundles =
        lib.mapAttrs (
          shellName: cfg: let
            appliedBundles =
              map (
                bundleName:
                  config.opi.bundles.${bundleName}
                  or (throw "opi.shells.${shellName}.bundles: unknown bundle '${bundleName}'")
              )
              cfg.bundles;
          in {
            inherit shellName appliedBundles;
            rPackages = lib.concatMap (b: b.rPackages) appliedBundles ++ cfg.rPackages;
            env = lib.mergeAttrsList (map (b: b.env) appliedBundles ++ [cfg.env]);
            inherit (cfg) name packages shellHook;
            bundlePackages = lib.concatMap (b: b.packages) appliedBundles;
            bundleShellHook = lib.concatMapStrings (b: b.shellHook) appliedBundles;
          }
        )
        config.opi.shells;

      # Images: one per divergence in content, never per differing arguments
      # (ARCHITECTURE §4). Provenance labels come from the consuming flake's own
      # `self`, so an image records which revision and which lockfile built it
      # (inv 11) without the project wiring anything.
      opiImages =
        lib.mapAttrs (
          imageName: cfg: let
            # Naming a shell makes the image that shell's runtime closure: the
            # dev shell and the image cannot disagree about R, the R packages or
            # the env (invariant 10), because both are materializations of one
            # declaration (ARCHITECTURE §3).
            renv =
              if cfg.shell == null
              then null
              else let
                entry =
                  shellsWithBundles.${cfg.shell}
                  or (throw "opi.images.${imageName}: unknown shell '${cfg.shell}' (declared in opi.shells)");
              in
                import ../../lib/mkRenv.nix {
                  inherit pkgs lib;
                  inherit (entry) rPackages env;
                };
          in {
            image = import ../../lib/mkImage.nix {
              inherit pkgs lib;
              # The consumer's input if they pin their own, else opi's.
              nix2container =
                (
                  inputs.nix2container or inputs.opi.inputs.nix2container
                or (throw "opi.images.${imageName}: the `opi` flake input must be named `opi`, or add a `nix2container` input")
                ).packages.${
                  system
                }.nix2container;
              name = "${cfg.repository}/${imageName}";
              contents =
                (
                  if renv == null
                  then []
                  else renv.paths
                )
                ++ cfg.contents;
              env =
                (
                  if renv == null
                  then {}
                  else
                    renv.env
                    // {
                      # `Rscript`/`R` have to resolve inside the container: the
                      # entrypoint is a shell command and an image has no
                      # profile to put the runtime on PATH. The wrapper carries
                      # the env, so this also keeps R_LIBS_SITE on the process
                      # even when a platform injects env of its own.
                      PATH = lib.concatStringsSep ":" [
                        "${renv.package}/bin"
                        "/usr/local/bin"
                        "/usr/bin"
                        "/bin"
                      ];
                    }
                )
                // cfg.env;
              inherit (cfg) entrypoint requiredEnv cmd tag port;
              revision = inputs.self.rev or null;
              source = baseNameOf (toString inputs.self);
            };
          }
        )
        config.opi.images;
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

      # An image is the same idea as a shell, materialized for a container. A
      # project declares it once here (not in a Containerfile — ARCHITECTURE §4)
      # and gets two outputs: <name>-image, and <name>-push, the deploy step.
      options.opi.images = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              repository = lib.mkOption {
                type = lib.types.str;
                description = "Artifact Registry path without the image name (e.g. us-central1-docker.pkg.dev/PROJECT/REPO). The image is <repository>/<name>.";
              };

              shell = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "An opi.shells entry whose runtime closure fills `contents` and `env`: same R, same R packages, same env as that shell (invariant 10). Leave null for a non-R image.";
              };

              contents = lib.mkOption {
                type = lib.types.listOf (lib.types.either lib.types.package lib.types.path);
                default = [];
                description = "Store paths laid at the image root. With `shell`, the runtime closure's `paths` are added automatically; use this for code-adjacent assets (a Shiny app directory), never for data.";
              };

              entrypoint = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Command to run. opi does not dispatch (ARCHITECTURE §7): bind 0.0.0.0:$PORT, read env, export OTel, handle SIGTERM.";
              };

              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {};
                description = "config.env. For an R project this is the runtime closure's `env` (the same values the dev shell has, invariant 10).";
              };

              requiredEnv = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Env var names that must be non-empty at boot (inv 13). The entrypoint exits 78 rather than failing later; the list is also a label so tofu and ops can compare it with what is actually mounted.";
              };

              cmd = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                description = "Default arguments. Several workloads sharing one image differ here, not in `contents` (ARCHITECTURE §4).";
              };

              tag = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Image tag; null uses nix output hash, which cannot be stale. Deploys pin a digest regardless.";
              };

              port = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Port to expose (Cloud Run sets $PORT).";
              };

              tfvars = lib.mkOption {
                type = lib.types.str;
                default = "infra/tofu/terraform.tfvars";
                description = "File <name>-push pins the digest into, relative to the repository root.";
              };

              migrateJob = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Cloud Run job that must run after `tofu apply` (the ordering trap, ARCHITECTURE §4).";
              };

              gcpProject = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "GCP project, for the closing instructions.";
              };

              region = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "GCP region, for the closing instructions.";
              };
            };
          }
        );
        default = {};
      };

      config.devShells = lib.mapAttrs (_: e:
        mkOpiShell {
          inherit pkgs lib;
          inherit (e) name rPackages env;
          packages = e.bundlePackages ++ e.packages;
          shellHook = e.bundleShellHook + e.shellHook;
        })
      shellsWithBundles;

      # Materialization 2: what a process runs in — the runtime closure CI can
      # `nix run` and an image can copy. Same declaration, no dev-only weight:
      # bundle `packages` are deliberately absent here, because a nix-built R
      # package carries its own native deps and a bundle's CLIs are for humans
      # (ARCHITECTURE §5).
      config.packages =
        lib.mapAttrs' (
          shellName: e:
            lib.nameValuePair "${shellName}-env"
            (import ../../lib/mkRenv.nix {
              inherit pkgs lib;
              inherit (e) rPackages env;
            }).package
        )
        shellsWithBundles
        # Materialization 3: images, declared in opi.images.
        // lib.mapAttrs' (imageName: v: lib.nameValuePair "${imageName}-image" v.image) opiImages;

      # The deploy step: push, resolve the digest, pin it in tfvars, and say what
      # to run next (lib/pushImage.nix).
      config.apps =
        lib.mapAttrs' (
          imageName: v:
            lib.nameValuePair "${imageName}-push" (import ../../lib/pushImage.nix {
              inherit pkgs lib;
              image = v.image;
              flakeAttr = "${imageName}-image";
              inherit (config.opi.images.${imageName}) tfvars migrateJob region;
              project = config.opi.images.${imageName}.gcpProject;
            })
        )
        opiImages;
    }
  );
}
