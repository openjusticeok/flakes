# Plan: `openjusticeok/flakes`

Status: the `rv` → nixpkgs-`rPackages` collapse (P0) has landed on `feat/all-in`
and is verified; **S0 (guardrails), S1 (one composition path), and S2 (option
surface) are done**. **S3 was rescoped** after measuring the shell — its original
hypothesis was wrong (see S3 and `ARCHITECTURE.md`). S4 and P1–P4 remain; rename
to `nix` stays the **last** step (post-review, post-merge).

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

Invariants 6–14 (images derived from the same declaration, digest-not-tag, no
dev-only weight in artifacts, no credentials, env parity, lock-as-reproducible-
unit, environment-agnostic artifacts, declared required env, CI-gated deploys)
are in `ARCHITECTURE.md` §6. They govern the artifacts this file's phases build.

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
- `examples/{project,module}` evaluate (`["default","shiny"]` /
  `["analysis","default","shiny"]`); `templates/{default,gis,shiny}` evaluate
  to `["default"]`.
- One nixpkgs pin; four private flakes as inputs; `overlays.default` exported and
  applied to the repo's own pkgs; `arrow` GCS/S3 override effective.
- **One package set and one composition path.** The module instantiates `pkgs`
  (overlaid) and `lib/mkOpiShell.nix` builds every shell from it — the repo's
  base shell, project shells, and `<pkg>-dev` shells alike.
- 2182 hand-written `.nix` lines (excl. locks), 12 lock nodes, base shell with 57
  `buildInputs` (34 system + the R set). Up from 1146 before alejandra expanded
  the tree; S0 added checks/fixtures/script, S1 moved the shell contract into
  `lib/`, S2 collapsed the option surface, P1 added the runtime closure and the
  image/push builders (`lib/{mkRenv,runtimeEnv,mkImage,pushImage}.nix` — ~800
  lines of new capability, which is why the S2 line count no longer describes
  today). `nix2container` is the 12th lock node, so S4's target becomes 8.
- **The module path is covered.** `nix flake check` builds 14 checks on
  x86_64-linux (13 elsewhere: `opi-env-loads-transitive-deps` is the one that
  builds the R closure and is Linux-scoped on purpose), and
  `scripts/check-consumers` evaluates 8 consumer cases (2 examples, 3 templates,
  one good and two bad module fixtures) plus packages/images, and example lock
  freshness — run by CI.
  Before S0 there was one `tryEval` check and no consumer evaluation at all.

## Where the complexity is

| Surface | Lines | Buys | Verdict |
|---|---|---|---|
| `modules/flake/opi.nix` | 231 (148 code) | the consumer API | over-built; two mechanisms removable |
| `shells/base.nix` | 223 | R + 34 system pkgs + a pandoc pin | over-provisioned; ~half unused |
| `lib/rPackages.nix` | 89 | CRAN-name resolver + suggestions | right-sized — leave alone |
| `overlays/` (3 files) | 71 | two overrides | split too thin |
| `shells/bundles/` (4 files) | 46 | 6 packages, 1 bundle unused | concept > payload |
| examples + templates | 7 flake.nix, 789 lock lines | documentation | 3 templates suffice; untested |

*(Line counts are the S0 baseline; the "Now" column of the targets table tracks
the reduction.)*

**F1 — Two owners produced the version-of-record `pkgs`.** *(fixed in S1)*
`flake.nix` instantiated nixpkgs with the overlay and the module *also* did
`pkgs.extend opi.overlays.default`, so a consumer's `pkgs` (what
`opi.shells.<n>.packages = [ pkgs.jq ]` resolved against) was unoverlaid while R
packages resolved against the overlaid set — two package sets per shell.

**F2 — The `passthru.shellEnv`/`shellHook` protocol was a hand-rolled inheritance
channel.** *(fixed in S1)* `inputsFrom = [ base ]` already carried `buildInputs`
and `shellHook`; the protocol existed only to smuggle `env`, at the cost of the
env being declared twice, the same guard appearing in two files, and three
"don't prepend the hook or it runs twice" comments.

**F3 — The option surface defined the same 4-field record twice, plus dead
aliases.** *(fixed in S2)* `entrySubmodule` and the shell submodule duplicated
`rPackages`/`packages`/`env`/`shellHook`; `opi.layers`,
`opi.shells.<n>.layers`, the `mkMerge` and the alias plumbing existed for
consumers that never shipped — `main` never had this API.

