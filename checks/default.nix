# Flake checks.
#
# Mostly eval-time assertions. `nix flake check` evaluates every devShell, so the
# failures worth catching here are the ones that happen during evaluation: an R
# name the resolver cannot find, a stale org-package lock, a base shell that lost
# its contract. Each check is a trivial derivation gated on an assertion, so a red
# build means the assertion failed — not that some other build produced $out.
#
# One check does build: `opi-env-loads-transitive-deps`, because "the packages
# actually load" is not an eval-time fact (it is the check that catches a broken
# R_LIBS_SITE or a missing org set). It is scoped to x86_64-linux on purpose:
# the composition bug it guards is platform-independent, so building the closure
# on three platforms would triple CI cost for no new signal. Widen it once the
# org cache is subscribed everywhere (P2).
#
# What is deliberately not here:
#
#   - Building R packages on every platform. Minutes to hours times three; the
#     platform-independent part is covered by the single Linux check above.
#   - Anything that needs a second `nix` process to evaluate another flake
#     (examples/, templates/, the module fixtures under checks/fixtures/). Those
#     are covered by scripts/check-consumers, which CI runs.
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    config,
    system,
    ...
  }: let
    rp = import ../lib/rPackages.nix {inherit pkgs lib;};

    check = name: cond: msg:
      if cond
      then pkgs.runCommand "check-${name}" {} "touch $out"
      else throw "check-${name}: ${msg}";

    # Every opi shell is built by lib/mkOpiShell.nix, so asserting the contract
    # on the base shell asserts it for project shells and `<pkg>-dev` shells too
    # (scripts/check-consumers proves the composition actually reaches a project).
    # mkShell lifts `env` entries to attributes, so this is readable at eval time.
    baseShell = config.devShells.base;

    arrowInBase =
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      baseShell.buildInputs;

    # The runtime closure for the org environment, composed exactly as
    # `packages.base-env` is. Its claim is that dev-only weight cannot be in it
    # (invariant 8 by construction), so the checks assert absence rather than a
    # shorter list.
    baseEnv = import ../lib/runtimeEnv.nix {inherit pkgs lib;};

    # A shell with extras, composed as the module composes one. This is the case
    # that was broken: the module passed only the shell's own rPackages to
    # mkRenv, so a project's <name>-env had no `targets` and no `dplyr` while its
    # dev shell had both.
    projectEnv = import ../lib/runtimeEnv.nix {
      inherit pkgs lib;
      rPackages = ["sf"];
    };

    # Everything the runtime closure contains: the wrapper (what an image copies)
    # plus the packages it references.
    envPaths = [baseEnv.package pkgs.R] ++ baseEnv.resolved;

    inEnv = needle: builtins.any (p: lib.hasInfix needle (p.name or "")) envPaths;

    envArrowCount = builtins.length (
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      envPaths
    );

    # An image composed the way a project would, with small `contents` on
    # purpose: the contract is what is under test, not R. (The pilot's image is
    # where `mkRenv` meets `mkImage` for real.)
    probeImage = import ../lib/mkImage.nix {
      inherit pkgs lib;
      nix2container = inputs.nix2container.packages.${system}.nix2container;
      name = "probe/img";
      tag = "check";
      contents = [pkgs.bash];
      env = {OPI_CHECK = "1";};
      requiredEnv = ["OPI_CHECK"];
      entrypoint = ["/bin/sh" "-c" "true"];
      revision = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345abc";
      source = "0s5y0vj2q3krm9wz4x8bnc1dfgh6p7qs";
      port = 8080;
    };

    probePush = import ../lib/pushImage.nix {
      inherit pkgs lib;
      image = probeImage;
      flakeAttr = "probe-image";
      migrateJob = "probe-migrate";
      region = "us-central1";
      project = "probe-project";
    };

    # `<pkg>-dev` shells are the only shells the module does not build: they come
    # from shells/private.nix and put the org package in `packages` (which mkShell
    # maps to nativeBuildInputs, where R's envHook finds it) instead of
    # `rPackages`. Nothing checked that path at all.
    orgPackages = import ../lib/orgPackages.nix {inherit inputs system lib;};

    devShellProblems =
      builtins.concatMap (
        pkgName: let
          shellName = "${pkgName}-dev";
          shell = config.devShells.${shellName} or null;
          expected = orgPackages.packages.${pkgName}.name or null;
          carries =
            shell
            != null
            && builtins.any (p: (p.name or null) == expected) (shell.nativeBuildInputs or []);
        in
          if carries
          then []
          else [shellName]
      )
      orgPackages.names;

    # A project-shaped shell, composed the way the module composes one (extras
    # on top of the org environment, same pkgs). S1's acceptance criterion is
    # that this path carries exactly one `arrow` — the patched one — and still
    # has the org env and the project's own overrides.
    projectShell = import ../lib/mkOpiShell.nix {
      inherit pkgs lib;
      name = "check-opi-project-shell";
      rPackages = ["sf" "data.table"];
      packages = [pkgs.jq];
      env.FIXTURE_PROJECT = "1";
    };

    arrowInProject =
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      projectShell.buildInputs;

    # A lock missing an org package is the signature of a stale opi input in a
    # consuming flake; lib/orgPackages.nix must throw rather than ship a base
    # shell without the org packages.
    orgPackagesWithoutInputs = import ../lib/orgPackages.nix {
      inputs = {};
      system = "x86_64-linux";
      inherit lib;
    };
  in {
    checks =
      {
        # The resolver maps CRAN names onto pkgs.rPackages, including the dot ->
        # underscore spelling, and finds the org's own packages — which only
        # resolve if overlays/default.nix is applied to this repo's pkgs.
        opi-resolver-resolves =
          check "opi-resolver-resolves"
          (builtins.all (n: (builtins.tryEval (rp.resolve n)).success) [
            "dplyr"
            "ggplot2"
            "data.table"
            "arrow"
            "ojodb"
          ])
          "a known R package name failed to resolve (dot -> underscore mapping, or the version-of-record overlay, is broken)";

        # PLAN invariant #4: unknown names throw rather than silently skipping.
        opi-resolver-unknown-throws =
          check "opi-resolver-unknown-throws"
          (!(builtins.tryEval (rp.resolveMany ["dplry"])).success)
          "resolveMany accepted an unknown package name";

        # ... and the throw is actionable. This is the part a tryEval-only check
        # misses: a broken hint path once passed `flake check` and only failed on a
        # deliberate typo test.
        opi-resolver-suggests =
          check "opi-resolver-suggests"
          (builtins.elem "dplyr" (rp.nearest "dplry") && lib.hasInfix "Did you mean" (rp.hint "dplry"))
          "the unknown-name suggestion did not offer 'dplyr' for 'dplry'";

        opi-orgpackages-stale-lock-throws =
          check "opi-orgpackages-stale-lock-throws"
          (!(builtins.tryEval (lib.isAttrs orgPackagesWithoutInputs)).success)
          "orgPackages accepted inputs that do not carry the org package flakes";

        # What ships is the manifest, so the manifest is what gets asserted.
        # nix2container writes `config` verbatim, so the capitalised OCI keys are
        # load-bearing: with lowercase `entrypoint`/`env` the image has no
        # Entrypoint and no Env, and the failure only shows up when the container
        # will not start (oscn-rs shipped exactly this).
        opi-image-config = pkgs.runCommandLocal "check-opi-image-config" {nativeBuildInputs = [pkgs.jq];} ''
          jq -e '
            (."image-config".Entrypoint == ["/bin/opi-entrypoint", "/bin/sh", "-c", "true"])
            and (."image-config".Env == ["OPI_CHECK=1"])
            and (."image-config".User == "1000:1000")
            and (."image-config".ExposedPorts["8080/tcp"] == {})
            and (."image-config".Labels["org.openjusticeok.builder"] == "opi/mkImage")
            and (."image-config".Labels["org.openjusticeok.required-env"] == "OPI_CHECK")
            and (."image-config".Labels["org.opencontainers.image.revision"] == "a1b2c3d4e5f60718293a4b5c6d7e8f9012345abc")
            and (."image-config".Labels["org.openjusticeok.source"] == "0s5y0vj2q3krm9wz4x8bnc1dfgh6p7qs")
            and ((."image-config" | has("entrypoint")) | not)
            and ((."image-config" | has("env")) | not)
          ' ${probeImage}
          touch $out
        '';

        # inv 13's runtime half: a missing declaration is a boot failure with
        # EX_CONFIG (78), naming the variable, rather than a failure at first use
        # deep inside a query. With it set, the guard hands over to the real
        # entrypoint.
        opi-image-guard = pkgs.runCommandLocal "check-opi-image-guard" {} ''
          set +e
          message=$(env -u OPI_CHECK ${probeImage.guard}/bin/opi-entrypoint true 2>&1)
          status=$?
          set -e
          if [ "$status" -ne 78 ]; then
            echo "expected exit 78 for a missing required env, got $status" >&2
            exit 1
          fi
          case "$message" in
            *OPI_CHECK*) ;;
            *)
              echo "the failure did not name the missing variable: $message" >&2
              exit 1
              ;;
          esac
          OPI_CHECK=1 ${probeImage.guard}/bin/opi-entrypoint true

          # No PATH and no /bin at all: the guard must be pure bash, because a
          # container's PATH is whatever the image happens to set. A
          # `printenv`-based guard would report the variable as missing here.
          env -i OPI_CHECK=1 ${probeImage.guard}/bin/opi-entrypoint ${pkgs.coreutils}/bin/true
          touch $out
        '';

        # The push/pin helper's silent-failure guards: a dry run changes nothing,
        # and a tfvars with no `image_name` line is refused (a sed that matches
        # nothing exits 0 — that is how a pin silently does not happen).
        opi-push-image-guards =
          pkgs.runCommandLocal "check-opi-push-image-guards" {
            inherit (probePush) target;
            push = probePush;
          } ''
            set -euo pipefail
            hex=$(printf 'a%.0s' {1..64})

            mkdir -p repo/infra/tofu
            touch repo/flake.nix
            printf 'image_name = "old/img@sha256:%s"\n' "$hex" > repo/infra/tofu/terraform.tfvars
            before=$(cat repo/infra/tofu/terraform.tfvars)

            dry=$(cd repo && "$push/bin/opi-push-image" --dry-run)
            case "$dry" in
              *"$target"*) ;;
              *)
                echo "the dry run did not name the target: $dry" >&2
                exit 1
                ;;
            esac
            case "$dry" in
              *"would pin"*) ;;
              *)
                echo "the dry run did not describe the pin: $dry" >&2
                exit 1
                ;;
            esac
            if [ "$before" != "$(cat repo/infra/tofu/terraform.tfvars)" ]; then
              echo "the dry run modified the tfvars" >&2
              exit 1
            fi

            mkdir -p broken/infra/tofu
            touch broken/flake.nix
            echo '# no pin line here' > broken/infra/tofu/terraform.tfvars
            if (cd broken && "$push/bin/opi-push-image" --dry-run); then
              echo "expected a refusal when the tfvars has no image_name line" >&2
              exit 1
            fi

            if (cd repo && "$push/bin/opi-push-image" --force); then
              echo "expected an unknown argument to be rejected" >&2
              exit 1
            fi
            touch $out
          '';

        # A shell's runtime closure is the org set *plus* the shell's extras. When
        # it was only the extras, nothing failed until CI ran tar_validate() in the
        # artifact — so assert it here, where the composition happens.
        opi-env-includes-org-set =
          check "opi-env-includes-org-set"
          (
            builtins.any (p: lib.hasPrefix "r-targets-" (p.name or "")) projectEnv.resolved
            && builtins.any (p: lib.hasPrefix "r-sf-" (p.name or "")) projectEnv.resolved
            && builtins.length projectEnv.resolved > builtins.length baseEnv.resolved
          )
          "a shell's runtime closure lost the org standard R set (or its own extras)";

        # The runtime closure carries nothing a process does not need. This is
        # invariant 8 as an assertion rather than a promise: if someone adds a
        # dev-only package to the runtime path, this fails by name.
        opi-env-runtime-only =
          check "opi-env-runtime-only"
          (
            !(inEnv "positron")
            && !(inEnv "gcc")
            && !(inEnv "cmake")
            && !(inEnv "cargo")
            && !(inEnv "rustc")
            && !(inEnv "quarto")
            && !(inEnv "postgresql")
            && !(inEnv "duckdb")
            && !(inEnv "google-cloud-sdk")
            && envArrowCount == 1
          )
          "the runtime closure picked up dev-only weight (Positron, a compiler, a CLI tool, or a second arrow) — it should be R + rPackages + env only";

        # Same env as the shell (invariant 10) plus an explicit R_LIBS_SITE, since
        # there is no R setup hook to compute one for a process.
        opi-env-contract =
          check "opi-env-contract"
          (
            baseEnv.env.R_HOME
            == "${pkgs.R}/lib/R"
            && baseEnv.env.R_LIBS_USER == "${pkgs.emptyDirectory}"
            && baseEnv.env.R_ENVIRON_USER == "/dev/null"
            && baseEnv.env.R_MAKEVARS_USER == "/dev/null"
            && lib.hasPrefix "/nix/store/" (toString (baseEnv.env.FONTCONFIG_FILE or null))
            # QUARTO_R lives in the shared env, not in a shellHook, so an image
            # inherits it (invariant 10) — a hook is something an image never runs.
            && baseEnv.env.QUARTO_R == "${pkgs.R}/bin/R"
            # R_LIBS_SITE comes from R's setup hook at build time, so it is a
            # derivation rather than a string here.
            && lib.isDerivation baseEnv.rLibsSite
          )
          "the runtime closure's env diverged from the shell's";

        # The shell contract: R_HOME, the three immutability pins, the fontconfig
        # path, and QUARTO_R. Losing any of these is silent otherwise — the shell
        # still opens, R just behaves differently than documented.
        opi-shell-contract =
          check "opi-shell-contract"
          (
            baseShell.R_HOME
            == "${pkgs.R}/lib/R"
            && baseShell.R_LIBS_USER == "${pkgs.emptyDirectory}"
            && baseShell.R_ENVIRON_USER == "/dev/null"
            && baseShell.R_MAKEVARS_USER == "/dev/null"
            # FONTCONFIG_FILE is the makeFontsConf derivation; mkShell keeps it as
            # an attrset, so compare its store path rather than its type.
            && lib.hasPrefix "/nix/store/" (toString (baseShell.FONTCONFIG_FILE or null))
            && baseShell.QUARTO_R == "${pkgs.R}/bin/R"
          )
          "the base shell lost part of its contract (R_HOME, the immutability pins, FONTCONFIG_FILE, or QUARTO_R)";

        # One `arrow`, from the package set the shells are built from. Zero means
        # the overlay stopped injecting it; more than one is the mixed-pkgs bug
        # (F1) coming back — a project would get an unpatched arrow on R_LIBS_SITE.
        opi-shell-one-arrow =
          check "opi-shell-one-arrow"
          (
            builtins.length arrowInBase
            == 1
            && builtins.any (p: p.drvPath == pkgs.rPackages.arrow.drvPath) baseShell.buildInputs
          )
          "the base shell carries zero or several `arrow` derivations — a second package set is leaking in";

        # The private-package dev shells: one per org package, each carrying that
        # package so its propagated deps land on R_LIBS_SITE.
        opi-private-dev-shells =
          check "opi-private-dev-shells"
          (devShellProblems == [])
          "these <pkg>-dev shells are missing or do not carry their org package: ${lib.concatStringsSep ", " devShellProblems}";

        # The project path (org environment + extras) keeps the same properties:
        # one arrow, the org env intact, the project's own env applied on top.
        opi-shell-project-compose =
          check "opi-shell-project-compose"
          (
            builtins.length arrowInProject
            == 1
            && builtins.any (p: p.drvPath == pkgs.rPackages.arrow.drvPath) projectShell.buildInputs
            && projectShell.R_HOME == "${pkgs.R}/lib/R"
            && projectShell.FIXTURE_PROJECT == "1"
          )
          "a project shell did not compose as org environment + extras (missing arrow, second package set, lost R_HOME, or an env override was dropped)";
      }
      # The one check that builds. Scoped to x86_64-linux: the composition bug it
      # guards (org set missing, or transitive R deps missing from R_LIBS_SITE, as
      # in targets -> R6) is platform-independent, so building the closure on
      # darwin and arm too would only triple CI time. See the header.
      // lib.optionalAttrs (system == "x86_64-linux") {
        opi-env-loads-transitive-deps = pkgs.runCommandLocal "check-opi-env-loads-transitive-deps" {} ''
          ${baseEnv.package}/bin/Rscript -e 'library(targets); stopifnot(requireNamespace("R6", quietly = TRUE)); cat("ok\n")'
          touch $out
        '';
      };
  };
}
