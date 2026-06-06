---
id: 4
slug: wire-nix-mori-docs-for-the-split-packages
title: "Wire nix mori docs for the split packages"
kind: exec-plan
created_at: 2026-06-06T14:28:17Z
intention: "intention_01kteks21kes6rcgdxpc96x5s2"
master_plan: "docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md"
---

# Wire nix, mori, and docs for the split packages

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

By the time this plan runs, the repository has been split from one package (`typeid-hs`) into three:
`typeid-hs-sql` (shared, tool-agnostic embedded SQL), `typeid-hs-hasql-migration` (the renamed
`hasql-migration` backend), and `typeid-hs-codd` (the new `codd` backend). The code builds, but the
repository's *metadata and documentation* still describe the old single-package world: `mori.dhall`
lists one package named `typeid-hs`, the README explains only the `hasql-migration` usage and still
calls the package `typeid-hs`, and the Nix dev shell has not been exercised against the multi-package
project.

This plan finishes the initiative by making the repository's metadata and docs tell the truth. After
it, `mori show --full` reports three packages and the `codd` dependency; the README documents both
migration backends, names the three packages correctly, and tells existing consumers how to migrate off
the now-removed `typeid-hs` package name; and the Nix dev shell is confirmed to build all three packages.

You can see it working by running `mori show --full` (three packages, `codd` in the dependency list),
reading the rewritten README, and running `nix develop --command cabal build all` to confirm the whole
project builds in the pinned toolchain.

This plan is part of the initiative in
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md`. It has a hard dependency
on plan 1 (the multi-package layout must exist) and soft dependencies on plan 2 and plan 3 (it documents
their final package names and public APIs, so it should be finalized after both are complete). If plan 2
or plan 3 is not yet done, you may draft the structural parts but must not finalize the README usage
sections or the `mori.dhall` dependency list until their public surfaces are settled.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: `mori.dhall` updated — three packages, codd dependency, refreshed description (2026-06-06)
- [x] Milestone 1: `mori show --full` reflects the three packages and dependencies (2026-06-06)
- [x] Milestone 2: Nix dev shell builds all three packages (`nix develop --command cabal build all`); `flake.nix` description fixed (2026-06-06)
- [x] Milestone 3: root README rewritten — both backends documented; consumer migration note added; all code examples typecheck (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The plan's README code examples were stale against the pinned library versions; all were
  corrected and typechecked before finalizing.** Four corrections were needed: (1) hasql 1.10 no
  longer exports `run` from `Hasql.Session`; the session runner is
  `Hasql.Connection.use :: Connection -> Session a -> IO (Either SessionError a)` (this matches the
  MasterPlan Surprises entry from EP-2). (2) `Hasql.Connection.acquire` now takes a `Settings` type,
  not a bare `ByteString`; the string-literal connection examples require
  `{-# LANGUAGE OverloadedStrings #-}` (verified `Settings` derives `IsString`). (3) codd's
  `ApplyResult` has **no `Show` instance**, so the plan's `print result` in the codd example would not
  compile; the README pattern-matches the three constructors instead. (4) `applyTypeIdMigrations`
  cannot run in plain `IO` (`No instance for CoddLogger IO`); the example runs it in `LoggingT IO` via
  `Codd.Logging.runCoddLogger`. Every README snippet was extracted and compiled with
  `ghc -fno-code -package <backend>` until it typechecked with exit 0.

- **The codd dependency was repinned to the official upstream mid-EP-4 (user-directed).** While
  finalizing the docs, the user directed that codd be consumed from `https://github.com/mzabani/codd`
  rather than the corpus fork `shinzui/codd-project`. This is an EP-3-owned `cabal.project` change;
  it was made here and re-verified (build + end-to-end apply). The README already links the official
  `mzabani/codd`, and `mori.dhall`'s registered dependency name is `mzabani/codd`, so no further doc
  change was needed. Full rationale in `docs/plans/3-create-typeid-hs-codd-package.md` Decision Log
  and the MasterPlan Surprises & Discoveries / Decision Log.


## Decision Log

- Decision: Keep `mori.dhall` as a single project manifest listing all three packages, rather than
  splitting into per-package manifests.
  Rationale: `mori.dhall` describes a project (a repository), and these three packages live in and are
  released from one repository. One manifest with three `packages` entries matches mori's model (see the
  existing single-entry manifest) and is the least surprising representation.
  Date: 2026-06-06