**F4 — Bundle machinery exceeded the bundles.** *(fixed in S2)* `geo` =
gdal+geos+proj; `shiny` = chromium+nodejs; `quarto` = chromium — **referenced by
nothing**. Four files, a registry import, and `mkDefault`-wrapping every `env`
value to ship 6 packages.

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

**F7 — Seven copies of the same consumer flake; `census` ⊂ `gis`.** *(fixed in
S2)* `templates/census`'s R set was a strict subset of `templates/gis`'s. All
seven copies said `systems = flakeExposed` while three platforms are supported,
so an unsupported host got the module's confusing "no `opi` input with a base
devShell" throw instead of "unsupported system". Templates also re-listed
base-standard packages (`targets`, `ggplot2`, `dplyr`), hiding what every opi
shell already provides.

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

### S1 — Collapse the shell contract — **done**

One composition path, three thin call sites, one package set.

- **`lib/mkOpiShell.nix` (new, 88 lines)** is the only way an opi shell is built:
  `{ pkgs, lib, name, rPackages, buildInputs, packages, env, shellHook }` → one
  `mkShell` that owns the org env (`R_HOME`, `FONTCONFIG_FILE`, `R_LIBS_USER =
  emptyDirectory`, `R_ENVIRON_USER`/`R_MAKEVARS_USER = /dev/null`), the readiness
  hook, and `QUARTO_R`, with R packages resolved onto `buildInputs` so R's setup
  hook fills `R_LIBS_SITE`. Extras are appended; nothing inherits.
- **`lib/baseEnvironment.nix` (new)** holds the org policy that used to be inline
  in `shells/base.nix`: the standard R set, the toolchain/native libraries, the
  interactive tools, the quarto + pandoc pin. Two files instead of one function
  mixing policy and mechanism.
- **`shells/base.nix` 223 → 18 lines**, `shells/private.nix` 29 → 32, and
  **`lib/mkPackageShell.nix` deleted** — the base shell, project shells, and
  `<pkg>-dev` shells are now three calls to the same function.
- **Deleted mechanisms:** `passthru.shellEnv`/`passthru.shellHook` and the
  doubled `env`/`shellHook` in the base shell; `inputsFrom` and the "don't
  prepend the hook" footgun; `pkgsOpi` (`pkgs.extend`); `defaultBase`; the
  `isOpiBase` guard (twice); `composeShell`; and the `opi.shells.<n>.base` option,
  which only existed to be wrapped. `checks/fixtures/bad-base` went with it.
- **The module now owns `pkgs`:** `config._module.args.pkgs = lib.mkDefault
  (import inputs.nixpkgs { overlays = [ versionOfRecord ]; …positron-bin; })`, and
  `flake.nix` no longer instantiates nixpkgs at all. flake-parts defaults `pkgs`
  with `mkOptionDefault`, so our `mkDefault` wins and a consumer that
  instantiates `pkgs` itself still can — and is then responsible for applying
  `opi.overlays.default` (documented in the module header).
- **New checks** encode the acceptance criteria at eval time:
  `opi-shell-contract` (R_HOME, the three immutability pins, `FONTCONFIG_FILE`,
  the `QUARTO_R` export), `opi-shell-one-arrow` (the base shell carries exactly
  one `arrow` and it is `pkgs.rPackages.arrow`), and `opi-shell-project-compose`
  (the same for a project-shaped shell **plus** its own `env` override surviving).

*Accept (met):* `nix flake check` → 6 checks; `scripts/check-consumers --locks`
→ 13 passed; `nix fmt -- --check .` clean; base `buildInputs` still 57.

*Deviations from the plan as written:*

1. `opi.shells.<n>.base` was deleted here rather than in S2 — it existed only to
   select what `composeShell` wrapped, and `mkOpiShell` always includes the org
   environment. S2 therefore only reuses the submodule and drops `layers`.
