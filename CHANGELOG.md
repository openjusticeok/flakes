# Changelog

## v0.7.1 (2026-11-10)

### Added

- commit `checks/fixtures/module-ok/flake.lock`, so the one fixture that proves
  `opi.shells` still composes resolves its inputs from a lock like every example
  and template, instead of re-resolving them on each `check-consumers` run

### Fixed

- stop `opi-bootstrap` from rewriting `rproject.toml`, which no template ships
  now that rv is gone: the rewrite died on the missing file before any
  placeholder was filled, so a copy of the current template could not bootstrap
- drop `rproject.toml` from the script's `owned_paths`, so the provenance
  comparison no longer expects a file the template does not contain

## v0.7.0 (2026-11-10)

### Added

- add `opi.images.<name>`, yielding `<name>-image` and `<name>-push`; naming a
  shell makes the image that shell's runtime closure, so R, R packages, and env
  cannot drift between the two
- add `lib/mkRenv.nix`, which builds R, the resolved rPackages, and the env into
  a runnable wrapper; every `opi.shells.<name>` now also yields
  `packages.<name>-env`, and `shells/base.nix` exposes `packages.base-env`
- add `lib/rShellEnv.nix` to hold the shared env, so a shell and an image cannot
  disagree about fonts, `R_HOME`, or the immutability pins
- add `lib/runtimeEnv.nix`, routing base-env, `<name>-env`, and images through
  one composition so the org standard R set is always included alongside a
  shell's extras
- add `lib/orgPackages.nix` as the single list of org packages, replacing
  `overlays/r-private.nix`; a stale lock now fails with the re-lock command
- add `devShells.<pkg>-dev` built from the base shell plus the package, since
  package repos cannot depend on opi without an input cycle
- add `scripts/check-consumers`, which evaluates every example, template, and
  module fixture against the working tree with `--override-input opi` and forces
  each shell's drvPath so a throwing shell cannot pass
- add `checks/fixtures` with one good module consumer and three bad ones
  (unknown R package, unknown bundle, non-opi base) that must fail with the
  expected message
- add `opi-bootstrap` as a flake package, wrapping `scripts/bootstrap-template`
  so a repo created from the template can derive its provenance from the root
  commit's tree
- add `examples/image`, a Shiny app declared once as a shell and an image, with
  a `terraform.tfvars` the push helper pins by digest
- add `census`, `geoarrow`, and browser map packages to the gis template
- add `formatter = pkgs.alejandra` and reformat the tree; CI runs
  `nix fmt -- --check .`
- add `ARCHITECTURE.md`, `PLAN.md`, and `REVIEW.md` documenting the model and
  the simplification plan
- add `renovate.json` and a consumers CI job running formatting and
  `check-consumers --locks`

### Changed

- replace rv with nixpkgs rPackages throughout; CRAN names resolve via
  `pkgs.rPackages` in `lib/rPackages.nix`
- compose every opi shell through one function, with `mergeAttrsList` env
  merging and a base-contract assertion
- rename `opi.layers` to `opi.bundles`, keeping the old spelling as an alias,
  and move the base flake to `shells/base.nix`
- rename the `opi-flakes` input to `opi`
- resolve project rPackages against opi's overlay so private names and patched
  public packages match the base shell
- take `R_LIBS_SITE` from R's setup hook in a build instead of listing direct
  packages, so propagated deps like `targets` -> `R6` resolve
- move `QUARTO_R` into `rShellEnv`, so images inherit it and the shellHook
  export an image never ran is gone
- pin `R_ENVIRON_USER` and `R_MAKEVARS_USER` to `/dev/null` so `~/.Renviron` and
  `~/.R/Makevars` cannot override the shell's R setup
- pin consumer platforms via `opi.lib`
- write capitalised OCI config keys in `mkImage`, since nix2container serialises
  `config` verbatim and lowercase keys produce an image with no Entrypoint and
  no Env
- carry the git revision and the flake source hash in provenance labels rather
  than the lockfile hash, which throws when a consumer's lock is untracked
- emit `<name>-push` as a real flake `app` rather than a bare derivation
- expose `opi.lib.orgRPackages` alongside the standard set
- update arf to 0.5.3 and air to 0.12.0