- Decision: The README documents both backends in one file at the repo root and adds an explicit
  "Migrating from typeid-hs" note, rather than relegating per-backend docs to package-level READMEs.
  Rationale: A reader landing on the repository needs to choose a backend; a single comparison plus a
  clear migration note serves that best. Package-level READMEs may still be added by plans 2/3 for
  package pages, but the root README is the canonical entry point.
  Date: 2026-06-06


## Outcomes & Retrospective

EP-4 is complete, finalizing the initiative. `mori.dhall` now declares all three packages
(`typeid-hs-sql`, `typeid-hs-hasql-migration`, `typeid-hs-codd`) with correct paths and
descriptions, adds `mzabani/codd` to the dependency list, and carries a both-backends project
description; `mori show --full` renders three packages and four dependencies without a Dhall error.
`flake.nix`'s stale `"Haskell nix template"` description is replaced, and
`nix develop --command cabal build all` builds all three packages in the pinned GHC 9.12.4 dev
shell. The root `README.md` is rewritten to present the three packages, help a reader choose a
backend, document both `migrate` flows, and explain the `typeid-hs` → `typeid-hs-hasql-migration`
rename; no stale bare `typeid-hs` `build-depends` reference remains outside the migration note.

The main lesson (see Surprises) is that documentation examples must be compiled, not trusted: the
plan's README snippets were stale against the actually-pinned `hasql` (1.10, which moved `run` to
`Hasql.Connection.use` and made `acquire` take a `Settings`/`IsString` value) and `codd` (whose
`ApplyResult` is not `Show` and whose `applyTypeIdMigrations` needs `LoggingT IO`, not `IO`). Each
snippet was compiled with `ghc -fno-code` until green. Separately, the user redirected the codd
dependency to the official `mzabani/codd` (tag `v0.1.8`, no `subdir`) during this plan; that
`cabal.project` change was applied and re-verified end-to-end.

(Note: this section header was absent from the generated skeleton and added during EP-4
implementation, as the ExecPlan spec requires every plan to maintain an Outcomes section.)


## Context and Orientation

Assume no prior knowledge of this repository beyond the working tree.

**Repository state at the start of this plan** (after plans 1–3): three package directories
(`typeid-hs-sql/`, `typeid-hs-hasql-migration/`, `typeid-hs-codd/`), a multi-package `cabal.project`
listing all three plus `source-repository-package` pins for `hasql-migration` and `codd`, and a
`flake.nix`/`nix/` dev shell. The two files this plan rewrites — `mori.dhall` and `README.md` — still
describe the old single package.

**The current `mori.dhall` (full content)** — you will edit the `description`, `packages`, and
`dependencies`:

```dhall
let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/026ae74331e5c516542af1dd96f041c658ed4621/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "typeid-hs"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some "PostgreSQL migrations for TypeID using hasql-migration"
      , domains = [ "TypeID", "Database" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{
        , name = "typeid-hs"
        , github = Some "topagentnetwork/typeid-hs"
        }
      ]
    , packages =
      [ Schema.Package::{
        , name = "typeid-hs"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "."
        , description = Some "PostgreSQL migrations for TypeID using hasql-migration"
        }
      ]
    , dependencies =
      [ "shinzui/hasql-migration"
      , "hasql/hasql"
      , "ekmett/lens"
      ]
    }
```