2. **`lib/orgPackageNames.nix` (new)** split the name list out of
   `lib/orgPackages.nix`. The guardrail caught this: a consumer does not have the
   org's private flakes as *its own* inputs, so `baseEnvironment` asking
   `orgPackages` for names threw "no flake input(s) for org package(s)" in every
   consumer. Names are static data and resolve through `pkgs.rPackages`; only the
   derivations need inputs. `mkOpiShell` consequently takes no `inputs`/`system`
   at all — just a `pkgs` that carries the overlay.
3. There is **no `pkgs.extend` fallback** for consumers who define `pkgs`
   themselves (the previous draft kept one). Two entry points to the overlay is
   how F1 happened; one owner plus a documented rule is the simpler invariant.

Line count is roughly flat (±15) because `baseEnvironment.nix` carries the same
comments forward — the win is conceptual and correctness, not text.

### S2 — Shrink the option surface — **done**

- **One submodule, not two copies.** `entrySubmodule` (packages / rPackages /
  env / shellHook) is imported by both `opi.bundles` and `opi.shells`, which adds
  only `name` and `bundles`. The duplicated 4-field block, its drift hazard, and
  the four divergent descriptions are gone. (The shell submodule still has to be
  a *function* so `attrsOf` can pass it the `name` special arg.)
- **`opi.layers` and `opi.shells.<n>.layers` deleted**, along with the `mkMerge`
  and the `config.bundles = config.layers` alias. `config.opi.bundles =
  shippedBundles` is now an ordinary definition, so a project's
  `opi.bundles.<name>` merges with the shipped ones without a merge combinator.
- **Bundles: 4 files → 1.** `geo` and `shiny` inlined into
  `shells/bundles/default.nix`; the never-referenced `quarto` bundle deleted. The
  `mkDefault` wrapper moved from the module into the bundle file, next to the
  value it protects (`env.PROJ_DATA = lib.mkDefault …`), so projects can still
  override a shipped env var without a module-level mapAttrs over every bundle.
- **`lib/packageNames.nix`** replaced `lib/orgPackageNames.nix` and carries both
  the standard R set and the org package names: one input-free data file for
  "which R packages the org ships", exported as `opi.lib.standardRPackages` so a
  template can list only its deltas.
- **`opi.lib.systems`** exports the three supported platforms; templates and
  examples use `inherit (opi.lib) systems;` instead of
  `nixpkgs.lib.systems.flakeExposed`, which made an unsupported host fail with a
  confusing module error rather than "unsupported system". That also removed the
  now-unused `nixpkgs` formal from every consumer flake.
- **Templates 4 → 3** (`census` was a strict subset of `gis`) and
  **`examples/base-direct` deleted** (three files and a 263-line lock to express
  `nix develop .#base`).

*Accept (met):* `modules/flake/opi.nix` 214 → 172 lines (~135 excluding the
module header); 3 templates and 2 examples, all CI-evaluated; `check-consumers`
→ 10 passed; `nix flake check` → 6 checks; hand-written `.nix` 1437 → 1355. The
old → new API table is under P3 in "Remaining original work".

*Deviation:* the `quarto` bundle had no user, so it left without a replacement —
chromium for `quarto preview` is one `packages = [ pkgs.chromium ]` line for a
project that wants it. If a second project needs it, it returns as a bundle then,
with someone to justify it.

### S3 — Right-size the base shell — **closed: measured, then rejected**

The original S3 assumed `arrow-cpp`/`abseil-cpp`/`udunits` were dead weight and
targeted "buildInputs 57 → ~30". **Measured (Oct 2026): that assumption is wrong.**
`devShells.x86_64-linux.base` is 10,898 MiB / 858 paths, and the marginal cost of
removing each candidate is:

| Candidate | Marginal saving | Reality |
|---|---|---|
| `arrow-cpp`, `abseil-cpp`, `udunits`, `rustc`, `libwebp`, `cairo`, `fontconfig` | **0 MiB** | already reachable through R packages (`r-arrow`, `sf`→`udunits`, `r-ragg` carries libwebp) |
| `positron-bin` | 3,153 MiB | IDE — dev only, but 29% of the shell |
| `postgresql` | 1,198 MiB | CLI convenience — dev only |
| `google-cloud-sdk` | 625 MiB | CLI / ADC plumbing |
| `duckdb` | 288 MiB | CLI convenience — dev only |
| `quarto` | 247 MiB | reporting; org-standard, keep |

