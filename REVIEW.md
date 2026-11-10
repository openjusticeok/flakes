# Review: `feat/all-in` vs `main`

Scope: `openjusticeok/flakes` branch `feat/all-in` (2 commits ahead of `main`:
`64071d4` refactor rv → nixpkgs `rPackages`, `349b2a1` wire private org packages)
plus the review work applied on top (uncommitted).

Status: the refactor is sound and its central bet — R packages from nix via R's
setup hook instead of `rv`/`rWrapper` — is verified working. What remains is
missing `PLAN.md` deliverables, deferred automation, and a handful of accepted
regressions.

```
 flake.nix               | 12 +-
 modules/flake/opi.nix   | 47 +++++++++-
 overlays/default.nix    | 14 +-
 overlays/r-private.nix  | 16 +-  (deleted)
 shells/base.nix         | 30 +++--
 shells/private.nix      |  4 +   (new)
 templates/gis/flake.nix | 11 +
 lib/orgPackages.nix     | new
 lib/mkPackageShell.nix  | new
 scripts/develop         | 100644 → 100755
 examples/*/flake.lock   | re-locked
```

---

## 1. Changes applied during review

| # | Change | Why |
|---|---|---|
| 1 | `lib/mkPackageShell.nix` (new) | base-contract dev shell for one org package; package repos cannot import it (input cycle), so the org repo owns it |
| 2 | `shells/private.nix` (new) | exposes `devShells.{ojodb,ojoregex,ojothemes,ojoutils}-dev` |
| 3 | `lib/orgPackages.nix` (new) | single source of truth for org package names; throws with the fix when an input is missing from the lock instead of silently dropping the package |
| 4 | `overlays/{default,r-private}.nix` | private packages inlined into `overlays/default.nix`; `r-private.nix` deleted — after (3) it was a 3-line pass-through over `lib/orgPackages.nix`, and the one `rPackages.override` it fed is where the "call it once" constraint actually lives |
| 5 | `shells/base.nix` | org names from (3) (no hardcoded drift); `R_ENVIRON_USER=/dev/null`, `R_MAKEVARS_USER=/dev/null` |
| 6 | `modules/flake/opi.nix` | `pkgsOpi = pkgs.extend opi.overlays.default` — resolve/compose against the version-of-record package set; deprecated `opi.layers` + `opi.shells.<n>.layers` aliases |
| 7 | `flake.nix` | **no** compat shims: `flakeModules.opi` and the custom `opi` output are purged; the sweep happens at merge, not after |
| 8 | `templates/gis/flake.nix` | restored 6 packages the rv-era template provisioned (`sfdep`, `freestiler`, `geoarrow`, `tidycensus`, `tigris`, `crsuggest`) — cf. R7 |
| 9 | `scripts/develop` | `+x` (was 0644, so `./scripts/develop` failed) |
| 10 | `examples/*/flake.lock` | re-locked; all three hard-errored before |
| 11 | `lib/rPackages.nix` | "did you mean" hints (PLAN invariant #4) via `lib.strings.levenshtein` + `lib.strings.commonPrefixLength`, scored in CRAN spelling — no hand-rolled edit distance |
| 12 | `overlays/system.nix` | jarl `doCheck = false` on darwin only (issue #34); the file was an empty stub |

Deliberately **not** kept: `flakeModules.opi` and `opi.base.devShells` are gone.
The old API now fails at the import line (`error: attribute 'opi' missing`),
which is the intent — consumers move to `flakeModules.default` when they merge.
Still present: `opi.layers` and `opi.shells.<n>.layers` as deprecated aliases for
`bundles` inside `modules/flake/opi.nix`; removing them is a small deletion if
they should go too.

### 1a. Resolver used the consumer's package set (fixed)

A project listing `"arrow"` got a second, unpatched arrow that sorted *ahead* of
the base shell's on `R_LIBS_SITE`, and `"ojodb"` was unresolvable. The module now
composes shells against `pkgs.extend opi.overlays.default`:

```
before:  R_LIBS_SITE = 0vqpcjpw…-r-arrow-24.0.0     ← plain, no GCS/S3
                       n1kjivx…-r-arrow-24.0.0      ← overridden (shadowed)
         rPackages = [ "ojodb" ] → error: unknown package(s): ojodb

after:   R_LIBS_SITE = n1kjivx…-r-arrow-24.0.0      ← one copy, the overridden one
         rPackages = [ "ojodb" "ojoregex" "arrow" "data.table" ] → exit 0
```

### 1b. R's user config (fixed)

`R_ENVIRON_USER=/dev/null` and `R_MAKEVARS_USER=/dev/null` are now in
`shellEnv`, so they reach base, project, and `<pkg>-dev` shells. `~/.Renviron` can
no longer reset `R_LIBS_USER` past the `emptyDirectory` pin (PLAN invariant #3),
and `~/.R/Makevars` can no longer inject flags into `devtools::load_all()`
compiles.

---

## 2. Present and verified

**Wiring.** One flake, one nixpkgs pin (`rstats-on-nix/nixpkgs/r-daily`),
flake-parts, `x86_64-linux` / `aarch64-linux` / `aarch64-darwin`.
`nix flake check` → *all checks passed*.

**Outputs.** `devShells.{base,default,ojodb-dev,ojoregex-dev,ojothemes-dev,ojoutils-dev}`,
`flakeModules.default`, `overlays.default` (+ `system` / `r-public`),
`checks` (1), `templates` (4). No deprecated aliases.

**R environment.** `R_LIBS_SITE` populated by R's setup hook from `buildInputs`
(no rWrapper, no rv, no `.Rprofile`), `R_LIBS_USER=<empty-directory>`, `R_HOME`,
`FONTCONFIG_FILE`, `QUARTO_R` via the propagated base `shellHook`,
`R_ENVIRON_USER` / `R_MAKEVARS_USER=/dev/null`.

**Private packages.** 4 self-contained flakes consumed as inputs with
`nixpkgs.follows`, injected into `pkgs.rPackages`; all expose
`packages.<system>.<name>`; the base shell's standard set includes them; consumers
can request them by name.

**Version-of-record.** `overlays.default` applied to the repo's own pkgs *and* to
consumer shells; the `arrow` GCS/S3 override takes effect in both.

**Composition contract.** Base `passthru.shellEnv` / `shellHook` honored by the
module and by `mkPackageShell`; bundle `env` / `packages` / `rPackages` /
`shellHook` merge in listed order; guards fail loudly for a non-opi base, unknown
bundle, unknown R name, and missing org input.

**Repo hygiene.** No `rv` / `rproject.toml` / `rv.lock` / `activate.R` / `layers`
/ `opi-flakes` references anywhere (grep-clean). `renovate.json`, `checks.yml`,
`scripts/develop`, 3 working examples, 4 templates on the new API.

---

## 3. Still missing vs `PLAN.md`

| Item | Status |
|---|---|
| P0 #8 `lib/mkRLibrary.nix` | deliberately not written — redundant with the setup-hook mechanism; re-home under `packages/` in P1 if a deploy artifact needs one library dir |
| P1 `packages/default.nix` | missing (org-local derivations) |
| P1 checks: shell smoke test, representative build | missing — only the resolver sanity check. No CI changes were made by request, so **nothing builds an R package in CI**; `nix flake check` only evaluates. It also does not exercise failure paths: during this review a broken hint path (wrong `lib` attribute) passed `flake check` and only failed on a deliberate typo test |
| P2 Cachix | missing: `nixConfig` has `rstats-on-nix` only; no org cache, no push step |
| Bump process | missing: no `lockFileMaintenance`, no `nix flake update` workflow → the `r-daily` pin never advances on its own |
| P3 consumer migration | not started (the shims buy the window) |
| P4 rename `flakes` → `nix` | not started |
| Docs | no README / DEVELOPMENT at all (also absent on `main`) |
| `formatter` output | absent (also absent on `main`) |

---

## 4. Remaining regressions vs `main`

| # | Regression | Severity | Note |
|---|---|---|---|
| R1 | **No pin-bump automation.** `update-flake-lock.yml` and `update-base-tools.yml` deleted; `renovate.json` has no `lockFileMaintenance`, and Renovate cannot advance a branch-pinned input today (ref updates are still an open upstream PR) | high over time | deliberate deferral; the pin silently ages |
| R2 | **Tool versions ride nixpkgs.** No `tools.json`; `arf` / `jarl` / `air-formatter` come from nixpkgs (arf 0.6.0, air 0.12.0, jarl 0.6.0-unstable) — no escape hatch if nixpkgs lags | medium | acceptable; the old machinery was ~130 lines |
| R3 | **`rv` escape hatch gone** — no sanctioned way to add an R package absent from `pkgs.rPackages` | medium | intentional per PLAN; undocumented |
| R4 | **`x86_64-darwin` unsupported**; templates/examples still declare `systems = flakeExposed`, so an unsupported host fails with the module's "no `opi` input with a base devShell" throw rather than "flake does not provide this system" | low | one-line fix in 7 files, not done |
| R5 | **Template `flake.lock`s removed** → `nix flake init -t` no longer yields a pre-pinned project | low | arguably better than stale pins |
| R6 | **Positron interpreter pin removed** from `templates/default/.vscode/settings.json` (`positron.r.interpreters.default`) | low | consistent with "launch Positron from the shell", undocumented |
| R7 | **gis template content** was missing `sfdep` / `freestiler` / `geoarrow` / `tidycensus` / `tigris` / `crsuggest` that `main`'s `rproject.toml` provisioned (all present in nixpkgs) | fixed | |
| R8 | **geo bundle no longer exports `PKG_CONFIG_PATH` / `-rpath`** | accepted | nix-built packages carry their own deps; local source builds are blocked by immutability |
| R9 | Input alias `opi-flakes` → `opi` cannot be shimmed, and the module path/output renames are unshimmed by choice; every consumer edits its `flake.nix` at merge | low | deliberate: sweep at merge |

---

## 5. Advancements over `main`

- **One pin, one flake**: `main` had a nested `base` flake with its own nixpkgs
  (`nixos-26.05` vs the org's); now everything shares `rstats-on-nix`.
- **Fresh R**: R 4.6.1 with CRAN builds from the pinned channel, instead of rv
  installing into `$PWD/rv/library` per project.
- **Immutable by construction**: no writable R library, no rv seam, no `.Rprofile`
  activation; `R_LIBS_USER` is a read-only empty store path.
- **No rWrapper shim** → Positron's in-process `ark` shares R and glibc with the
  shell.
- **Org packages are real Nix derivations** in `pkgs.rPackages` (cacheable,
  reproducible, `R CMD check`-able), not git-installed from GitHub branches on
  every project activate.
- **Resolvable by name**: projects can name `"arrow"` / `"ojodb"` and get the
  version-of-record build; on `main` deps lived in per-project `rproject.toml`
  with `packages_env_vars` copied around.
- **Per-package dev shells** (`<pkg>-dev`) — new; package repos previously
  hand-rolled shells with no base environment.
- **Loud failure modes**: unknown R name, unknown bundle, non-opi base, missing
  org input (with the re-lock command).
- **Renamed API, deliberately breaking**: `flakeModules.default`, `opi.bundles`,
  `opi.shells.<n>.rPackages`; no compat shims, so the migration is explicit
  rather than silently deferred. `nix flake check` is also warning-free now.
- **Real CI**: 3-platform `nix flake check` matrix (was one platform) — still
  eval-only.

---

## 6. Verification log

```
nix flake check --no-build                 → all checks passed!  (6 devShells evaluated)
devShells.x86_64-linux                     → [base, default, ojodb-dev, ojoregex-dev, ojothemes-dev, ojoutils-dev]
examples/{project,module,base-direct}      → ["default","shiny"] / ["analysis","default","shiny"] / ["default"]
new-API consumer, rPackages=[ojodb,ojoregex,arrow,data.table] → exit 0; single overlaid arrow
old-API consumer (flakeModules.opi, opi.layers, layers=[geo,analysis], opi.base.devShells)
                                           → ["default","oldbase"], PROJ_DATA set, jq+richgo on PATH
templates/gis (path-overridden copy)       → devShells.default drvPath resolves (15 R packages)
base / ojodb-dev / project shell           → R_ENVIRON_USER=/dev/null, R_MAKEVARS_USER=/dev/null,
                                             R_LIBS_USER=<empty-directory>
stale-lock guard                           → "opi: no flake input(s) for org package(s): ojoregex, ojothemes …
                                             re-lock the opi input"
```

---

## 7. Operational gotcha: stale path inputs

Path flake inputs are pinned in `flake.lock` by **narHash**. A consumer test
"failed" during this review because it was evaluating a snapshot of the repo from
before the fix — silently.

- After any change in this repo, `examples/*/flake.lock` are stale and must be
  re-locked (`nix flake update opi`). It was done three times during this review.
  `nix develop` run inside the example picks it up; `--no-write-lock-file` /
  `--locked` (CI) does not.
- When testing an org-repo change from a consumer, prefer
  `--override-input opi path:…`, which always copies fresh.
- This is the same class of failure as the original example breakage — the one
  thing a CI job would catch (noted, not added).

---

## 8. Suggested next steps, in order

1. **R4** — pin templates/examples to the three supported systems (7 one-line
   edits).
2. **Docs** — a README that answers issues #35/#36/#37: package changes are flake
   changes (direnv reloads), `install.packages()` is *meant* to fail, and
   `nix-direnv` comes from `nix profile install nixpkgs#nix-direnv`.
3. **Decide #38** — how consumers get the private cache (`okpolicy` Cachix):
   per-flake `extra-substituters` (needs auth), machine-level `nix.conf`, or CLI
   probe. Today the flake advertises only `rstats-on-nix`.
4. **`packages/default.nix`** + a deploy-shaped R library derivation (where
   `mkRLibrary` belongs if it is ever needed).
5. **Cachix + a check that builds** `arrow` / `ojodb`, so the CI matrix means
   something.
6. **Bump automation** (`lockFileMaintenance` or a `nix flake update` workflow) —
   R1 is the regression that grows worse every month.
7. **P3 sweep** — consumers move to `flakeModules.default` when they merge (no
   shims), then **P4 rename** `flakes` → `nix`.

---

## 9. GitHub issues triage

Open at review time: #25, #27, #33, #34, #35, #36, #37, #38 (closed: #1, #4).

| # | Title | Verdict |
|---|---|---|
| #25 | fix: consider how rv scripts are included | **Obsolete / red herring.** `rv` is gone (no `rv/`, `rv.lock`, `rproject.toml`, `activate.R` anywhere). Close; the linked `opi-project-template` issue belongs to old projects. |
| #27 | fix: rv cache for nix needs to be isolated | **Obsolete / red herring.** Root cause was rv sharing one cache between nix R and rig/CRAN R. No rv → no shared cache. Close; may still apply to projects mid-migration. |
| #33 | (bug) stale tracked flake.lock in examples/project | **Valid, reproduced, FIXED** (re-locked all three examples). Answer to its open question: *regenerate and commit* for examples — their lock pins the org snapshot by `narHash`, and a lockless example re-resolves silently; *ship no lock* for templates, which are meant to resolve fresh (`flake init`). |
| #34 | (mac-fatal-ish) jarl 0.6.0-unstable × darwin | **Valid, still broken, FIXED** with the issue's own workaround, scoped to darwin (`overlays/system.nix` — the file the refactor added empty for exactly this). The check passes on Linux. Remove once nixpkgs carries the upstream fix. |
| #35 | (fix-ish) adding package/library mid R session | **Valid but by design.** Immutability (PLAN #3) means the R library is a store path; adding a package is a flake edit and direnv re-enters the shell. The workaround (shelling out to `nix develop` from inside R to read `R_LIBS_SITE`) is a red herring — it re-evaluates the flake recursively. Needs a docs answer, not an overlay. |
| #36 | (bug) install.packages() soft error message | **Author already marked `(disregard for now)`.** Real sharp edge: the `emptyDirectory` pin produces R's raw "lib is not writable". Same docs fix as #35. |
| #37 | (notes) nix-direnv must be installed via nix | **Valid; onboarding/docs gap, not a repo bug.** The "better fix" (shellHook env probe) and "best fix" (CLI orchestration) are P3+ CLI work. |
| #38 | (silent, expensive) accept-flake-config + org cache skipped | **Half stale premise, half open.** The issue says "the flake ships the okpolicy cache in nixConfig" — it does **not**; `nixConfig` advertises only `rstats-on-nix`. CI already sets `accept-flake-config = true`, so CI is not silently skipping. What remains true: direnv's `nix print-dev-env` drops untrusted flake settings, and the private `okpolicy` cache does not exist yet anywhere (nothing is pushed — P2). Needs the #38 decision, after P2. |
| #1 | `{ragg}` depends on `libwebp` (closed) | Still satisfied: `libwebp` is in the base shell's dependency list. |
| #4 | udunits/udunits2 needed for `{units}` (closed) | Still satisfied: `udunits` is in the base shell's dependency list. |

Net: two issues are dead (rv), one is the bug this review fixed, one is a real
macOS blocker now worked around, four are documentation or deferred decisions.

---

## 10. Org docs vs this repo (from the `okpolicy` skill)

The skill's `references/infrastructure.md` documents the target state; two claims
did not match the branch and are worth closing as code, not prose:

| Doc says | Reality on the branch | Action |
|---|---|---|
| "the resolver throws with nearest matches on an unknown name" | it listed names but offered no matches | **fixed** (change #11) |
| "Cachix cache named `okpolicy` (private); CI pushes with `CACHIX_AUTH_TOKEN`" | no org cache in `nixConfig`, no `cachix-action` in CI | P2 |
| "projects follow it as `opi-flakes` / `opi`" | `.default` / `opi` only; no shim, so old consumers fail at the import line | P3 (sweep at merge) |
| "one nixpkgs pin, bumped monthly on green" | one pin ✓, no bump automation (R1) | see §4 |
| "`opi.shells` layered on base, shared sets via `opi.bundles`, R via `R_LIBS_SITE`" | matches exactly | — |
| repo rename `flakes` → `nix`, org `openjusticeok` → `okpolicy` in flight | branch still `openjusticeok/flakes` | P4, and **do not rename as a side effect** |

---

# Review round 2 — after S2, the runtime closure, images, and CI

Round 1 above covers `feat/all-in` before the phase work. This round reviews the
tree as committed at `099b486`: S0–S2, `packages.<name>-env`, `mkImage`/
`pushImage`, and the `targets-ci` change. Method: read every file under `lib/`,
`shells/`, `modules/`, `checks/`, `flake.nix`; ran the four gates; re-measured
the claims in `PLAN.md`/`ARCHITECTURE.md`; ran the commands each invariant
implies. Nothing here is inferred from the docs.

## 11. Must fix

**Status after review feedback: F1 and F2 are fixed; F3 is downgraded to a wording
fix (done) because step 3 is the implementation. Corrections to this section are
kept inline rather than rewritten, so the review's errors stay visible.**

| # | Finding | Evidence | Fix |
|---|---|---|---|
| F1 ✅ | **`nix flake check` built the whole R runtime closure on all three platforms** — while `checks/default.nix`'s header said it "builds nothing" and that R-package builds "belong behind the Cachix push". *(Correction: my claim that "P2 does not exist" was wrong — the `okpolicy` cache exists and `r-ci.yml`/`targets-ci.yml` both use it. What is missing is narrower: this repo's own `checks.yml` has no `cachix-action`, and `flake.nix`'s `nixConfig` advertises only `rstats-on-nix`.)* | `nix eval .#checks.aarch64-darwin` included `opi-env-loads-transitive-deps` | **Done**: the check is now `lib.optionalAttrs (system == "x86_64-linux")`, so it runs 14 checks on x86_64-linux and 13 elsewhere; the header states the policy and why. Cachix subscription stays a pre-finalization task |
| F2 ✅ | **Invariant 10 was false for `QUARTO_R`.** It was exported from `mkOpiShell`'s shellHook (`export QUARTO_R="$(which R)"`), which an image never runs; `lib/rShellEnv.nix` — the shared env — did not contain it, and invariant 10 listed it as inherited | `grep -rn QUARTO_R lib shells modules` → only mkOpiShell + the check | **Done**: `QUARTO_R = "${pkgs.R}/bin/R"` now lives in `rShellEnv`, so shells and images share it by construction; `opi-shell-contract` asserts the env attribute and `opi-env-contract` asserts the image's, instead of grepping a hook |
| F3 ✅ (doc) | Two invariants are written as shipped but are not implemented: inv 13's declaration half (the flake reads the CLI's config file) and inv 14's CI-only gate. The v3 status said the image/CI half is implemented | module options `requiredEnv`; no image workflow | **Done as wording**: the status paragraph now names both as *half*-enforced and points at §9 step 3. Implementing them is step 3, not a review fix |

## 12. Doc vs reality drift

| # | Claim | Reality | Note |
|---|---|---|---|
| F4 ✅ | PLAN: "1355 hand-written `.nix` lines", "`nix flake check` → 6 checks" | 2,182 `.nix` lines (+179 shell); **14** checks on x86_64-linux, 13 elsewhere | **Done**: current-state bullets and the targets table now say both, and mark the old figure as the S2 snapshot |
| F5 ✅ | ARCHITECTURE inv 11: provenance is "source revision + **lock hash**" | shipped label is `org.openjusticeok.source` = flake *source* hash (covers the lock) | **Done**: inv 11 now says source hash and why (untracked consumer locks) |
| F6 ✅ | `flake.nix`: `opi.lib.standardRPackages` is "what every opi shell already provides" | every shell provides `names.standard ++ names.org` | **Done**: the comment says two halves and `opi.lib.orgRPackages` is exported alongside |
| F7 ⚠️ | REVIEW.md R1 ("no pin-bump automation… silently ages") and R4/R9 | R4/R9 are **done** (templates use `opi.lib.systems`, `flakeModules.default`, `opi.shells`); R1 stands: no bump automation, and the org cache is not a substituter in `nixConfig` | round-1 statuses still need re-triage; the cache part is pre-finalization, not design |

## 13. Should fix

| # | Finding | Evidence |
|---|---|---|
| F8 | **No check covers `<pkg>-dev` shells** (`shells/private.nix`) — the only shells the module does not build. Verified by hand that `ojodb-dev` has `ojodb` on `R_LIBS_SITE` and loads, but nothing guards a regression |
| F9 | `shells/private.nix` puts the package in `packages = [package]` (→ `nativeBuildInputs`) while every other shell uses `rPackages`. It works because R's hook (`addEnvHooks … addRLibPath`) covers both, but the comment attributes it to `propagatedBuildInputs`, which is not the mechanism |
| F10 | `opi.images` cannot set `user`, `workingDir`, or custom `labels`, though `mkImage` accepts them — a consumer has no way to reach them without importing the lib file out of the opi store path |
| F11 | The repo has no root `.envrc` although all three templates ship one (S4 item). The org's own checkout is the one place `direnv` does not work |
| F12 | `readinessHook` runs five subprocesses (`air`/`arf`/`jarl`/`quarto --version`, `which R` twice) on **every** shell entry, including CI's `nix develop` |

## 14. Invariant enforcement

| Inv | Enforced by | Status |
|---|---|---|
| 1–2 (one pin, no `rv`) | flake inputs, `nix flake check` | ✓ structural |
| 3 (immutable R library) | `rShellEnv` pins + `opi-shell-contract` | ✓ |
| 4 (actionable failures) | `opi-resolver-{unknown-throws,suggests}`, bad-* fixtures | ✓ |
| 5 (cache retention) | — | policy only |
| 6 (image from the same declaration) | `opi.images.shell`, `opi-image-config` | ✓ for `shell` users; `shell = null` is the documented escape hatch |
| 7 (digest, never a tag) | `pushImage` pins `@sha256:` | ✓ in the helper; nothing verifies tfvars |
| 8 (no dev weight in images) | `opi-env-runtime-only`; `contents` by construction | ✓ |
| 9 (no credentials) | — | policy only |
| 10 (image inherits shell env) | `renv.env` (from `rShellEnv`), `opi-env-contract` | ✓ — `QUARTO_R` included since F2's fix |
| 11 (`flake.lock` is the unit) | labels `revision` + `source` | ✓ |
| 12 (environment-agnostic) | — | policy only |
| 13 (declare env, fail at boot) | `opi-image-guard` (runtime half) | **half** — see F3 |
| 14 (prod from CI, labelled) | labels | **half** — see F3 |

## 15. Gates

`nix flake check` all passed (14 checks on x86_64-linux, 13 on aarch64-linux and
        aarch64-darwin) · `nix fmt -- --check .` clean ·
`./scripts/check-consumers` 8/8 · `actionlint` clean on the actions repo ·

*(Round-3 snapshot. Current: 15 checks on x86_64-linux, 14 elsewhere, and
`check-consumers` 12/12 — the new `opi-private-dev-shells` check and
`examples/image` are §17's.)*
runtime closure 3,475 MiB / 578 paths vs dev shell 10,898 MiB / 858.

## 16. Next, in order

1. ~~F1, F2~~ **done** — the build check is Linux-scoped and `QUARTO_R` moved into
   `rShellEnv` (shells and images now share it).
2. **Cachix, pre-finalization** — subscribe `okpolicy` in `flake.nix`'s
   `nixConfig` and add `cachix-action` where `checks.yml` has its `# P2`
   placeholder. The cache exists and the shared workflows already use it; this is
   wiring, not design.
3. **F3 = step 3** — the pilot: `requiredEnv` read from the CLI config file,
   Secret Manager mounts, and the CI-only deploy gate. The only real capability
   gap left in the model.
4. **F7** — re-triage REVIEW.md's round-1 items (R4/R9 are done; R1 stands).
5. **F8–F12** — opportunistic; F8 (no check covers `<pkg>-dev` shells) is the one
   with real risk behind it.

## 17. Findings from building the first real image (step-3 groundwork)

`examples/image` (a Shiny app: shell + `opi.images.dashboard` + push app) is now
in the tree, and building and running it found three bugs that no eval-time check
had caught — all in code merged before this round.

| # | Finding | Evidence | Status |
|---|---|---|---|
| F13 | **`copyToRoot` flattens the closure.** The module passed `renv.paths` (578 store paths) as image contents, which unpacks them all at `/`: every package's `nix-support/propagated-build-inputs` collides (nix2container: *"the file … already exists in the graph"*), and R moves off the store path `R_LIBS_SITE` names. | `nix build .#dashboard-image` failed in `layers.json` | **fixed**: the module copies `[renv.package]` (the wrapper → `/bin`), so R and its packages arrive as dependencies at their store paths; `mkRenv.paths` removed (it invited the mistake) |
| F14 | **`apps.<n>-push` was a bare derivation**, which flake-parts rejects when forced. Invisible because `check-consumers` and `nix flake check` only looked at attribute *names* — `nix run .#dashboard-push` was the first thing to force the value. | `error: The option 'perSystem.…apps.dashboard-push.NIX_MAIN_PROGRAM' does not exist` | **fixed**: emitted as `{ type = "app"; program = …; }` |
| F15 | **The example itself was wrong in an instructive way**: the `shiny` bundle is tooling (chromium/node), so listing only `bslib` built a valid image whose entrypoint would die with *"there is no package called 'shiny'"*. | running the runtime closure: `HTTP 200` only after adding `"shiny"` to `rPackages` | **fixed** in the example, with a comment; this is the class of bug `requiredEnv` cannot catch, hence "run the pilot, don't just build it" |

Verified for the example: image builds (15 s), manifest carries
`Entrypoint = ["/bin/Rscript" "-e" …]`, `User = 1000:1000`, `WorkingDir = /`,
`ExposedPorts = 8080/tcp`, 7 env vars including `PATH`/`QUARTO_R`/`R_HOME`, and
`org.openjusticeok.source = <store-hash>-source`; `app.R` and the wrapper are
rewritten to `/app.R` and `/bin`; the app serves HTTP 200 from the runtime
closure; `nix run .#dashboard-push -- --dry-run` prints target, current pin, and
what it would pin.

Also closed this round: **F8** (new check `opi-private-dev-shells`, 15 checks on
x86_64-linux), **F10** (`opi.images` gained `user`, `workingDir`, `labels`),
**F11** (root `.envrc`; `scripts/develop` deleted — its premise, private flakes not
being published, has been false for a while).

*Correction to F14's first appearance:* the example's `flakeModules.default` import
was briefly written as `flakeModule.default` — an attribute typo that fails only at
evaluation, which is why examples stay in `check-consumers`.