**The mori workflow.** `mori` is a project registry. The project's identity, packages, and dependencies
are declared in `mori.dhall`; `mori show --full` renders the manifest, and the project is registered/
refreshed in the registry by re-observing it. After editing `mori.dhall`, run `mori show --full` to
confirm the manifest parses and renders the intended structure. The Dhall `Schema` import is pinned by
sha256; do not change that import. Use the existing `Schema.Package::{...}` record shape for each package.

**The current README.** It is titled `# typeid-hs`, says "PostgreSQL migrations for TypeID using
hasql-migration", and shows `build-depends: typeid-hs` plus `import TypeId.Db.Migration` usage for
running/validating/listing migrations, a table of installed objects, SQL usage examples, and a version
section. The installed-objects table, SQL usage examples, and version note remain accurate for both
backends and can be reused largely as-is; what changes is the package-selection framing, the
`build-depends` names, and the addition of a `codd` usage section and a migration note.

**The Nix dev shell.** `flake.nix` imports `nix/haskell.nix`, which builds a dev shell from the
`haskell-nix-dev` base flake (GHC 9.12.4 + cabal + HLS) and adds `pkgs.postgresql`, `pkgs.just`,
`pkgs.xz`. It is a **dev-shell-only** flake (a comment in `nix/haskell.nix` states the package build is
provided by the shared registry, not here, so there is no `flake.module.nix`). This means there is
typically **no Nix change required** for the package split — the dev shell builds whatever
`cabal.project` lists. This plan's Nix work is therefore primarily *verification* that the dev shell
still works for the multi-package project, plus updating the `flake.nix` `description` string if desired.

**Term definitions.**
- *`mori.dhall`*: a Dhall-format manifest declaring this project's identity, packages, and dependencies
  for the `mori` registry.
- *dev-shell-only flake*: a Nix flake that provides a development environment (`nix develop`) but does
  not itself build the package as a Nix output.


## Plan of Work

Three milestones, independently verifiable.

**Milestone 1 — `mori.dhall`.** Rewrite the `packages` list to the three packages with correct `name`,
`path`, and `description`; update the project-level `description`; and add `mzabani/codd` to
`dependencies` (keeping `shinzui/hasql-migration`, `hasql/hasql`, `ekmett/lens`). Acceptance:
`mori show --full` renders three packages and the codd dependency without a Dhall error.

**Milestone 2 — Nix verification.** Confirm the dev shell builds the whole multi-package project, and
update the `flake.nix` `description` string from the stale "Haskell nix template" to something accurate.
Acceptance: `nix develop --command cabal build all` succeeds.

**Milestone 3 — README.** Rewrite the root README to present both backends, fix all `typeid-hs` package
references to the new names, add a `codd` usage section, and add a "Migrating from typeid-hs" note.
Acceptance: the README names all three packages correctly, documents both `migrate` flows, and explains
the rename; a grep confirms no stale bare `typeid-hs` package reference remains except inside the
migration note.


## Concrete Steps

All commands from the repository root; prefix with `nix develop` where a Haskell toolchain is needed.

### Milestone 1 — mori.dhall

1. Edit `mori.dhall`. Change the project `description` to cover both backends, rewrite `packages` to
   three entries, and add the codd dependency. The `project.name`, `namespace`, `repos`, `domains`, and
   `owners` stay as they are (the project is still the `typeid-hs` repository). Target content for the
   changed regions:

```dhall
      , description = Some "PostgreSQL TypeID migrations, shipped as hasql-migration and codd backends over a shared SQL core"
```

```dhall
    , packages =
      [ Schema.Package::{
        , name = "typeid-hs-sql"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-sql"
        , description = Some "Embedded TypeID PostgreSQL SQL, tool-agnostic"
        }
      , Schema.Package::{
        , name = "typeid-hs-hasql-migration"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-hasql-migration"
        , description = Some "PostgreSQL TypeID migrations via hasql-migration"
        }
      , Schema.Package::{
        , name = "typeid-hs-codd"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-codd"
        , description = Some "PostgreSQL TypeID migrations via codd"
        }
      ]
    , dependencies =
      [ "shinzui/hasql-migration"
      , "hasql/hasql"
      , "ekmett/lens"
      , "mzabani/codd"
      ]
```

   Note: `mzabani/codd` is the registered name (confirm with `mori registry search codd`). Keep the
   `Schema` import line and its sha256 unchanged.