The lesson is not "delete more", it is that **half the shell is dev-only tooling
that a deployment never needs** — so the fix belongs in the artifact model
(`ARCHITECTURE.md`), not in a smaller package list.

A role/layer taxonomy was drafted to express that and was **rejected as semantic
baggage** (six nouns, 65 packages to classify, fuzzy boundaries). The model
survives without it: there is one org environment; the runtime closure is defined
by *construction* (`mkRenv` = R + packages + env), so dev-only weight cannot
reach an image without anyone labelling anything; and the only genuine question —
"which few tools are optional?" — is what `opi.bundles` already expresses.

**Outcome: no package surgery at all.** Two follow-ups were considered and both
rejected:

1. **Bundling the opt-outs** (`postgresql` 1,198 MiB, `duckdb` 288 MiB,
   `google-cloud-sdk` 625 MiB, `positron-bin` 3,153 MiB) — rejected. It saves
   *local disk* only, because project CI enters the dev shell anyway
   (`r-ci`/`targets-ci` run `nix develop`), and local disk is not a constraint.
   `gcloud` also stays always-on: it is how an analyst obtains ADC and how
   `push-image` resolves a digest. Bundling would cost a breaking change in every
   shell that runs `psql`/`duckdb`/`positron .` and buy nothing measurable.
2. **Pruning the header/lib set** — rejected as pointless: 0 MiB marginal, and
   they are what makes a local C++ `devtools::load_all()` link.

So the org environment is unchanged. **The real lever is that CI should stop
entering the dev shell** — `nix build .#<name>-env -c tar_make()` instead of
`nix develop -c …` — which is the runtime closure (`ARCHITECTURE.md` §9 step 1,
§10), not a package-list edit. Both `arrow-cpp`/`abseil-cpp`/`udunits` and the
dev-only tooling stay exactly where they are.

*Accept (met by decision, not code):* no change to the closure; the measurement
that justified the decision is recorded in the table above and in
`ARCHITECTURE.md` §2a.

### S4 — Hygiene (opportunistic)

`flake-parts.follows` on the four private inputs (F9, 11 → 7 lock nodes); root
`.envrc` with `use flake .#base` and delete `scripts/develop` (F8); merge
`overlays/{system,r-public}.nix` into `overlays/default.nix` (F11); re-home the
pandoc pin to `overlays/system.nix` (F10), where the removal-condition comment
style already lives.

### Targets

| Metric | S0 baseline | Now (after S2) | Target |
|---|---|---|---|
| hand-written `.nix` lines | 1442 (was 1146 before alejandra) | 1355 at S2 (2182 today: P1 added the runtime/image builders) | ~1050 (superseded — the S-phases shrank composition, P1 added capability) |
| `modules/flake/opi.nix` | 231 | 172 (~135 + header) | ~130 |
| `shells/base.nix` | 223 | 18 | — |
| `lib/mkOpiShell.nix` + `lib/baseEnvironment.nix` | — | 262 | — |
| base `buildInputs` | 57 | 57 | 57 (measured: removing any single candidate saves 0 MiB) |
| pkgs instantiations per consumer | 2 | **1** | 1 |
| shell-composition mechanisms | 4 | **1** | 1 |
| bundle files | 4 | **1** | 1 |
| templates / examples | 4 / 3 | **3 / 2** | 3 / 2 |
| lock nodes | 11 | 11 | 8 (`nix2container` lands in P1; S4 then cuts the four private `nixpkgs` duplicates) |
| files deleted | — | `lib/mkPackageShell.nix`, `lib/orgPackageNames.nix`, `checks/fixtures/bad-base`, 3 bundle files, `templates/census`, `examples/base-direct` | 2 overlay files, `scripts/develop` (not `scripts/check-consumers`, added by S0) |

S1 was line-neutral by design: the mechanism it deleted (~70 lines of guards,
`composeShell`, `defaultBase`, `pkgsOpi`, passthru) reappears as ~100 lines of
explicit contract and comment in `lib/`. S2 is where the text actually fell. The
numbers that mattered most are the two conceptual ones: four ways to compose a
shell became one, and two package sets became one.

**Out of scope for S0–S4:** the `flakes` → `nix` rename and the consumer sweep
(P3/P4). Do not rename any `openjusticeok` reference as a side effect.

## Remaining original work