### Fixed

- fix image contents by passing `mkRenv`'s wrapper as `copyToRoot` instead of
  the package list, which flattened 578 store paths to the root and moved R off
  the path `R_LIBS_SITE` points at
- enforce `requiredEnv` at boot with exit 78, using a pure-bash guard that does
  not depend on the container's PATH
- refuse a tfvars with no `image_name` line in `pushImage`, poll for the digest,
  and pin via write-then-rename
- suggest nearest known names when an rPackages entry is unknown
- skip jarl's check phase on darwin, where it fails on temp paths
- run `opi-env-loads-transitive-deps` only on x86_64-linux; the bug it guards is
  platform-independent, so the other platforms skip the build
- assert the env attribute in `opi-shell-contract` and `opi-env-contract`
  instead of grepping the hook

### Removed

- drop the `base/` flake, `lib/default.nix`, `lib/mkOpiShell.nix`, the
  `update-base-tool.sh` script and its scheduled workflows, and the tracked
  `result` symlink
- remove `scripts/develop`, which overrode the private package inputs to local
  sibling checkouts
- remove macos from the actions workflow matrix

## v0.6.0 (2026-08-28)

### Added

- add air and jarl configs and VS Code settings to the default template, so
  formatting, linting, and the Positron interpreter resolve to the project shell

### Changed

- drop the `rWrapper` and the `rPackages` list from the base shell; R packages
  now come from rv
- set `R_LIBS_SITE` alongside `R_LIBS_USER` and create `rv/library` directly
- pin `R_ENVIRON_USER` to the project `.Renviron`, or `/dev/null`, so a user
  `~/.Renviron` cannot override the project library
- print the shell banner after the R environment is set up

## v0.5.0 (2026-08-10)

### Added

- add the `default` flake template, with `.envrc`, `.Rprofile`, `.gitignore`
  covering `data/`, `rv/`, and `_targets/`, plus `rproject.toml` and `rv.lock`

## v0.4.1 (2026-08-03)

### Changed

- update arf to 0.4.5

## v0.4.0 (2026-07-28)

### Changed

- update r tools: arf to 0.4.4 and air to 0.11.0

## v0.3.4 (2026-07-25)

### Added

- add `duckdb` to the base system dependencies so the R package links the system
  library instead of compiling DuckDB from source

### Changed

- move the static libv8 setting into `rproject.toml` so rv manages it per project

## v0.3.3 (2026-07-25)

### Removed

- remove `R_COMPILE_AND_INSTALL_PACKAGES` from the shell; `rproject.toml`
  manages source builds through rv

## v0.3.2 (2026-07-24)

### Fixed

- set `NIX_LDFLAGS_<host>` rather than exporting `NIX_LDFLAGS`, so the gcc
  wrapper injects rpath flags on both linux and darwin

## v0.3.1 (2026-07-24)

### Fixed

- force R packages to build from source and embed Nix rpaths instead of
  exporting `LD_LIBRARY_PATH`, which made system binaries load Nix glibc

## v0.3.0 (2026-07-24)

### Added

- add git, gh, and the Google Cloud SDK to the base dev shell

### Changed

- split shell inputs into `rTools` and `devShellTools`

## v0.2.0 (2026-07-24)

### Added

- add libwebp to the base system dependencies for the R image packages

## v0.1.4 (2026-07-23)

### Added

- add weekly scheduled workflows that update rv, arf, jarl, and air through
  `base/tools.json`, and keep `flake.lock` current
- add `.github/scripts/update-base-tool.sh`, which prefetches the source hash,
  derives the cargo hash from a build, and verifies with `nix flake check`

## v0.1.3 (2026-07-22)

### Added

- commit `flake.lock` for the root and base flakes

## v0.1.2 (2026-07-22)

### Changed

- update `actions/checkout` to v7 and `cachix/install-nix-action` to v31

## v0.1.1 (2026-07-22)

### Added

- add a GitHub Actions workflow running `nix flake check` on push to `main` and
  on pull requests

## v0.1.0 (2026-07-22)

### Added

- add the opi base flake, bundling R, rv, arf, jarl, air, and the native
  libraries the org R packages link against
- expose `lib.mkOpiShell` for project-specific dev shells