2. Verify the manifest parses and renders the new structure:

```bash
mori show --full
```

   Expected: the output lists three packages (`typeid-hs-sql`, `typeid-hs-hasql-migration`,
   `typeid-hs-codd`) under "Packages", and the "Dependencies" section now includes `mzabani/codd`
   alongside the three existing entries. If Dhall reports a parse error, re-check comma placement in the
   `packages`/`dependencies` lists.

### Milestone 2 — Nix verification

3. Update the stale `flake.nix` `description` (currently `"Haskell nix template"`):

```text
  description = "PostgreSQL TypeID migrations: hasql-migration and codd backends over a shared SQL core";
```

4. Confirm the dev shell builds the whole project in the pinned toolchain:

```bash
nix develop --command cabal build all
```

   Expected: `typeid-hs-sql`, `typeid-hs-hasql-migration`, and `typeid-hs-codd` all build. If this fails
   only inside `nix develop` but worked in plans 1–3 with a system cabal, the difference is the pinned
   GHC 9.12.4 — record the discrepancy in Surprises & Discoveries and resolve dependency bounds (e.g. the
   codd `allow-newer` from plan 3) in `cabal.project`.

### Milestone 3 — README

5. Rewrite `README.md`. Keep the TypeID explanation, the installed-objects table, the SQL usage examples,
   and the version note (they apply to both backends). Replace the single-package framing with a
   package-selection section, document both backends, and add a migration note. A suitable structure:

```markdown
# typeid-hs

PostgreSQL migrations for [TypeID](https://github.com/jetify-com/typeid), shipped as two
interchangeable backends over a shared SQL core. TypeID is a type-safe, K-sortable, globally
unique identifier inspired by Stripe IDs. The SQL is sourced from
[typeid-sql](https://github.com/jetify-com/opensource/tree/main/typeid/typeid-sql).

## Packages

This repository builds three packages:

- **`typeid-hs-sql`** — the embedded TypeID SQL exposed as plain Haskell values. Tool-agnostic;
  depends on neither hasql nor codd. The two backends build on it.
- **`typeid-hs-hasql-migration`** — applies the migrations with
  [hasql-migration](https://hackage.haskell.org/package/hasql-migration). Choose this if your
  project already uses hasql.
- **`typeid-hs-codd`** — applies the same migrations with [codd](https://github.com/mzabani/codd).
  Choose this if your project uses codd's forward-only, schema-verifying workflow.

Depend on exactly one backend; it pulls in `typeid-hs-sql` for you.

## Migrating from `typeid-hs`

The package formerly named `typeid-hs` is now `typeid-hs-hasql-migration`. Its modules and API are
unchanged — only the package name changed. Update your `build-depends`:

```cabal
build-depends:
  typeid-hs-hasql-migration   -- was: typeid-hs
```

No code changes are needed: `import TypeId.Db.Migration` and the `migrate`/`validate`/`getMigrations`
functions are identical.

## Usage — hasql-migration backend

(Reuse the existing Running / Validating / Checking sections verbatim, under build-dep
`typeid-hs-hasql-migration`.)

## Usage — codd backend

Add `typeid-hs-codd` to your `build-depends`. The migrations are exposed as codd
`AddedSqlMigration` values, plus helpers to apply them:

```haskell
import TypeId.Db.Codd.Migration (migrateFromEnv)

main :: IO ()
main = do
  result <- migrateFromEnv   -- reads CODD_CONNECTION, CODD_MIGRATION_DIRS, CODD_EXPECTED_SCHEMA_DIR
  print result
