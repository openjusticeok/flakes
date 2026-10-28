# Plan: `openjusticeok/flakes`

Status: the `rv` → nixpkgs-`rPackages` collapse (P0) has landed on `feat/all-in`
and is verified; **S0 (guardrails) is done**; S1–S4 and P1–P4 remain. The active
plan from here is the simplification pass below: the repo carries more machinery
than its payload, most of it in the consumer module and the base shell. Rename to
`nix` stays the **last** step (post-review, post-merge).

## Goal

One flake that is the org's version-of-record: an R package set + non-R pins, dev
shells, a flake-parts module, templates, and deploy-facing overlays — with **rv
removed permanently**, a **single nixpkgs pin**, and **one way to compose a
shell**.

## Locked decisions

- **Nixpkgs base:** `rstats-on-nix/nixpkgs`, pinned by rev (dated branch /
  frozen-edge). Bump **monthly, merge-when-green**; skipping months is fine
  (quarterly == two skipped bumps). Deliverables are frozen by their own pins, so
  org-repo bumps only advance dev environments and new deliverables.
- **Naming (final phase):** repo `nix`; input alias `opi`; module
  `flakeModules.default`; options `opi.shells` + `opi.bundles`.
- **One flake, one nixpkgs pin**; flake-parts retained; **rv gone**.
- **Private repos are self-contained flakes** (build + devshell in-repo),
  consumed as inputs; the org repo aggregates.
- **No `sources.json`** — `flake.lock` + Renovate.
- Private packages injected into **`pkgs.rPackages`**; resolver accepts **CRAN
  names** (dot → underscore).
- **Strict immutability** (no writable user R lib, no escape hatch).
- CLI later (P3+).
- **Cachix private** (org cache `okpolicy`); platforms `x86_64-linux`,
  `aarch64-linux`, `aarch64-darwin`.
- **Base shell** is R + toolchain + the org-standard R set (tidyverse core,
  `targets`, `qs2`, `here`, `rmarkdown`, `knitr`, `readxl`, `googledrive`,
  `pointblank`, `arrow`) + `positron-bin`; projects add extras via
  `opi.shells.<name>.rPackages`. R packages are wired through R's setup hook
  (`R_LIBS_SITE`), not `rWrapper`.
- **Positron** is launched from the shell (`positron .`), so R and the IDE share
  one environment/nixpkgs (Linux `ark` dlopens libR in-process; glibc must match).
- **Bundles are an opt-in convenience, not a framework** (S2): three or so named
  sets of Nix packages; anything richer waits for a second real user.
- **Formatting:** `alejandra` via `nix fmt`, from our own nixpkgs pin. CI runs
  `nix fmt -- --check .`, so formatting is never a review topic.
- **`positron-bin` stays in the base shell** and its unfree predicate stays with
  the package-set owner (S1). Revisit only if a consumer needs to opt out.
- **Dropping the heavy system packages** (`arrow-cpp`, `abseil-cpp`, `udunits`)
  is expected to be safe but is **not yet measured** — S3 measures the closure
  and keeps an opt-in bundle for anyone who needs them.

## Invariants (must hold)

1. **Single nixpkgs pin.** The org repo declares every private input with
   `inputs.nixpkgs.follows = "nixpkgs"` **and `inputs.flake-parts.follows =
   "flake-parts"`**. Projects follow `opi/nixpkgs`. One pin governs the shipped
   closure. *Currently violated for flake-parts — the lock carries five
   `flake-parts` nodes (F9); fixed in S4.*
2. **No rv anywhere.** No `rv`, `rv/`, `rproject.toml`, `rv.lock`, `activate.R`,
   `.Rprofile`, `tools.json`, or rv-seam env hacks.
3. **Immutable R library.** R packages come from nix only; `R_LIBS_*` points at a
   nix-built library dir; no writable user lib.
4. **Actionable failures.** Resolver/bundles throw on unknown names with nearest
   matches.
5. **Frozen deliverables rely on cache retention.** Old closures must stay
   substitutable — org Cachix retention + the `rstats-on-nix` cache.

## Current state (verified on `feat/all-in`)

