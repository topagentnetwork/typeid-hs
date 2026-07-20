---
id: 5
slug: create-typeid-hs-pg-migrate-package
title: "Create typeid-hs-pg-migrate package"
kind: exec-plan
created_at: 2026-07-20T22:13:16Z
intention: "intention_01ky0sdvgze7ztnt6p3vvta4w4"
---

# Create typeid-hs-pg-migrate package

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today this repository ships the TypeID PostgreSQL migrations through two migration backends
over one shared SQL core: `typeid-hs-hasql-migration` (applies the SQL with the
`hasql-migration` library) and `typeid-hs-codd` (applies it with `codd`). Both read the same
embedded SQL from the tool-agnostic `typeid-hs-sql` package. This plan adds a **third**
backend: a new cabal package `typeid-hs-pg-migrate` that exposes the **same** TypeID SQL as a
`pg-migrate` *migration component* so that a project standardized on the `pg-migrate` library
can apply the TypeID objects with `pg-migrate`.

*TypeID* is a type-safe, K-sortable, globally unique identifier (like Stripe IDs). The four
SQL files install a UUIDv7 generator, base32 encode/decode, a `typeid` composite type, the
`typeid_generate*`/`typeid_parse`/`typeid_print`/`typeid_check*` functions, and a `===`
operator. That set is identical across all three backends.

*`pg-migrate`* is a Hasql-native PostgreSQL migration library developed in this fleet
(GitHub `shinzui/pg-migrate`; source on disk at `/Users/shinzui/Keikaku/bokuno/pg-migrate`).
Its central idea is: **libraries own ordered, embedded migration components, and applications
compose those components into one explicitly ordered plan and run it.** A *component* is a
named, ordered, non-empty bundle of SQL migrations with a stable identifier and an optional
set of component dependencies. A *plan* is a validated, dependency-ordered composition of
components. `pg-migrate` records applied migrations in a durable **ledger** (by default a
PostgreSQL schema named `pgmigrate`), applies pending migrations under an advisory lock, and
verifies stored history against the declared plan (positions, checksums, kinds, transaction
modes). It is forward-only and does not run down migrations.

`typeid-hs` fits `pg-migrate`'s model exactly: it is a *library* whose job is to *own* the
TypeID migration component so consuming applications can compose it. After this plan, a
consuming application can:

- depend on `typeid-hs-pg-migrate`;
- obtain the TypeID migrations as a `pg-migrate` `MigrationComponent` value
  (`typeIdComponent`) and splice it into its own plan alongside its own components, declaring a
  dependency on the stable component name `"typeid"` (exported as `componentNameText`);
- or, for the simplest case, call the batteries-included `migrateTypeId` helper, which builds
  a single-component plan and applies just the TypeID migrations against a database.

You can see it working by building `typeid-hs-pg-migrate`, then applying the migrations against
a real PostgreSQL database and confirming `SELECT typeid_generate_text('user')` returns a
TypeID and that `pg-migrate` recorded four `applied` rows (`typeid/01_uuidv7`,
`typeid/02_base32`, `typeid/03_typeid`, `typeid/04_operator`) in its ledger.