```

To compose the TypeID migrations with your service's own migrations, use `migrations` (a list of
codd `AddedSqlMigration` values) and `applyTypeIdMigrations`, supplying your own `CoddSettings` and
choosing `StrictCheck` or `LaxCheck`. Your service owns its expected-schema snapshot; this package
does not ship one.

## What Gets Installed

(Reuse the existing installed-objects table — it applies to both backends.)

## SQL Usage Examples

(Reuse the existing SQL examples verbatim.)

## Version

(Reuse the existing version note; `version` is available from both
`TypeId.Db.Migration` and `TypeId.Db.Codd.Migration`.)
```

   When reusing the existing Running/Validating/Checking and SQL-examples sections, copy them from the
   pre-rewrite README content (preserved in git history and quoted in part above) so nothing is lost.
   The triple-backtick fences shown inside this plan are illustrative; in the actual README every fenced
   block must carry a language tag (`cabal`, `haskell`, `sql`, `text`) per the repository's formatting
   rule.

6. Confirm no stale bare `typeid-hs` package reference survives outside the migration note. The
   acceptable remaining mentions of the literal token `typeid-hs` are: the repository title `# typeid-hs`,
   the new package names that contain it as a prefix (`typeid-hs-sql`, etc.), and the "Migrating from
   `typeid-hs`" note. Spot-check:

```bash
grep -n "typeid-hs" README.md
```

   Review the output by eye: every line should be either the title, a hyphenated package name, or the
   migration note — never a bare `build-depends: typeid-hs` or "the typeid-hs package" outside the note.


## Validation and Acceptance

This plan is complete when:

1. `mori show --full` lists three packages (`typeid-hs-sql`, `typeid-hs-hasql-migration`,
   `typeid-hs-codd`) and a `dependencies` section including `mzabani/codd`:

```bash
mori show --full
```

2. The dev shell builds the whole project:

```bash
nix develop --command cabal build all
```

   Expected: all three packages build.

3. The README documents both backends, names all three packages correctly, includes the
   "Migrating from `typeid-hs`" note, and contains no stale bare `typeid-hs` `build-depends` reference
   (Milestone 3 step 6).

4. `flake.nix` no longer describes itself as `"Haskell nix template"`.

When these hold, update the MasterPlan Exec-Plan Registry to mark EP-4 Complete, check off the EP-4
entries in the MasterPlan Progress section, and fill in the MasterPlan Outcomes & Retrospective section
since this is the final plan of the initiative.


## Idempotence and Recovery

All edits here are to text files (`mori.dhall`, `flake.nix`, `README.md`) and are idempotent — writing
the same content twice is harmless. `mori show --full` and `nix develop --command cabal build all` are
read-only/repeatable. If a `mori.dhall` edit breaks parsing, `git checkout -- mori.dhall` restores the
last good version; re-apply the change carefully watching list comma placement. There are no destructive
operations in this plan.


## Interfaces and Dependencies

**Reads (soft dependencies):** the final package names and public APIs produced by
`docs/plans/2-rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql.md`
(`typeid-hs-hasql-migration`, module `TypeId.Db.Migration`) and
`docs/plans/3-create-typeid-hs-codd-package.md` (`typeid-hs-codd`, module `TypeId.Db.Codd.Migration`
with `migrateFromEnv`, `applyTypeIdMigrations`, `migrations`). The README and `mori.dhall` must name
these exactly as those plans finalized them — verify against the actual `.cabal` files and module export
lists rather than from memory before finalizing.

**Files this plan owns:** `mori.dhall`, `flake.nix` (description only), and the root `README.md`. See
MasterPlan Integration Points entries 4 and 5: only this plan edits `mori.dhall`'s package/dependency
lists and the root README. This plan does not edit `cabal.project` or any package's `.cabal` or source
(those are owned by plans 1–3); if it finds a build problem, it records it in the MasterPlan Surprises &
Discoveries section and the relevant backend plan is updated.

**Tools:** `mori` (manifest rendering), `nix` (dev shell), `cabal` (build verification).