| Item | Status |
|---|---|
| P0 internal refactor | **done** on `feat/all-in` (rv gone, one pin, module + overlays + 4 org packages). Deviations: `lib/rv-private.nix` never written (`r-private` was inlined into `overlays/default.nix`); `lib/mkRLibrary.nix` deliberately not written — redundant with the setup-hook mechanism, re-home under `packages/` only if a deploy artifact needs one library dir |
| P1 runtime closure + images | **done**: runtime closure (`lib/mkRenv.nix`, `lib/rShellEnv.nix`, `lib/runtimeEnv.nix`, `packages.<name>-env`), images (`lib/mkImage.nix`, `lib/pushImage.nix`, `opi.images.<name>` → `<name>-image` + `<name>-push`). Measured 3,475 MiB / 578 paths vs 10,898 MiB / 858 for the dev shell — see `ARCHITECTURE.md` §2c. **Next:** the pilot — a Shiny dashboard on Cloud Run with `requiredEnv` + Secret Manager mounts |
| P2 Cachix + bump automation | missing: `nixConfig` advertises only `rstats-on-nix`; no org cache, no push step, no `lockFileMaintenance` — the `r-daily` pin never advances on its own (REVIEW R1) |
| P3 consumer migration | **table below**; the sweep itself is unstarted. Migrate when the API settles (after S3) so consumers edit their flake once. The four repos that call `actions/.../targets-ci.yml@v1` need it soonest: `demo-main-lockdown` and `demo-opi-project-template` still use `opi-flakes.base.devShells` (gone), `opi-project-template` and `youth-justice-listening-circles` still import `flakeModules.opi` (renamed `default`) and pass `layers` (gone). All four need a `flake.lock` bump, and the workflow change reaches them only when the `v1` tag moves |
| P4 rename `flakes` → `nix` | not started; last, post-review/merge |
| Docs | none: no README/DEVELOPMENT (also absent on `main`). Issues #35/#36 (adding a package mid-session; `install.packages()` soft error) are docs answers, not code |
| `x86_64-darwin` | unsupported; S2 makes the failure message honest |

### Consumer migration (P3)

Every consumer edits its `flake.nix` once. Nothing is shimmed — the retracted
spellings fail at the import line or as an unknown option, which is the intent.

| Old | New |
|---|---|
| `inputs.opi-flakes.url` | `inputs.opi.url` |
| `imports = [ opi.flakeModules.opi ]` | `imports = [ opi.flakeModules.default ]` |
| `opi.base.devShells.${system}.base` | `opi.devShells.${system}.base` — or drop it: shells already include the org environment |
| `opi.layers.<name>` | `opi.bundles.<name>` |
| `opi.shells.<n>.layers = [ … ]` | `opi.shells.<n>.bundles = [ … ]` |
| `opi.shells.<n>.base = …` | *removed* (S1) — there is one composition path |
| `systems = nixpkgs.lib.systems.flakeExposed` | `inherit (opi.lib) systems;` |
| `bundles = [ "quarto" ]` | `packages = [ pkgs.chromium ]` (the bundle was unused and is gone) |
| per-project `rproject.toml` / `rv.lock` / `.Rprofile` / `rv/` | delete; declare R packages in `opi.shells.<n>.rPackages` |
| `install.packages()` inside a session | edit `rPackages` and re-enter the shell (immutable by design) |
| `nix develop --command rv sync` / `rv run -e …` in CI | `nix build .#<shell>-env`, then `<path>/bin/Rscript -e …` (the `targets-ci.yml` workflow does this; `shell_name` input, default `default`) |

## Bump process (monthly)

Renovate opens a PR bumping the `rstats-on-nix` ref (and private inputs) → CI
matrix builds all three platforms → push to Cachix → merge if green, skip if not.
Frozen deliverables never move unless their own lock is bumped.

## Risks

- **Consumer-facing churn from S1/S2.** The module owns `pkgs` and the API lost
  `base` and `layers`; all three are breaking. Mitigation: S0 first, one
  old→new table (under P3), and the P3 sweep in a single window so consumers
  edit their flake once.
- **`positron-bin` unfree predicate lives in the module.** Decided: keep it —
  positron is the IDE and belongs in every shell. Revisit if a consumer needs to
  opt out (then `opi.shells.<n>.positron = true`).
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