This plan is a standalone follow-on to the completed initiative in
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md`. It is **not**
part of that MasterPlan (which is Complete) — it is modeled directly on the third backend it
delivered, `docs/plans/3-create-typeid-hs-codd-package.md`. It has one hard dependency, already
satisfied in the tree: the module `TypeId.Db.Sql` (package `typeid-hs-sql`) must export
`version :: String`, `migrationFiles :: [FilePath]`, and `sqlFiles :: [(FilePath, ByteString)]`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1 (2026-07-20T22:29Z): `typeid-hs-pg-migrate/` package + `.cabal` created; `pg-migrate` pinned in `cabal.project` (tag `v1.1.0.0` / `f39d64e`, subdir `pg-migrate`); dependency graph resolves **cleanly** under GHC 9.12.4 (no `allow-newer` needed); placeholder library builds.
- [ ] Milestone 2: `TypeId.Db.PgMigrate.Migration` exposes `version`, `componentNameText`, `typeIdComponent`, `typeIdPlan`, `TypeIdMigrateError`, `migrateTypeId`; builds clean with `-Wall`; `typeIdComponent` and `typeIdPlan` evaluate to `Right` at the REPL (proves the embedded SQL passes `pg-migrate`'s SQL validator).
- [ ] Milestone 3: end-to-end apply against a live PostgreSQL via `migrateTypeId`; four migrations recorded `applied` in `pgmigrate.migrations` in order; TypeID objects verified present; rerun is idempotent (`AlreadyApplied`).
- [ ] Milestone 4: `README.md` documents the `pg-migrate` backend; `mori.dhall` lists the fourth package and the `shinzui/pg-migrate` dependency.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Milestone 1: `pg-migrate` v1.1.0.0 (subdir `pg-migrate`) solved **cleanly** under GHC 9.12.4
  with no `allow-newer` and no extra pins. `cabal build typeid-hs-pg-migrate` fetched the pin and
  built only two new dependencies not already in the tree — `hasql-transaction-1.2.2` and
  `pg-migrate-1.1.0.0` — then the placeholder library. Evidence: `cabal build` output listed
  exactly `hasql-transaction-1.2.2 (lib)`, `pg-migrate-1.1.0.0 (lib)`, `typeid-hs-pg-migrate-0.1.0.0
  (lib)` as the build set (plus a `typeid-hs-sql` reconfigure). This is the "clean solve" branch of
  the plan's Idempotence and Recovery guidance; Milestone 4 documents it as the final dependency
  story (no `allow-newer` / `constraints` entries required).


## Decision Log

Record every decision made while working on the plan.

- Decision: Deliver `pg-migrate` support as a new sibling package `typeid-hs-pg-migrate`
  consuming `typeid-hs-sql`, mirroring the existing `typeid-hs-codd` package rather than adding
  a module to an existing backend.
  Rationale: This matches the established three-package layout (a tool-agnostic SQL core plus
  one thin backend package per migration tool). It keeps `pg-migrate`'s dependency closure out
  of the other backends, lets a consumer depend on exactly one backend, and keeps each backend
  independently buildable. See `docs/plans/3-create-typeid-hs-codd-package.md` for the model.
  Date: 2026-07-20

- Decision: Build the component with `pg-migrate`'s pure, non-Template-Haskell smart
  constructor `migrationComponentFromEmbeddedSql :: Text -> Set Text -> NonEmpty (FilePath,
  ByteString) -> Either DefinitionError MigrationComponent`, fed directly from
  `TypeId.Db.Sql.sqlFiles`. Do **not** use `pg-migrate-embed`'s Template Haskell
  `embedMigrationManifest` and do **not** add a `pg-migrate` manifest file to this repo.
  Rationale: `typeid-hs-sql` already embeds the SQL at compile time and exposes the ordered
  `(FilePath, ByteString)` list — precisely the shape `migrationComponentFromEmbeddedSql`
  consumes. The TH `embedMigrationManifest` splice merely produces that same
  `NonEmpty (FilePath, ByteString)` from an on-disk manifest, so it would duplicate the SQL and
  add the `pg-migrate-embed` dependency and its GHC recompilation plugin for no gain. This keeps
  the backend a thin adapter with no second copy of the SQL and no manifest to keep in sync.
  Date: 2026-07-20

- Decision: Name the `pg-migrate` component `"typeid"`, exported as `componentNameText`. Each
  SQL file's base name becomes a migration name by dropping `.sql` (e.g. `01_uuidv7.sql` ->
  `01_uuidv7`), giving durable migration identities `typeid/01_uuidv7`, `typeid/02_base32`,
  `typeid/03_typeid`, `typeid/04_operator`.
  Rationale: `migrationComponentFromEmbeddedSql` derives the migration name from the file base
  name by stripping only the `.sql` suffix, and `pg-migrate` identifiers may not contain a
  slash, so the file base names (no directory component) are used verbatim. `"typeid"` is the
  obvious, stable, human-meaningful component name; exporting it lets consuming applications
  declare a `pg-migrate` component dependency on it (`Set.singleton componentNameText`) so the
  TypeID migrations are ordered before their own.
  Date: 2026-07-20

- Decision: Expose the idiomatic `pg-migrate` surface (`typeIdComponent`, `componentNameText`)
  **and** a batteries-included `migrateTypeId` runner (plus a `typeIdPlan` value and a flattened
  `TypeIdMigrateError` sum type).
  Rationale: `pg-migrate`'s model is that applications compose and run plans, so the component
  is the primary deliverable. But this repository's other backends each ship a batteries-included
  apply path (`typeid-hs-hasql-migration`'s `migrate`, `typeid-hs-codd`'s `migrateFromEnv`), and
  the ExecPlan specification requires demonstrable end-to-end behavior a novice can run. A thin
  `migrateTypeId :: RunOptions -> Settings -> IO (Either TypeIdMigrateError MigrationReport)`
  that builds the single-component plan and calls `runMigrationPlan` provides that without
  hiding `pg-migrate`'s composition model — the docs steer multi-component consumers to
  `typeIdComponent`.
  Date: 2026-07-20

- Decision: Pin `pg-migrate` in `cabal.project` via a `source-repository-package` at the
  official upstream `https://github.com/shinzui/pg-migrate`, tag `v1.1.0.0` (commit
  `f39d64e354818999667d345a1452f33eb4857fc1`), with `subdir: pg-migrate`, alongside the existing
  `hasql-migration` and `codd` pins.
  Rationale: `pg-migrate` is not on Hackage; this repo already pins its database tooling by
  `source-repository-package` (the `hasql-migration` fork and `codd`). `pg-migrate` is a
  multi-package repository whose core library lives in the `pg-migrate/` subdirectory, so the
  pin needs `subdir: pg-migrate`; the other subpackages (CLI, embed, import adapters) are not
  needed by this backend and are deliberately not exposed. `v1.1.0.0` is the current released
  tag (its published Public API 1.0 and ledger schema version 1 are the supported contract). The
  local mori-registered checkout `/Users/shinzui/Keikaku/bokuno/pg-migrate` is the same
  repository and may be read for source reference.
  Date: 2026-07-20

- Decision: Include the README + `mori.dhall` documentation wiring as a milestone of this plan
  (Milestone 4) rather than a separate finalization plan.
  Rationale: Unlike the earlier split (which used a dedicated finalization plan, EP-4, because
  three packages landed at once), this plan adds a single backend; folding the doc/manifest
  update into the same plan keeps the change self-contained and the plan honestly complete only
  when the new package is discoverable and documented.
  Date: 2026-07-20