- `nix flake check` passes; `devShells.x86_64-linux` =
  `[base, default, ojodb-dev, ojoregex-dev, ojothemes-dev, ojoutils-dev]`.
- `examples/{project,module,base-direct}` all evaluate
  (`["default","shiny"]` / `["analysis","default","shiny"]` / `["default"]`).
- One nixpkgs pin; four private flakes as inputs; `overlays.default` exported and
  applied to the repo's own pkgs; `arrow` GCS/S3 override effective.
- 1442 hand-written `.nix` lines (excl. locks), 11 lock nodes, base shell with 57
  `buildInputs` (34 system + the R set). Up from 1146 before alejandra expanded
  the tree; S0 added ~170 lines of checks, fixtures, and the consumer script.
- **The module path is now covered.** `nix flake check` builds four eval-time
  checks, and `scripts/check-consumers` evaluates 11 consumer cases (examples,
  templates, one good and three bad module fixtures) — run by CI. Before S0,
  `config.opi.shells` was empty here, so nothing in CI traversed the 231-line
  module every consumer depends on, and the examples' locks went stale three
  times with no red build.

## Where the complexity is

| Surface | Lines | Buys | Verdict |
|---|---|---|---|
| `modules/flake/opi.nix` | 231 (148 code) | the consumer API | over-built; two mechanisms removable |
| `shells/base.nix` | 223 | R + 34 system pkgs + a pandoc pin | over-provisioned; ~half unused |
| `lib/rPackages.nix` | 89 | CRAN-name resolver + suggestions | right-sized — leave alone |
| `overlays/` (3 files) | 71 | two overrides | split too thin |
| `shells/bundles/` (4 files) | 46 | 6 packages, 1 bundle unused | concept > payload |
| examples + templates | 7 flake.nix, 789 lock lines | documentation | 3 templates suffice; untested |

**F1 — Two owners produce the version-of-record `pkgs`.** `flake.nix:59-62` sets
`_module.args.pkgs = import inputs.nixpkgs { overlays = … }`;
`modules/flake/opi.nix:54` *also* does `pkgsOpi = pkgs.extend opi.overlays.default`.
In a consumer, `pkgs` (what `opi.shells.<n>.packages = [ pkgs.jq ]` resolves
against) is unoverlaid while R packages resolve against the overlaid set — two
package sets per shell, and one overlay with two entry points that can stack.

**F2 — The `passthru.shellEnv`/`shellHook` protocol is a hand-rolled inheritance
channel.** `inputsFrom = [ base ]` already carries `buildInputs` and `shellHook`;
the protocol exists only to smuggle `env`. Cost: `shells/base.nix:216` +
`modules/flake/opi.nix:85-100` (read it back), two copies of the same guard
(`opi.nix:222`, `lib/mkPackageShell.nix:17`), and three "don't prepend the hook or
it runs twice" comments (`shells/base.nix:4-5`, `opi.nix:164-167`,
`mkPackageShell.nix:22-24`) — a documented footgun.

**F3 — The option surface defines the same 4-field record twice, plus dead
aliases.** `entrySubmodule` (`opi.nix:64-88`) and the shell submodule
(`opi.nix:148-200`) duplicate `rPackages`/`packages`/`env`/`shellHook`.
`opi.layers` (`137-142`), `opi.shells.<n>.layers` (`171-175, 198-201`) and the
`mkMerge` plumbing (`133-135`) exist for consumers that never shipped — `main`
never had this API.

**F4 — Bundle machinery exceeds the bundles.** `geo` = gdal+geos+proj; `shiny` =
chromium+nodejs; `quarto` = chromium — **referenced by nothing**. Registry file +
import + `mkDefault`-wrapping every `env` value (`opi.nix:66-70`) to ship 6
packages.

**F5 — The base shell provisions tools the design forbids using.**
`shells/base.nix:51-107`: 34 system packages including `arrow-cpp`,
`abseil-cpp`, `duckdb`, `postgresql`, `udunits`, `cargo`, `rustc`. The comment at
57-58 concedes they are not for building R packages; invariant #3 makes
`install.packages()` impossible and `PKG_CONFIG_PATH` is deliberately unexported,
so discovery does not work either. Every shell closure pays for them.

