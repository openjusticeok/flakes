# Architecture: environments, capabilities, and deployables

Status: **settled (v2)**. The axes (§2), declaration (§3), deploy contract (§4),
roles (§5) and invariants (§6) are decided and buildable against. The image/CI
half of the model is not implemented yet — §9 gives the order. Open items are
reduced to triggers (§8).

v2 changes from v1: the env/secret contract lives in the CLI config file and the
flake reads it (inv 13); prod deploys are **gated by CI** but provenance is
**labels only** — signing deferred with a stated trigger (inv 14);
`packages.<name>-env` is decided, not proposed; entrypoints stay per-project;
secrets arrive as Secret Manager volumes; Cachix keeps everything for now; and
the pilot image is a Shiny dashboard already on Cloud Run (§8, §9).

v1 changes from v0, driven by review: **layers are gone from the vocabulary**
(they were a partition pretending to be needed); **CI is not a materialization**
(empirically it is `dev` minus the IDE); and the "things R packages don't carry"
question was measured — the answer is *fonts via env*, not libraries (§2).

Companion documents: `PLAN.md` (decisions, invariants 1–5, phase plan) and
`REVIEW.md` (the `rv` → nix collapse). This file answers a question PLAN does
not: **how do dev shells, capabilities, and production artifacts relate, when
they all come from one flake?**

---

## 1. What this flake is

A version-of-record for the org:

- the **R package set** (public CRAN/Bioconductor via `rstats-on-nix` + the org's
  own packages), resolved by CRAN name;
- the **dev environment** every project works in;
- and the **deployable artifacts** that should come from the same declarations
  rather than a parallel hand-maintained stack.

Non-goals: not an application framework, not a deploy tool, and it does not own
GCP infrastructure (that is `openjusticeok/infrastructure`, with `tofu`).

## 2. The problem: three axes collapsed into one list

Today every package lives in one flat list ("the org environment") and the only
artifact shape we produce is a `devShell`. That conflates three independent
questions:

| Axis | Question | Carrier |
|---|---|---|
| **Capability** | what can this environment *do*? (geo, shiny, warehouse, gcp, render) | `opi.bundles` |
| **Project** | which named environments does one repo have? | `opi.shells` |
| **Lifecycle** | is this what you *work in*, or what *runs in prod*? | **was missing** — everything was a devShell |

### 2a. The measurement that proves the conflation

`devShells.x86_64-linux.base` (Oct 2026, `nix path-info -rSh`): **10,898 MiB
across 858 store paths**. Marginal cost of each candidate (union of the inputs
*without* it, subtracted from the total):

| Removed | Marginal saving | Role |
|---|---|---|
| `positron-bin` | 3,153 MiB (29%) | IDE — dev only |
| `postgresql` | 1,198 MiB (11%) | CLI convenience — dev only |
| `google-cloud-sdk` | 625 MiB (6%) | CLI / ADC plumbing — dev & ops |
| `duckdb` | 288 MiB (3%) | CLI convenience — dev only |
| `quarto` | 247 MiB | reporting |
| `cargo` | 38 MiB | native build |
| `arrow-cpp`, `abseil-cpp`, `udunits`, `rustc`, `libwebp`, `cairo`, `fontconfig` | **0 MiB** | already reachable via R packages |

Half the shell (5.2 GiB) is dev-only tooling with no bearing on a deployment, so
it must not be reasoned about in the same breath. And removing
`arrow-cpp`/`abseil-cpp`/`udunits` saves *nothing* — they stay reachable through
`r-arrow` (`ARROW_USE_PKG_CONFIG=true`), `r-ojoutils`→`sf`→`udunits`, etc. PLAN's
original S3 hypothesis ("base 57 → ~30 inputs") was measured and is wrong.

### 2b. What R packages genuinely do not carry: **fonts, via env**

Measured on `r-ragg` 1.5.2 (the graphics device behind most org plots):

- its closure carries `libwebp`, `libtiff`, `libjpeg-turbo`, `libpng`,
  `freetype`, `harfbuzz`, `fontconfig`, and **`dejavu-fonts-minimal`**;