- Decision: Start `typeid-hs-pg-migrate` at version `0.1.0.0`.
  Rationale: New package name; `0.1.0.0` matches the baseline chosen for the other new packages
  in this repository (see the MasterPlan Decision Log).
  Date: 2026-07-20


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

Assume no prior knowledge of this repository beyond the working tree.

**ADRs.** There is no `docs/adr/` directory in this repository at the time of writing (verified:
`ls docs/adr` reports no such directory). No relevant ADR exists to consult. The durable
project context this plan builds on lives in the MasterPlan and prior ExecPlans instead:
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md` and
`docs/plans/3-create-typeid-hs-codd-package.md`. At completion, per the ExecPlan specification,
review this plan's Decision Log/Surprises/Outcomes and promote durable, project-level decisions
(the "three-then-four backends over one SQL core" architecture, the pinned-fork policy, the
"library owns the component; application composes and runs" boundary) into a new `docs/adr/`
entry if they warrant a durable home.

**Repository state at the start of this plan.** The tree is a cabal multi-package project
(a "monorepo": several packages built from one `cabal.project`). Relevant layout:

```text
.
|-- cabal.project                     # packages list + source-repository-package pins
|-- typeid-hs-sql/
|   |-- typeid-hs-sql.cabal
|   |-- database/v0.0.1/*.sql          # the four SQL files, embedded here
|   `-- src/TypeId/Db/Sql.hs           # exposes version, migrationFiles, sqlFiles
|-- typeid-hs-hasql-migration/         # backend 1 (hasql-migration)
|-- typeid-hs-codd/                    # backend 2 (codd)  <-- the model for this plan
|   |-- typeid-hs-codd.cabal
|   `-- src/TypeId/Db/Codd/Migration.hs
|-- README.md
|-- mori.dhall                         # project manifest (packages + dependencies)
`-- flake.nix, nix/                    # dev-shell-only Nix (GHC 9.12.4 / cabal / HLS / postgresql)
```

You will add a new sibling directory `typeid-hs-pg-migrate/`.

**The shared interface you consume (already in the tree; do not redefine it):**

```haskell
module TypeId.Db.Sql
  ( version        -- :: String, "v0.0.1"
  , migrationFiles -- :: [FilePath], ["01_uuidv7.sql","02_base32.sql","03_typeid.sql","04_operator.sql"]
  , sqlFiles       -- :: [(FilePath, ByteString)], each base name + embedded bytes, in migrationFiles order
  ) where
```

`sqlFiles` is a four-element list in the exact order migrations must run; later files depend on
objects created by earlier ones. It is statically non-empty.

**The `pg-migrate` API you will use.** These are accurate signatures and module locations,
verified against the pinned source at `/Users/shinzui/Keikaku/bokuno/pg-migrate/pg-migrate/src`
(the same repository this plan pins). Treat them as the contract; Milestone 2's REPL check will
surface any deviation.

From the safe common facade module `Database.PostgreSQL.Migrate` (re-exports the pieces below):

```haskell
-- Build a component from ordered ".sql" base names and their exact embedded bytes.
-- The migration name is the file base name with the ".sql" suffix removed.
migrationComponentFromEmbeddedSql
  :: Text                          -- component name (validated: no slash, printable ASCII, <=200 bytes)
  -> Set Text                      -- component dependency names (use Set.empty for none)
  -> NonEmpty (FilePath, ByteString)
  -> Either DefinitionError MigrationComponent

-- Validate an already dependency-ordered component sequence into a plan.
migrationPlan :: NonEmpty MigrationComponent -> Either PlanError MigrationPlan

-- Run a plan with a freshly acquired connection built from Hasql connection settings.
runMigrationPlan
  :: RunOptions
  -> Hasql.Connection.Settings.Settings
  -> MigrationPlan
  -> IO (Either MigrationError MigrationReport)

defaultRunOptions :: RunOptions   -- standard "pgmigrate" ledger, indefinite lock wait, no events

-- Report shape (all derive Show):
data MigrationReport   = MigrationReport { startedAt, finishedAt :: UTCTime
                                         , results :: NonEmpty MigrationResult
                                         , cleanupIssues :: [CleanupIssue] }
data MigrationResult   = MigrationResult { migration :: MigrationId
                                         , outcome :: MigrationOutcome
                                         , duration :: Maybe NominalDiffTime }
data MigrationOutcome  = AlreadyApplied | AppliedNow

-- Error types you will surface (all derive Show):
data DefinitionError = ...   -- invalid component/migration name or invalid SQL payload
data PlanError       = ...   -- components do not form a valid dependency-ordered plan
data MigrationError  = ...   -- acquisition/verification/execution failure while running
```

`Settings.Settings` and its constructor come from `hasql`:

```haskell
import Hasql.Connection.Settings qualified as Settings
Settings.connectionString :: Text -> Settings.Settings   -- e.g. "postgresql://user@host:port/db"
```

**How `pg-migrate`'s SQL validator treats the TypeID SQL (why this works).** `migrationComponentFromEmbeddedSql`
calls a validator (`Database.PostgreSQL.Migrate.Sql.validateSql`) on each file. The validator
rejects a UTF-8 BOM and invalid UTF-8, then a scanner tokenizes statements. Two facts make the
TypeID SQL valid:

1. The scanner treats **dollar-quoted** bodies (`$$ ... $$`) as opaque — it consumes from the
   opening delimiter to the matching close without tokenizing their contents. Every TypeID
   function body is dollar-quoted (verified: each file uses `as $$ ... $$`), so the PL/pgSQL
   `begin`/`end`/`end if;` keywords inside those bodies are **not** seen as SQL statements and
   do **not** trip the scanner's ban on explicit transaction-control commands (`BEGIN`,
   `COMMIT`, `END`, `ROLLBACK`, `SAVEPOINT`, ...).
2. None of the four files begins with a `-- pg-migrate:` directive comment or contains a `psql`
   meta-command (a line starting with `\`), and none uses `COPY ... FROM STDIN`. So each file
   scans as ordinary multi-statement **transactional** SQL (the default when there is no
   `-- pg-migrate: no-transaction` directive). Multi-statement transactional SQL is allowed.

Therefore all four files produce valid `SqlKind`, `Transactional` migrations. Milestone 2
proves this by evaluating `typeIdComponent` to `Right` at the REPL, and Milestone 3 proves the
SQL actually executes against PostgreSQL.

**The ledger.** With `defaultRunOptions`, `pg-migrate` initializes a schema named `pgmigrate`
containing (among others) a table `pgmigrate.migrations` with columns `component, migration,
position, checksum, kind, transaction_mode, status, started_at, ...`. After a successful apply,
this table holds one `status = 'applied'` row per TypeID migration. Milestone 3 queries it.

**Compatibility.** `pg-migrate` v1.1.0.0 targets GHC 9.12.4 and PostgreSQL 17/18, with
`hasql >= 1.10 && < 1.11` (from its published compatibility table). This repository already uses
GHC 9.12.4 and already resolves `hasql` 1.10.x for its other backends, so the toolchain matches.
The core `pg-migrate` library's direct dependencies are `aeson`, `base (>=4.20 && <4.22)`,
`bytestring`, `containers`, `contravariant`, `crypton`, `hasql`, `hasql-transaction (>=1.2 &&
<1.3)`, `ram (>=0.20 && <0.23)`, `text`, and `time`; under GHC 9.12.4, `base` is 4.21.x, which
is inside `pg-migrate`'s bound. These are all Hackage packages; Milestone 1 confirms they solve.

**Toolchain.** GHC 9.12.4 / `cabal` from the Nix dev shell (`flake.nix`, `nix/haskell.nix`).
This is a **dev-shell-only** flake: the dev shell provides GHC, cabal, HLS, and `pkgs.postgresql`,
and the packages are built by `cabal` inside the shell, which fetches `source-repository-package`
pins over the network. Prefix commands with `nix develop --command` if cabal/psql are not already
on your PATH. All commands run from the repository root unless noted.


## Plan of Work

Four milestones. Milestone 1 stands up the package and proves the `pg-migrate` dependency graph
resolves under GHC 9.12.4 (the riskiest build concern, given `pg-migrate` is a git pin with its
own transitive closure). Milestone 2 writes the public module and proves the embedded SQL passes
`pg-migrate`'s validator by evaluating the component to `Right`. Milestone 3 validates
end-to-end against a real PostgreSQL. Milestone 4 makes the package discoverable and documented.

There is no separate throwaway "spike" milestone: the main design unknown (does `pg-migrate`
accept the exact TypeID SQL?) has been de-risked by reading `pg-migrate`'s scanner (see Context),
and Milestone 2's REPL evaluation of `typeIdComponent` plus Milestone 3's live apply together
serve as the executable proof.

**Milestone 1 — Package skeleton and `pg-migrate` dependency resolution.** Create
`typeid-hs-pg-migrate/` with a `.cabal` depending on `typeid-hs-sql`, `pg-migrate`, `hasql`,
`text`, and `containers`. Pin `pg-migrate` in `cabal.project` via `source-repository-package`
(subdir `pg-migrate`), preserving the existing `hasql-migration` and `codd` pins, and add
`./typeid-hs-pg-migrate` to the `packages:` list. Add a temporary placeholder module so the
library has something to build. At the end of this milestone, `cabal build typeid-hs-pg-migrate`
resolves and builds an empty library — proving the dependency graph solves under GHC 9.12.4.
Acceptance: a clean `cabal build typeid-hs-pg-migrate` succeeds.

**Milestone 2 — The `TypeId.Db.PgMigrate.Migration` module.** Replace the placeholder with the
real module exposing `version`, `componentNameText`, `typeIdComponent`, `typeIdPlan`,
`TypeIdMigrateError`, and `migrateTypeId`. At the end, `cabal build typeid-hs-pg-migrate` compiles
warning-free with `-Wall`, and at the REPL `typeIdComponent` and `typeIdPlan` evaluate to `Right`
values (proving the SQL and derived names validate, and the single-component plan is well-formed).
Acceptance: clean build; `case typeIdComponent of Right _ -> True; _ -> False` is `True`;
`cabal build all` is green.

**Milestone 3 — End-to-end validation.** Stand up a throwaway PostgreSQL, apply the migrations
through `migrateTypeId defaultRunOptions`, and confirm: the report is `Right` with four
`AppliedNow` results in order; `pgmigrate.migrations` has four `applied` rows for component
`typeid`; `SELECT typeid_generate_text('user')` returns a `user_`-prefixed TypeID; and a second
`migrateTypeId` run reports all four as `AlreadyApplied` (idempotence). Acceptance: all of the
above observed.

**Milestone 4 — Documentation and manifest wiring.** Add a "Usage — pg-migrate backend" section
to `README.md`, update the package list at the top of the README to mention the third backend,
and update `mori.dhall` to add the `typeid-hs-pg-migrate` package entry and the
`shinzui/pg-migrate` dependency. Acceptance: `README.md` documents the backend with a compiling
usage example, and `mori.dhall` lists four packages and the new dependency.


## Concrete Steps

All commands run from the repository root. Prefix with `nix develop --command` if `cabal`/`psql`
are not on your PATH (for example, `nix develop --command cabal build typeid-hs-pg-migrate`).

### Milestone 1 — Package skeleton and `pg-migrate` dependency

1. Create the package directory and cabal file. Write
   `typeid-hs-pg-migrate/typeid-hs-pg-migrate.cabal`:

```cabal
cabal-version: 3.4
name: typeid-hs-pg-migrate
version: 0.1.0.0
synopsis: PostgreSQL TypeID migrations via pg-migrate
description:
  Exposes the TypeID PostgreSQL migrations (from typeid-hs-sql) as a pg-migrate
  migration component so an application can compose it into its own plan, plus a
  batteries-included helper to apply just the TypeID migrations.

license:
author: Nadeem Bitar
maintainer: nadeem@topagentnetwork.com
build-type: Simple

common common-options
  ghc-options:
    -Wall
    -Wcompat
    -Widentities
    -Wincomplete-uni-patterns
    -Wincomplete-record-updates
    -Wredundant-constraints
    -fhide-source-paths
    -Wmissing-export-lists
    -Wpartial-fields
    -Wmissing-deriving-strategies

  default-extensions:
    DataKinds
    DerivingStrategies
    LambdaCase
    OverloadedStrings

library
  import: common-options
  hs-source-dirs: src
  default-language: GHC2021
  exposed-modules:
    TypeId.Db.PgMigrate.Migration

  build-depends:
    base >=4.17 && <5,
    containers,
    hasql >=1.10 && <1.11,
    pg-migrate,
    text ^>=2.1.1,
    typeid-hs-sql,
```

2. Read the current `cabal.project`, then add the package path and the `pg-migrate` pin. Append
   `./typeid-hs-pg-migrate` to the `packages:` list and add a third `source-repository-package`
   stanza, **preserving** the existing `hasql-migration` and `codd` pins. The target result:

```text
packages:
  ./typeid-hs-sql
  ./typeid-hs-hasql-migration
  ./typeid-hs-codd
  ./typeid-hs-pg-migrate

source-repository-package
  type: git
  location: https://github.com/shinzui/hasql-migration
  tag: 4aaff6c0919d1fe8e1c248c3ce4ce05775c59c8c

source-repository-package
  type: git
  location: https://github.com/mzabani/codd
  tag: 29478ff469b1c0466a7d126d64ab3dc1dbff4756

source-repository-package
  type: git
  location: https://github.com/shinzui/pg-migrate
  tag: f39d64e354818999667d345a1452f33eb4857fc1
  subdir: pg-migrate
```

   The `pg-migrate` commit `f39d64e354818999667d345a1452f33eb4857fc1` is the peeled tag
   `v1.1.0.0`. The `subdir: pg-migrate` line is required because `pg-migrate` is a multi-package
   repository whose core library's `pg-migrate.cabal` lives in the `pg-migrate/` subdirectory.

3. Create a temporary placeholder module so the library has something to compile:

```bash
mkdir -p typeid-hs-pg-migrate/src/TypeId/Db/PgMigrate
```

   Write `typeid-hs-pg-migrate/src/TypeId/Db/PgMigrate/Migration.hs` as a placeholder:

```haskell
module TypeId.Db.PgMigrate.Migration () where
```

4. Resolve and build:

```bash
cabal build typeid-hs-pg-migrate
```

   Expected: cabal fetches and builds `pg-migrate` (subdir `pg-migrate`) and its transitive
   dependencies (`ram`, `crypton`, `hasql-transaction`, `contravariant`, ...), then builds the
   placeholder library. **If version solving fails** because a `pg-migrate` transitive dependency
   has bounds that exclude something in the GHC 9.12.4 package set, add a scoped `allow-newer`
   line to `cabal.project` and retry, for example:

```text
allow-newer: pg-migrate:base, pg-migrate:time, pg-migrate:template-haskell
```

   Record in Surprises & Discoveries whichever resolution was needed (clean solve, or which
   `allow-newer`/extra pin), because Milestone 4 documents the final dependency story.

### Milestone 2 — The real module

5. Replace the placeholder with the real
   `typeid-hs-pg-migrate/src/TypeId/Db/PgMigrate/Migration.hs`:

```haskell
module TypeId.Db.PgMigrate.Migration
  ( version,
    componentNameText,
    typeIdComponent,
    typeIdPlan,
    TypeIdMigrateError (..),
    migrateTypeId,
  )
where

import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Text (Text)
import Database.PostgreSQL.Migrate
  ( DefinitionError,
    MigrationComponent,
    MigrationError,
    MigrationPlan,
    MigrationReport,
    PlanError,
    RunOptions,
    migrationComponentFromEmbeddedSql,
    migrationPlan,
    runMigrationPlan,
  )
import Hasql.Connection.Settings qualified as Settings
import TypeId.Db.Sql qualified as Sql

-- | The schema version these migrations implement, sourced from typeid-hs-sql.
version :: String
version = Sql.version

-- | The stable pg-migrate component name that owns the TypeID migrations.
-- Exported so a consuming application can declare a dependency on it (for
-- example @Set.singleton componentNameText@) when composing its own plan.
componentNameText :: Text
componentNameText = "typeid"

-- | The TypeID migrations as a pg-migrate component, built from the ordered SQL
-- exposed by typeid-hs-sql. Each SQL file's base name becomes a migration name
-- by dropping the @.sql@ suffix (e.g. @01_uuidv7.sql@ becomes migration
-- @01_uuidv7@), so the durable migration identities are @typeid/01_uuidv7@,
-- @typeid/02_base32@, @typeid/03_typeid@, and @typeid/04_operator@.
--
-- Returns 'Left' only if the embedded SQL or a derived name is invalid, which
-- cannot happen for the fixed, tested SQL shipped by typeid-hs-sql; in practice
-- this is always 'Right'.
typeIdComponent :: Either DefinitionError MigrationComponent
typeIdComponent =
  migrationComponentFromEmbeddedSql
    componentNameText
    Set.empty
    -- Sql.sqlFiles is statically non-empty (four entries), so fromList is total here.
    (NonEmpty.fromList Sql.sqlFiles)

-- | A single-component plan containing only the TypeID migrations, for the
-- batteries-included case where an application applies just these migrations.
-- Applications that compose TypeID with their own migrations should instead use
-- 'typeIdComponent' directly and build their own plan with 'migrationPlan'.
typeIdPlan :: Either DefinitionError (Either PlanError MigrationPlan)
typeIdPlan = do
  component <- typeIdComponent
  pure (migrationPlan (component :| []))

-- | Flattened failure for the batteries-included 'migrateTypeId' runner.
data TypeIdMigrateError
  = -- | The embedded SQL or a derived migration name was invalid (never happens
    -- for the shipped SQL).
    TypeIdDefinitionError DefinitionError
  | -- | The single-component plan was rejected (never happens for one component).
    TypeIdPlanError PlanError
  | -- | pg-migrate failed while applying the plan against the database.
    TypeIdRunError MigrationError
  deriving stock (Show)

-- | Batteries-included entry point: build the single-component TypeID plan and
-- apply it against the database described by the given Hasql connection
-- settings, using the supplied pg-migrate 'RunOptions' (use 'defaultRunOptions'
-- for the standard @pgmigrate@ ledger, indefinite lock wait, and no events).
-- Applies the migrations in order under pg-migrate's advisory lock and records
-- them in the ledger; rerunning is idempotent (already-applied migrations are
-- reported as 'AlreadyApplied').
migrateTypeId ::
  RunOptions ->
  Settings.Settings ->
  IO (Either TypeIdMigrateError MigrationReport)
migrateTypeId options settings =
  case typeIdComponent of
    Left definitionError -> pure (Left (TypeIdDefinitionError definitionError))
    Right component ->
      case migrationPlan (component :| []) of
        Left planError -> pure (Left (TypeIdPlanError planError))
        Right plan ->
          first TypeIdRunError <$> runMigrationPlan options settings plan
```

6. Build the package and the whole project:

```bash
cabal build typeid-hs-pg-migrate
cabal build all
```

   Expected: clean compile with no warnings. Resolve any `-Wall` warnings (for example, drop an
   import GHC reports as unused). If `bytestring` is reported as a hidden direct dependency, add
   it to `build-depends`; the code above does not import `Data.ByteString` directly, so it should
   not be needed.

7. Prove the SQL validates and the plan is well-formed at the REPL:

```bash
cabal repl typeid-hs-pg-migrate
```

```haskell
import TypeId.Db.PgMigrate.Migration
:type typeIdComponent
-- typeIdComponent :: Either DefinitionError MigrationComponent
case typeIdComponent of Right _ -> "component ok"; Left e -> "ERROR: " <> show e
case typeIdPlan of Right (Right _) -> "plan ok"; other -> "ERROR: " <> show other
version
```

   Expected: `"component ok"`, `"plan ok"`, and `"v0.0.1"`. If `typeIdComponent` is `Left`,
   the printed `DefinitionError` names the offending file/name/SQL — record it in Surprises &
   Discoveries and reconcile against `pg-migrate`'s validator before proceeding.

### Milestone 3 — End-to-end validation

8. Stand up a throwaway PostgreSQL:

```bash
export PGDATA="$(mktemp -d)/pgdata"
initdb -U postgres "$PGDATA" >/dev/null
pg_ctl -D "$PGDATA" -o "-p 5599" -l "$PGDATA/log" start
createdb -U postgres -p 5599 typeid_pgmigrate_test
```

9. Apply the migrations through the real entry point:

```bash
cabal repl typeid-hs-pg-migrate
```

```haskell
:set -XOverloadedStrings
import Database.PostgreSQL.Migrate (defaultRunOptions)
import Hasql.Connection.Settings qualified as Settings
import TypeId.Db.PgMigrate.Migration (migrateTypeId)
report <- migrateTypeId defaultRunOptions (Settings.connectionString "postgresql://postgres@localhost:5599/typeid_pgmigrate_test")
report
```

   Expected: a `Right (MigrationReport { ... })` whose `results` is a four-element list of
   `MigrationResult` values, each with `outcome = AppliedNow`, for migrations
   `typeid/01_uuidv7`, `typeid/02_base32`, `typeid/03_typeid`, `typeid/04_operator`, and
   `cleanupIssues = []`. It must not throw.

10. Confirm the ledger recorded all four migrations in order:

```bash
psql -U postgres -p 5599 -d typeid_pgmigrate_test \
  -c "SELECT component, migration, position, status FROM pgmigrate.migrations ORDER BY component, position;"
```

   Expected: four rows, all `component = typeid`, `status = applied`, positions `1`..`4`, in
   migration order `01_uuidv7`, `02_base32`, `03_typeid`, `04_operator`:

```text
 component | migration  | position | status
-----------+------------+----------+---------
 typeid    | 01_uuidv7  |        1 | applied
 typeid    | 02_base32  |        2 | applied
 typeid    | 03_typeid  |        3 | applied
 typeid    | 04_operator|        4 | applied
(4 rows)
```

11. Confirm the TypeID objects were installed (proves the SQL actually executed):

```bash
psql -U postgres -p 5599 -d typeid_pgmigrate_test -c "SELECT typeid_generate_text('user');"
```

   Expected: one row whose value looks like `user_01h455vb4pex5vsknk084sn02q`.

12. Prove idempotence — rerun the apply in the same REPL (or a fresh one) and confirm every
    migration is now `AlreadyApplied`:

```haskell
report2 <- migrateTypeId defaultRunOptions (Settings.connectionString "postgresql://postgres@localhost:5599/typeid_pgmigrate_test")
report2
```

    Expected: a `Right (MigrationReport { ... })` whose four `results` all have
    `outcome = AlreadyApplied`. Then tear down:

```bash
pg_ctl -D "$PGDATA" stop
```

### Milestone 4 — Documentation and manifest wiring

13. Update `README.md`:
    - In the "Packages" section near the top, add a bullet for `typeid-hs-pg-migrate` describing
      it as the `pg-migrate` backend (a project standardized on the `pg-migrate` library composes
      the TypeID component into its own plan), and update the surrounding prose that currently
      says "two interchangeable backends" / "three packages" to reflect three backends over the
      shared core (four packages total).
    - Add a "Usage — pg-migrate backend" section. Include a component-composition example and a
      batteries-included example. Use these exact, compiling snippets:

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Set as Set
import Database.PostgreSQL.Migrate
  ( DefinitionError,
    MigrationPlan,
    PlanError,
    migrationComponentFromEmbeddedSql,
    migrationPlan,
  )
import TypeId.Db.PgMigrate.Migration (componentNameText, typeIdComponent)

-- Compose the TypeID component with your application's own component into one
-- plan. Your component declares a dependency on componentNameText ("typeid"),
-- and TypeID is listed first, so its objects exist before your migrations run.
appPlan :: Either DefinitionError (Either PlanError MigrationPlan)
appPlan = do
  typeid <- typeIdComponent
  app <-
    migrationComponentFromEmbeddedSql
      "app"
      (Set.singleton componentNameText)   -- "typeid" must be applied first
      (("0001-create-users.sql", "CREATE TABLE users (id typeid PRIMARY KEY);") :| [])
  pure (migrationPlan (typeid :| [app]))
```

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Database.PostgreSQL.Migrate (defaultRunOptions)
import qualified Hasql.Connection.Settings as Settings
import TypeId.Db.PgMigrate.Migration (migrateTypeId)

main :: IO ()
main = do
  -- Batteries-included: apply just the TypeID migrations.
  result <- migrateTypeId defaultRunOptions
              (Settings.connectionString "postgresql://postgres@localhost/mydb")
  case result of
    Right report -> print report          -- MigrationReport with per-migration outcomes
    Left err     -> print err             -- TypeIdMigrateError
```

    Note in the prose: the library ships no `pgmigrate` schema or ledger of its own — the
    consuming application owns the database and the `RunOptions` (ledger schema, lock wait,
    statement timeout). Applications composing TypeID with their own migrations should use
    `typeIdComponent` and build one plan with `migrationPlan`, declaring `componentNameText`
    ("typeid") as a dependency where they need TypeID objects to exist first.

14. Update `mori.dhall`:
    - Add a fourth `Schema.Package` entry to the `packages` list:

```dhall
, Schema.Package::{
  , name = "typeid-hs-pg-migrate"
  , type = Schema.PackageType.Library
  , language = Schema.Language.Haskell
  , path = Some "typeid-hs-pg-migrate"
  , description = Some "PostgreSQL TypeID migrations via pg-migrate"
  }
```

    - Add `"shinzui/pg-migrate"` to the `dependencies` list (alongside the existing
      `shinzui/hasql-migration`, `hasql/hasql`, `ekmett/lens`, `mzabani/codd`).
    - Optionally update the top-level `description` to mention three backends.

15. Rebuild everything and run the formatter/pre-commit as configured:

```bash
cabal build all
```

   Expected: green build. Commit the milestone (see Interfaces and Dependencies for the trailer
   requirement).


## Validation and Acceptance

This plan is complete when all of the following hold.

1. A clean build of the new package succeeds, proving the `pg-migrate` dependency resolves under
   GHC 9.12.4:

```bash
cabal clean && cabal build typeid-hs-pg-migrate
```

2. `TypeId.Db.PgMigrate.Migration` exports `version`, `componentNameText`, `typeIdComponent`,
   `typeIdPlan`, `TypeIdMigrateError`, and `migrateTypeId` with the signatures in Milestone 2,
   and both smart-constructed values are `Right`:

```haskell
:type typeIdComponent
-- typeIdComponent :: Either DefinitionError MigrationComponent
case typeIdComponent of Right _ -> True; _ -> False   -- True
case typeIdPlan of Right (Right _) -> True; _ -> False -- True
```

3. Applying the migrations against a live PostgreSQL installs the TypeID objects and records the
   ledger (Milestone 3): `migrateTypeId defaultRunOptions <settings>` returns
   `Right (MigrationReport ...)` with four `AppliedNow` results in order; `pgmigrate.migrations`
   holds four `applied` rows for component `typeid` at positions 1..4;
   `SELECT typeid_generate_text('user')` returns a `user_`-prefixed TypeID; and a second run
   returns four `AlreadyApplied` results.

4. `cabal build all` is green, `README.md` documents the `pg-migrate` backend with the compiling
   usage snippets above, and `mori.dhall` lists four packages plus the `shinzui/pg-migrate`
   dependency.

When these hold, fill in Outcomes & Retrospective and perform the ADR distillation pass
(create `docs/adr/` with an entry capturing the durable "N backends over one SQL core"
architecture and the pinned-fork policy if that context warrants a durable home).


## Idempotence and Recovery

The `.cabal`, `cabal.project`, `.hs`, `README.md`, and `mori.dhall` writes are idempotent; each
step describes the target end-state, so re-running it converges. `cabal clean && cabal build` is
always safe to repeat.

The throwaway PostgreSQL is disposable: `pg_ctl -D "$PGDATA" stop` and removing `$PGDATA` fully
resets it; re-running `initdb`/`createdb` from scratch is the recovery path. Applying the
migrations twice against the same database is safe by design — `pg-migrate` records applied
migrations in its ledger and reports already-applied ones as `AlreadyApplied` instead of
re-running them (proven in Milestone 3 step 12). For a clean slate, drop and recreate
`typeid_pgmigrate_test` (which also drops the `pgmigrate` ledger schema).

If `pg-migrate` fails to fetch or solve, the recovery path is, in order: (a) confirm the pinned
commit `f39d64e354818999667d345a1452f33eb4857fc1` is fetchable and that `subdir: pg-migrate` is
present (without it, cabal cannot find `pg-migrate.cabal`); (b) add scoped `allow-newer` entries
for whichever transitive bound blocks the solve; (c) if a transitive dependency (`ram`,
`crypton`, `hasql-transaction`) itself needs a newer/older revision than Hackage's default
solve chooses, add a targeted `constraints:` or `source-repository-package` pin. Record whichever
was needed in Surprises & Discoveries.

The placeholder module in Milestone 1 must be fully replaced by the real module in Milestone 2;
do not ship `module TypeId.Db.PgMigrate.Migration () where`.


## Interfaces and Dependencies

**Consumes (hard dependency, already in the tree):** `TypeId.Db.Sql` from package `typeid-hs-sql`
(`version :: String`, `migrationFiles :: [FilePath]`, `sqlFiles :: [(FilePath, ByteString)]`).

**Libraries:** `pg-migrate` (the migration engine; module `Database.PostgreSQL.Migrate` provides
`migrationComponentFromEmbeddedSql`, `migrationPlan`, `runMigrationPlan`, `defaultRunOptions`,
`RunOptions`, `MigrationComponent`, `MigrationPlan`, `MigrationReport`, `MigrationResult`,
`MigrationOutcome`, `DefinitionError`, `PlanError`, `MigrationError`), `hasql` (for
`Hasql.Connection.Settings.Settings`/`connectionString`), `containers` (for `Data.Set`), `text`
(for `Text`), and `base` (for `Data.List.NonEmpty` and `Data.Bifunctor.first`). Additional
transitive constraints (`crypton`, `ram`, `hasql-transaction`, `contravariant`, `aeson`, `time`)
come in via `pg-migrate`; add them to `build-depends` only if the compiler reports one as a
direct import (it should not).

**Public interface produced by this plan:** module `TypeId.Db.PgMigrate.Migration` in package
`typeid-hs-pg-migrate`, exporting:

```haskell
version           :: String
componentNameText :: Text
typeIdComponent   :: Either DefinitionError MigrationComponent
typeIdPlan        :: Either DefinitionError (Either PlanError MigrationPlan)
data TypeIdMigrateError
  = TypeIdDefinitionError DefinitionError
  | TypeIdPlanError PlanError
  | TypeIdRunError MigrationError
migrateTypeId ::
  RunOptions -> Hasql.Connection.Settings.Settings ->
  IO (Either TypeIdMigrateError MigrationReport)
```

**Shared build files:** appends `./typeid-hs-pg-migrate` to `cabal.project`'s `packages:` list
and adds a `source-repository-package` pin for `pg-migrate` (subdir `pg-migrate`), preserving the
existing `hasql-migration` and `codd` pins. Updates `mori.dhall` (fourth package entry +
`shinzui/pg-migrate` dependency) and `README.md` (pg-migrate backend section). No Nix changes are
needed: the flake is dev-shell-only and `cabal` fetches the new pin.

**Git trailers.** Every commit made while working on this plan must include both trailers:

```text
ExecPlan: docs/plans/5-create-typeid-hs-pg-migrate-package.md
Intention: intention_01ky0sdvgze7ztnt6p3vvta4w4
```
</content>
</invoke>