**F6 — CI tested the part with no complexity.** *(fixed in S0)*
`checks/default.nix` was one `tryEval` over three names that built `touch $out`.
Nothing built an R package or evaluated a consumer, and no failure path was
exercised.

**F7 — Seven copies of the same consumer flake; `census` ⊂ `gis`.**
`templates/census`'s R set is a strict subset of `templates/gis`'s. All seven say
`systems = flakeExposed` while three platforms are supported, so an unsupported
host gets the module's confusing "no `opi` input with a base devShell" throw
instead of "unsupported system". Templates also re-list base-standard packages
(`targets`, `ggplot2`, `dplyr`), hiding what base already provides.

**F8 — `scripts/develop` is a stale shim.** Its premise ("until the private
flakes are pushed to github") is dead — the lock pins all four at real revs. It
hardcodes the input names that `flake.nix` and `lib/orgPackages.nix` already own,
and the repo has no root `.envrc`.

**F9 — Five `flake-parts` nodes in the lock** (`flake-parts`…`flake-parts_5`):
the private inputs follow `nixpkgs` but not `flake-parts` (invariant #1).

**F10 — `pandocForQuarto` (40 lines, four hand-maintained hashes) lives in the
shell file** (`shells/base.nix:111`), turning `base.nix` into a pinning ground.

**Leave alone:** the resolver's suggestion machinery, the immutability pins
(`R_LIBS_USER`/`R_ENVIRON_USER`/`R_MAKEVARS_USER`), `lib/orgPackages.nix` as
single source of truth, the follows discipline, and the `arrow` override.

## Simplification plan

Each phase ships independently and is CI-verifiable. Order matters: guardrails
first, because every later phase rewrites consumer-facing evaluation.

### S0 — Guardrails — **done**

Shipped as its own commit series (formatting first, then the checks), because
none of the later phases can be verified without it.

1. `checks/default.nix` is now four eval-time assertions, each gated on a trivial
   derivation so a red check means the assertion failed: the resolver resolves
   (`dplyr`, `ggplot2`, `data.table` → underscore, `arrow` → overlay applied,
   `ojodb` → private package present), unknown names throw, the suggestion
   machinery still names the near-miss (`dplry` → `dplyr`), and a lock without
   the org inputs throws the re-lock message. `lib/rPackages.nix` exports
   `nearest`/`hint`/`known` for the middle two.
2. `checks/fixtures/` adds one good and three bad consumer flakes;
   `scripts/check-consumers` evaluates every example, template, and fixture
   against the working tree with `--override-input opi`. Two shapes matter and
   were both wrong on the first attempt: the eval forces each `drvPath`
   (`attrNames` alone never forces the values, so a throwing shell looked like a
   pass), and the loops skip directories without a `flake.nix` (a stray
   `examples/mkopi-shell/rv/library` made `nix eval` search upward and evaluate
   this repo's own flake).
3. `scripts/check-consumers --locks` re-locks the examples and fails on a diff,
   which is the one thing that catches the silently-stale path-input lock
   (REVIEW §7). Verified stable: re-locking reports no diff today.
4. `formatter = pkgs.alejandra`, and the whole tree is alejandra-formatted.
5. CI gains a `consumers` job (formatting + `check-consumers --locks`, one Linux
   runner) next to the existing three-platform `nix flake check`.

*Accept (met):* `nix flake check` builds all four checks; `check-consumers` →
11 passed, 0 failed; `--locks` → 14 passed; `nix fmt -- --check .` clean.

*Deviation from the plan as written:* the consumer checks are a script, not
`nix flake check` entries. A sandboxed build cannot copy the path inputs a nested
`nix eval` needs, so a check derivation would be fragile or network-dependent;
CI runs the script instead, and it works locally too.

### S1 — Collapse the shell contract (the big win)

1. New `lib/mkOpiShell.nix`: `{ pkgs, name, rPackages, packages, env, shellHook }`
   → one `mkShell`, owning `shellEnv` (R_HOME, FONTCONFIG_FILE, `R_LIBS_USER =
   emptyDirectory`, `R_ENVIRON_USER`/`R_MAKEVARS_USER = /dev/null`), the base
   readiness hook, and `QUARTO_R`.
2. `shells/base.nix` calls it once → `devShells.base`. Delete
   `passthru.shellEnv`/`passthru.shellHook` and the duplicated `shellHook`.
3. `modules/flake/opi.nix` calls it per shell. Delete `pkgsOpi`, `defaultBase`,
   `composeShell`'s env-merge list, and the `isOpiBase` guard.
4. Module owns `pkgs` via `config._module.args.pkgs = lib.mkDefault (import
   inputs.nixpkgs { overlays = [ opi.overlays.default ]; config.allowUnfreePredicate
   = …positron-bin; })`; `flake.nix:59-66` shrinks to
   `devShells.default = self'.devShells.base`. A consumer that overrides `pkgs`
   still gets `pkgs.extend` as the fallback path (F1).
5. `shells/private.nix` calls it with `packages = [ package ]`; delete
   `lib/mkPackageShell.nix` (its guard can never fire — the only caller passes
   `self'.devShells.base`).

*Accept:* examples evaluate as today; a project shell shows **one** `arrow` on
`R_LIBS_SITE` and it is the patched one; `QUARTO_R`, `R_HOME`, `FONTCONFIG_FILE`
and the immutability vars present; `pkgs.rPackages.arrow` under
`opi.shells.<n>.packages` and under `rPackages` are the same derivation.

### S2 — Shrink the option surface

1. Reuse one submodule: `opi.shells.<name>` = `entrySubmodule` + `{ base, name,
   bundles }`. Delete `opi.layers` / `opi.shells.<n>.layers` and the `mkMerge`.
2. Delete the unused `quarto` bundle; inline the surviving bundles into
   `shells/bundles/default.nix`; drop the `mkDefault` env wrapper.
3. Templates: delete `census` (subset of `gis`); `systems` pinned to the three
   platforms via an exported `opi.lib.systems`; show only deltas from the
   exported `opi.lib.standardRPackages`.
4. Delete `examples/base-direct` (equivalent to `nix develop .#base`).

*Accept:* opi.nix ≈ 130 lines; 3 templates and 2 examples, all CI-evaluated; one
old→new API table in the docs.

### S3 — Right-size the base shell

1. Measure first: `nix path-info -rSh` for `.#devShells.x86_64-linux.base` and one
   project shell, before and after. The expectation is that `arrow-cpp`,
   `abseil-cpp`, and `udunits` are dead weight (R packages carry their own
   native deps, `install.packages()` is impossible, and `PKG_CONFIG_PATH` is
   deliberately unexported), but it is not yet demonstrated — so this phase
   starts with the measurement, not the deletion.
2. Split `systemDependencies` into `always` (R + gcc/gnumake/cmake/pkg-config + a
   small `load_all` header set) and opt-ins (duckdb/postgres behind a `warehouse`
   bundle; the arrow/abseil/udunits group dropped after step 1 confirms it).

*Accept:* base closure materially smaller (buildInputs 57 → ~30);
`devtools::load_all()` on a package with C++ still compiles; `library(arrow)`
unchanged; duckdb/postgres reachable via the bundle.

### S4 — Hygiene (opportunistic)

`flake-parts.follows` on the four private inputs (F9, 11 → 7 lock nodes); root
`.envrc` with `use flake .#base` and delete `scripts/develop` (F8); merge
`overlays/{system,r-public}.nix` into `overlays/default.nix` (F11); re-home the
pandoc pin to `overlays/system.nix` (F10), where the removal-condition comment
style already lives.

### Targets

| Metric | S0 baseline | Target |
|---|---|---|
| hand-written `.nix` lines | 1442 (was 1146 before alejandra) | ~1050 |
| `modules/flake/opi.nix` | 231 | ~130 |
| `shells/base.nix` | 223 | ~110 |
| base `buildInputs` | 57 | ~30 |
| pkgs instantiations per consumer | 2 | 1 |
| lock nodes | 11 | 7 |
| files deleted | — | `lib/mkPackageShell.nix`, 3 bundle files, 2 overlay files, `templates/census`, `examples/base-direct`, `scripts/develop` (not `scripts/check-consumers`, which S0 added) |

**Out of scope for S0–S4:** the `flakes` → `nix` rename and the consumer sweep
(P3/P4). Do not rename any `openjusticeok` reference as a side effect.

## Remaining original work

| Item | Status |
|---|---|
| P0 internal refactor | **done** on `feat/all-in` (rv gone, one pin, module + overlays + 4 org packages). Deviations: `lib/rv-private.nix` never written (`r-private` was inlined into `overlays/default.nix`); `lib/mkRLibrary.nix` deliberately not written — redundant with the setup-hook mechanism, re-home under `packages/` only if a deploy artifact needs one library dir |
| P1 `packages/default.nix` + real build checks | missing. S0/S3 supply the build-side checks; org-local derivations still have no home |
| P2 Cachix + bump automation | missing: `nixConfig` advertises only `rstats-on-nix`; no org cache, no push step, no `lockFileMaintenance` — the `r-daily` pin never advances on its own (REVIEW R1) |
| P3 consumer migration | not started. `opi-flakes` → `opi`, `flakeModules.opi` → `flakeModules.default`, `layers` → `bundles`, drop rv files. Do the sweep when S1/S2 land so consumers move once |
| P4 rename `flakes` → `nix` | not started; last, post-review/merge |
| Docs | none: no README/DEVELOPMENT (also absent on `main`). Issues #35/#36 (adding a package mid-session; `install.packages()` soft error) are docs answers, not code |
| `x86_64-darwin` | unsupported; S2 makes the failure message honest |

## Bump process (monthly)

Renovate opens a PR bumping the `rstats-on-nix` ref (and private inputs) → CI
matrix builds all three platforms → push to Cachix → merge if green, skip if not.
Frozen deliverables never move unless their own lock is bumped.

## Risks

- **Consumer-facing churn from S1/S2.** The module owns `pkgs` and the API loses
  `layers`; both are breaking. Mitigation: S0 first, one old→new table, and fold
  the P3 sweep into the same window so consumers edit their flake once.
- **`positron-bin` unfree predicate moves into the module.** S1 widens it for
  every consumer; alternative is an explicit `opi.shells.<n>.positron = true`.
  Decide before S1.
- **Base-shell diet (S3) can break local C++ `load_all()`** against Arrow/DuckDB.
  Mitigation: measure first, keep the opt-in bundles for anyone who needs them.
- **Standalone-dev drift:** a package repo's `nix develop` uses its own pin; CI +
  Renovate mitigate; escalate to a shared pin flake only if it bites.
- **Fork bus factor / cache limits:** mitigated by the org Cachix; fallback to
  pinned `nixpkgs-unstable` + mirrored overrides.
- **`follows` discipline:** manual, one place (org `flake.nix`), easy to forget —
  as F9 shows.

## Verification

```sh
nix flake check                                    # builds the 4 eval checks
./scripts/check-consumers                          # 11 consumer cases
./scripts/check-consumers --locks                  # + example lock freshness
nix fmt -- --check .                               # alejandra
nix eval .#devShells.x86_64-linux --apply builtins.attrNames
nix develop .#base -c 'Rscript -e ".libPaths()"'
nix path-info -rSh .#devShells.x86_64-linux.base | tail -1   # S3 before/after
```

Path flake inputs are pinned by `narHash`: after any change here,
`examples/*/flake.lock` are stale. Prefer `--override-input opi path:…` when
testing a consumer, and re-lock the examples before committing.

## Doc map

| File | Holds |
|---|---|
| `PLAN.md` (this) | governing decisions, invariants, the active plan and its acceptance criteria |
| `REVIEW.md` | the `feat/all-in` review: what the rv→nix collapse changed, regressions vs `main`, issue triage |
| README (missing) | onboarding: direnv, why `install.packages()` fails, adding a package = a flake edit + shell re-entry |