- it does **not** carry the org font. Source Sans 3 reaches R only through
  `FONTCONFIG_FILE` (a `fonts.conf` in the shell's `env`).

So the dev/prod divergence risk is not a missing library, it is **an image that
forgets the shell's env**: same R packages, different glyphs, silent. This is why
invariant 10 exists.

### 2c. What the runtime closure measured

`packages.base-env` (`lib/mkRenv.nix`), built from the same declaration as
`devShells.base`:

| Artifact | Size | Paths |
|---|---|---|
| `devShells.base` | 10,898 MiB | 858 |
| `packages.base-env` | **3,475 MiB** | 577 |

Dev-only weight = **7,423 MiB (68%) that a process never needs**. Invariant 8 is
now verified rather than asserted: the runtime closure is smaller because
Positron, the toolchain and the CLI tools are not inputs — not because a list
filtered them.

Where the remaining 3,475 MiB goes (own size of the largest paths):

| Path | Size | Why it is there |
|---|---|---|
| `openjdk` | 572 MiB | referenced by nixpkgs' R itself |
| `gfortran` + `gcc` | 615 MiB | R's `Makeconf` references the compilers |
| `lapack` | 67 MiB | R |
| `pandoc-cli` + `quarto` + `deno` + `python3` | 576 MiB | arrived through the `rmarkdown`/`knitr`/`quarto` R packages |
| `google-cloud-cpp` + `arrow-cpp` | 177 MiB | the org `arrow` GCS/S3 override (`ARROW_USE_PKG_CONFIG`, non-minimal build) |

Two consequences to know before building an image:

1. **Most of the runtime closure is R's own dependency tree, not our choices.**
   ~1.25 GiB is Java, compilers and lapack that R references. A leaner image is
   possible later (an `R.override` without Java, or a striped R) — a separate
   decision, not a bug.
2. **The org standard R set is an analyst set, not a minimal one.** `rmarkdown`,
   `knitr` and their 576 MiB of pandoc/quarto/deno land in every runtime
   closure. A service that never renders a document should declare a smaller
   `rPackages` list — which the model already allows, because the runtime closure
   is derived per shell entry.

## 3. One declaration, several artifacts

A project declares its environments once:

```nix
opi.shells.default = {
  bundles = ["geo" "warehouse"];
  rPackages = ["sf" "tidycensus"];
  packages = [pkgs.jq];
  env.R_MAX_VSIZE = "32Gb";
};
```

Everything else is a **materialization** of that declaration; the shape is
decided by the output, never by a second package list.

| Materialization | Audience | Contents | Status |
|---|---|---|---|
| `devShells.<name>` | a human at a keyboard | everything: R + R packages + build + IDE + reporting + declared capability CLIs | **shipped** (`lib/mkOpiShell.nix`) |
| `packages.<name>-image` | Cloud Run / container host | R + R packages + **the shell's `env`** + declared image extras (assets, entrypoint); **environment-agnostic** | **not built** (§4, §7) |
| CI | `r-ci.yml`, `targets-ci.yml` | **= dev minus the IDE** — not a third shape | **decided, no mechanism needed yet** |
| `packages.<name>-env` | a CI job, or an image's contents | the runtime closure alone: R + R packages + `env`. No IDE, no compilers, no `ops` CLIs, no docker needed | **shipped** (`lib/mkRenv.nix`) |
| nothing | a scratch or docs-only repo | — | allowed |

**CI is a subtraction, not a materialization.** Review finding: nothing *must* be
in CI but not in dev; the only item that must not be in CI is the IDE (3.1 GiB of
Positron), and nearly everything else must be in CI *because checks run there*
(`air`, `jarl`, `git`, quarto for render checks). So CI needs no new artifact —
at most an exclusion switch, and only if the bandwidth actually hurts.

**Images are 0..N per project, gated on content.** One is the default; zero is
legitimate (a pure dev-shell repo); more than one is legitimate only when the
*contents* diverge materially — a Rust binary and a Shiny app in the same repo, or
a Shiny app and a `targets` pipeline whose package closure differs. Differing
*commands* are `args`, never a second image (see §4).

**And every image is environment-agnostic.** The same artifact runs in staging
and in prod; which environment it is talking to is injected as env vars at deploy
time and authorized by IAM (a developer does not hold prod permissions). So there
is no "staging image", no rebuild per environment, and no baked credential or
prod hostname — invariant 12.

**A pipeline may never need an image at all.** Pipelines are image-shaped when
they run as a Cloud Run job, and equally runnable as `nix shell` in CI with no
container. That is the argument for `packages.<name>-env` (§3): the runtime
closure is the unit both paths consume, and the image is one of two wrappers
around it. It also means "image per project" is about *what wraps the closure*,
not about whether the project is deployable.

## 4. The deploy contract (proven in `oscn-rs`)

The furthest-along deployment in the org is `openjusticeok/oscn-rs`. Its shape —
not its Rust specifics — is the reference.

```
nix build .#oscnImage          # nix2container.buildImage  → OCI image
nix run   .#push-image         # copyToRegistry (skopeo) → gcloud describe → sed
  └─ rewrites image_name = "…/oscn@sha256:…" in infra/tofu/terraform.tfvars
cd infra/tofu && tofu apply    # renders the digest into Cloud Run v2
gcloud run jobs execute oscn-migrate --wait   # AFTER apply — ordering trap
```

What it establishes:

- **Nix builds the image; there is no Containerfile.** `e867eb9` deleted
  `infra/containers/Containerfile` (+ `.otel`), docker-compose and a Grafana
  dashboard when `nix2container` landed. The surviving `.containerignore` is
  vestigial. A Containerfile is only meaningful as a `FROM`-the-pushed-image shim
  for a non-Nix consumer — never as the build path.
- **One image, four workloads.** Worker pool, `discover`, `planner`, `migrate`
  differ only by `args` + env (`infra/tofu/main.tf:460,647`).
- **Deploys reference a digest, never a tag.** Cloud Run dedupes template
  updates, so re-applying `:latest` did not roll the worker; it sat `Ready` and
  silent for ~1.5 h. `deploy_revision` forces a revision when the image is
  unchanged.
- **Ordering is part of the contract.** The migrate job template is rendered by
  `tofu apply`; running it before apply silently executes the *previous* image
  and reports success.
- **Dev and prod env split by output, not convention.** The devShell sets
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` and
  `OSCN_CONSOLE_LOGGING=1`; the image's `config.env` carries only `RUST_LOG` and
  the OTLP protocol.
- **Local state is a gitignored directory** (`.nix-dev/{pgdata,telemetry.duckdb}`)
  created by `apps`, not committed.

For R, the analogue is `packages.<name>-image`: nix2container, `R_LIBS_SITE` and
the rest of the shell's `env` in `config.env`, an entrypoint dispatching on `args`
(`shiny::runApp(host="0.0.0.0", port=8080)` / `targets::tar_make()` /
`plumber::pr_run()`), plus declared assets. No R project does this today;
`eviction-addresses`, `justice-link`, `ocjr-report-rural-fines-and-fees` consume
the flake for a **dev shell only** and deploy by hand.

### What the flake owns vs what a project keeps

| Owned by opi | Owned by the project / infra |
|---|---|
| R package resolution and the R library closure | the entrypoint and its arguments |
| the image builder (`mkRImage`): base layers, `env`, fontconfig | image *name* (Artifact Registry repo), assets to copy |
| the push → digest → pin helper | `infra/tofu` (Cloud Run resources, IAM, secrets, schedules) |
| dev environment composition | which workloads exist and their env |

## 5. No taxonomy: three facts, one existing concept

v0 had layers, v1–v2 had roles; both are **rejected**. A role table is semantic
baggage — six nouns, a classification of 65 packages to maintain, and fuzzy
boundaries (`is quarto reporting or checks?`) — bought to answer a question that
turns out to be structural. Three facts replace it:

**Fact 1 — there is one org environment.** R, the toolchain, the native libs,
the tools, quarto: one list, in `lib/baseEnvironment.nix`. It is what a dev shell
carries. Nobody tags anything.

**Fact 2 — the runtime closure is defined by construction, not by subtraction.**
`mkRenv { rPackages, env }` contains R + the resolved R packages + the shell's
env. Build tooling, Positron and CLI tools were never in it, so there is nothing
to exclude. "Dev-only weight never reaches an image" (inv 8) is therefore a
property of how the closure is built, not a rule that needs labels to enforce.

**Fact 3 — CI is a job-level choice, not a materialization.** A job either enters
the dev shell (`nix develop -c air format --check`) or the runtime closure
(`nix build .#env -c tar_make()`). Whichever it picks is visible in the workflow
yaml, which is exactly where that decision belongs.

**The one concept that survives is existing: a bundle.** The only genuine
question left is "which few tools are optional?", and `opi.bundles` already
expresses an optional group. Anything we decide to make optional becomes a
bundle; everything else stays in the org environment. That is 3–5 decisions, not
a taxonomy.

### What a dev shell carries, as description (NOT a spec to implement)

The grouping below is for a reader trying to understand where the 65 inputs come
from. It must not become code — no tags, no per-package metadata.

- **R and the R packages** (25): resolved from CRAN names, on `R_LIBS_SITE`.
- **Toolchain and native libraries** (30): `gcc`, `gnumake`, `cmake`,
  `pkg-config`, `cargo`/`rustc` (for `ojoutils`), and the headers/libs that make
  a local `devtools::load_all()` link — `arrow-cpp`, `abseil-cpp`, `udunits`,
  openssl/xml2/curl, and the graphics stack. Zero marginal closure cost (§2a).
- **Tools** (7): `air`, `arf`, `jarl` (also the CI checks), `git`, `gh`,
  `quarto`, `positron-bin`.

**Opt-out bundles: rejected.** The candidates were `positron-bin` (3,153 MiB),
`postgresql` (1,198 MiB), `google-cloud-sdk` (625 MiB), `duckdb` (288 MiB). Two
measurements informed the decision: `r-duckdb` carries its own engine (2.1 GiB,
242 paths), so R work never needs the CLI; and no workflow in
`openjusticeok/actions` invokes `gcloud` (tofu authenticates via WIF). But
bundling only saves **local disk** — CI enters the dev shell regardless (§10) —
and local disk is not a constraint. So the org environment stays as one list,
`gcloud` included (it is how an analyst gets ADC and how `push-image` looks up a
digest).

**Assets are a small, closed category.** They are code-adjacent — fonts, Quarto
extensions, templates, `.qmd` sources — never data: the org's rule is that data
stays in the warehouse, reached at runtime under the same `OJO_*` env an analyst
uses. This also keeps images environment-agnostic (invariant 12): baking data
would make staging and prod need different artifacts.

**Credentials are neither a package nor a category.** Analysts obtain ADC through
`gcloud`; deployments receive identity from the platform (Workload Identity).
A CLI in an image is a convenience, never the auth mechanism.

## 6. Invariants

1–5 live in `PLAN.md` (single nixpkgs pin, no rv, immutable R library, actionable
failures, cache retention). This document adds:

6. **The image is derived from the same declaration as the shell.** A project never
   maintains two package lists. If a runtime needs something the dev shell lacks,
   that is a contract bug, not a second list.
7. **Deploys reference a digest, never a tag.** Tags are a human affordance;
   infrastructure pins `@sha256:…` (the `oscn-rs` worker hang is the evidence).
8. **Dev-only weight never reaches an image.** Not by remembering to exclude it:
   the image is built from `mkRenv`, and Positron, compilers, formatters and CLI
   tools were never part of that closure (§5 fact 2).
9. **No credentials in artifacts.** Images and caches carry no tokens, keys or
   service-account files; identity comes from the platform.
10. **An image inherits the shell's `env`.** `R_HOME`, `FONTCONFIG_FILE`,
    `R_LIBS_USER`/`R_ENVIRON_USER`/`R_MAKEVARS_USER`, `QUARTO_R` — the same values,
    not re-derived ones. Without it, plots render in different fonts than dev and
    nothing errors (§2b).
11. **`flake.lock` is the reproducible unit; a digest identifies one build of
    it.** A deployed artifact records its digest *and* the source revision + lock
    hash it came from (image labels). Reproducibility is a property of the
    inputs, not of a byte-identical image — so Cachix retention is sized for the
    rollback window, with rebuild-from-lock as the fallback, not "keep every
    closure forever". This restates invariant 5 rather than replacing it.
12. **Artifacts are environment-agnostic.** One image serves staging and prod;
    the environment arrives as env vars at deploy and is authorized by IAM. No
    per-environment rebuilds, no baked prod hostnames, no credentials (§6 inv 9).
13. **An image declares the env it requires and refuses to start without it.**
    The declaration lives in the CLI's config file — already the place that names
    env vars and secret names, pulls values from GCP and writes `.env` — and the
    flake **reads that file** for `requiredEnv`, so `tofu` can validate its env
    sets at plan time and the entrypoint can fail at boot rather than at 3 a.m.
    mid-job. (`required` per entry decides whether it gates.) The cost accepted:
    the config file is a build input, so editing it invalidates the image.
14. **Prod deploys come from CI, and provenance is recorded.** A digest reaching
    prod was pushed by CI (never a laptop; dev/staging may still be deployed by a
    human), and the image carries labels naming the source revision and
    `flake.lock` hash it was built from (inv 11). Signing/attestation is
    **deferred** — the gate is the control that matters and it costs almost
    nothing given WIF; the signature can be added later without moving the gate.
    Trigger to revisit: a published number is challenged, or an outside party asks
    for proof rather than a claim.

## 7. What the builder is, given all this

Because R packages carry their libraries and the font/config story is `env`, the
R-specific part of an image is small. The error-prone part is not building — it
is pushing, resolving the digest, and pinning it. So three pieces, with different
scopes:

| Piece | Scope | Why it exists |
|---|---|---|
| `mkRenv { pkgs, rPackages, env }` | **R-specific, high value** | the runtime closure: R + resolved R packages + the org `env`. This is where opi's whole value concentrates (resolution rules, invariant 10). |
| `mkImage { name, contents, env, requiredEnv, entrypoint, assets, provenance }` | **thin, generic** | org conventions over `nix2container`: entrypoint path, labels carrying invariant 11's provenance, non-root user, and an entrypoint that enforces `requiredEnv` (inv 13). Usable by a Rust artifact too. |
| `pushImage` (an `apps.*` entry) | **org-wide, the valuable bit** | build → `copyToRegistry` → resolve digest → pin `image_name` in tfvars, with `--dry-run`. Bespoke per-repo today, and the step that fails silently (tag dedupe, digest lag, ordering). |

### Conventions opi ships (decided)

| Concern | Decision |
|---|---|
| Entrypoint | **Per project, documented contract.** opi does not ship a dispatcher: bind `0.0.0.0:$PORT`, read env, export OTel, handle `SIGTERM`. ~20 lines per repo, and unusual apps are never blocked by a framework. |
| Secrets | **Secret Manager volumes.** Cloud Run mounts secret *N* as a file/env; the image never fetches credentials. The `requiredEnv` names and the mounted secret names are both declared, so `tofu` can compare them at plan time. |
| Retention | **Keep every closure ever deployed, for now.** Cheap and safest; revisit when retention actually costs something — rebuild-from-lock (inv 11) is the fallback that makes shrinking possible later. |
| Signing | **Deferred** (inv 14). Labels carry revision + lock hash; the CI-only gate already exists. |

Split rationale: the *contract* (§4) is ecosystem-agnostic and belongs to the org;
the *contents* are ecosystem-specific (`mkRenv` for R, `crane` for Rust); the
*push/pin* is ecosystem-agnostic and the most dangerous to reimplement. A repo
should not hand-roll digest resolution; it should not be forced to adopt an R
builder either.

## 8. Open questions

Answered in review (kept for the record): layers are not a noun (→ §5); CI is
`dev` minus the IDE (→ §3); nothing must be in CI but not dev; `libwebp` is
carried by `r-ragg`; fonts are an `env` concern, not a package concern (→ §2b);
assets are a small closed category, code-adjacent only (→ §5); the reproducible
unit is `flake.lock`, not the digest (→ inv 11); artifacts are
environment-agnostic and authorization is IAM (→ inv 12).

**Q11–Q14 are answered:**

- **Q11 — required env: adopted.** The contract is declared once and consumed by
the CLI (which pulls values from GCP and materialises `.env`), by the image (which
fails to start without it) and by `tofu` (which validates its env sets against
it). The `required` flag per entry decides whether it gates. Home of the
declaration: **Q15**.
- **Q12 — provenance: attestation, in principle.** Labels alone answer "what does
this artifact claim to be"; an attestation answers "what can I prove". Adopted
subject to the trust path (**Q17**) and mechanism (**Q18**).
- **Q13 — pipelines: image-shaped, but not only.** A pipeline runs as a Cloud Run
job (image) *or* as `nix shell` in CI with no container at all. Hence the runtime
closure is a first-class output (**Q16**), and the image is one of two wrappers.
- **Q14 — rollback unit: `tofu` owns it.** Digest plus the env/IAM it was
validated against are versioned together in state; `deploy_revision` forces a
revision when the artifact is unchanged. A release note is not a mechanism.

**Q19–Q22 are answered:** per-project entrypoint with a documented contract (no
dispatcher); secrets via Secret Manager volumes mounted by `tofu`; retention =
keep everything for now, with rebuild-from-lock as the mechanism that will allow
shrinking later; pilot = **a Shiny dashboard already on Cloud Run**, because it
puts invariant 10 (fonts), 13 (required env), 14 (CI-only prod) and secret
delivery in front of real users with a small closure.

**Q26–Q30 are answered by rejection.** No opt-out bundles: `gcloud` stays
always-on (it is how an analyst obtains ADC and how `push-image` resolves a
digest), and bundling the DB CLIs / Positron was dropped because it saves only
local disk — CI enters the dev shell regardless (§10) — while costing a breaking
change for every shell that runs `psql`, `duckdb` or `positron .`. Measured
along the way: `r-duckdb` carries its own engine (2.1 GiB / 242 paths), so the
CLI is interactive-only; and no workflow in `openjusticeok/actions` calls
`gcloud`.

Remaining open items are **triggers, not questions**:

- **Signing/attestation** (inv 14) — when a published number is challenged, or an
  outside party asks for proof rather than a claim.
- **Shrinking Cachix retention** — when the storage/bandwidth bill matters. The
  lock makes this safe.
- **`ops` bundle split** (`postgresql`, `google-cloud-sdk`, `duckdb`) — measured at
  ~2.1 GiB per shell that does not declare them; nothing hurts yet, so it waits
  until a shell is slow to fetch or a CI job is paying for it.
- **The CLI** (PLAN P3+) — invariant 13 and the `.env`/secret flow both lean on it.

## 9. Implementation order

Nothing here changes today's dev shells; it makes the model real in the order that
de-risks it. Note what is **not** on the list: no classification pass, no tagging
of packages. The roles/taxonomy idea is dead (§5).

| Step | Work | Why in this order |
|---|---|---|
| 1 ✅ | **`packages.<name>-env`** — `lib/mkRenv.nix` + `lib/rShellEnv.nix` | Done and measured (§2c). Consumed by CI now, by images next |
| 2 | **`mkImage` + `pushImage`** | The wrapper and the dangerous step (digest lag, tag dedupe, pin ordering); pilot the Shiny dashboard |
| 3 | **`requiredEnv` + Secret Manager mounts in the pilot's tofu** | Where inv 13 first touches real infrastructure |
| 4 | *(deferred)* signing, retention tightening | Triggers in §8 |

No classification pass, no package tagging, and no bundle surgery — all three were
considered and rejected (§5, §8).

## 10. Where the CI win actually is

Bundling does **not** make CI cheaper, because project CI enters the dev shell:

| Workflow | Runner command | Needs | Does not need |
|---|---|---|---|
| `r-ci` | `nix develop --command air format --check .` / `jarl check .` | `air`, `jarl` | R, Positron, DB CLIs |
| `targets-ci` | `nix develop --command … targets::tar_make()` | R + packages = `packages.<name>-env` | Positron, `gcloud`, compilers |

So the lever is **CI not entering the dev shell**, which is exactly what
`packages.<name>-env` enables. Two consequences worth acting on separately:

- `targets-ci.yml` still runs `rv sync` / `rv run` (lines 59–68) — the shared
  workflow never migrated off `rv`, so it works only for projects pinned to the
  pre-`rv`-removal flake. That is a bug in `openjusticeok/actions`, not here.
- `r-ci` needs only `air` + `jarl`; a lint-only environment (no R at all) would
  make it seconds rather than minutes.
