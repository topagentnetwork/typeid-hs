---
id: 2
slug: rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql
title: "Rename and refactor typeid-hs-hasql-migration onto typeid-hs-sql"
kind: exec-plan
created_at: 2026-06-06T14:28:17Z
intention: "intention_01kteks21kes6rcgdxpc96x5s2"
master_plan: "docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md"
---

# Rename and refactor typeid-hs-hasql-migration onto typeid-hs-sql

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The repository's existing `hasql-migration`-based code currently lives in a single package called
`typeid-hs`, which embeds its own SQL. A companion plan,
`docs/plans/1-create-typeid-hs-sql-shared-core-and-multi-package-layout.md`, has already extracted that
SQL into a new tool-agnostic package, `typeid-hs-sql`, and converted the repository into a
multi-package cabal project.

This plan moves the existing `hasql-migration` code into its own package, **renames** that package
from `typeid-hs` to `typeid-hs-hasql-migration`, and rewires its one embedding module to consume
`typeid-hs-sql` instead of embedding the SQL a second time. The package's public modules and runtime
behavior are preserved exactly: a downstream user still imports `TypeId.Db.Migration` and calls
`migrate`, `validate`, `getMigrations`, `migrations`, and `version` with the same types and the same
effects. The only user-visible change is the package name in `build-depends` — this is a deliberate
breaking rename (see the MasterPlan Decision Log).

You can see it working by building `typeid-hs-hasql-migration` and confirming the public API is
unchanged in GHCi (the same function signatures load), and, if a PostgreSQL instance is available, by
running the migrations against it and confirming the TypeID objects are created — exactly as before.

This plan is part of the initiative in
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md`. It has a hard
dependency on plan 1: the module `TypeId.Db.Sql` (in package `typeid-hs-sql`) must already exist and
export `version :: String`, `migrationFiles :: [FilePath]`, and `sqlFiles :: [(FilePath, ByteString)]`.
If that module does not yet exist, stop and implement plan 1 first.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone 1: `typeid-hs-hasql-migration/` package created; sources moved; `.cabal` renamed
- [ ] Milestone 1: old root `typeid-hs.cabal` and `src/` removed; `cabal.project` updated
- [ ] Milestone 2: `V0_0_1` rewritten to consume `typeid-hs-sql` (`sqlFiles`/`version`); builds clean
- [ ] Milestone 3: public API unchanged (GHCi `:type` checks); behavior validated against PostgreSQL


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Keep all existing module names (`TypeId.Db.Migration`, `TypeId.Db.Migration.Migrations`,
  `TypeId.Db.Migration.Migrations.V0_0_1`, `TypeId.Db.Migration.Sessions`,
  `TypeId.Db.Migration.Statements`, `TypeId.Db.Migration.Transactions`) unchanged; only the package
  name changes.
  Rationale: This minimizes churn for downstream consumers — after updating the package name in
  `build-depends`, their `import` lines and call sites compile unchanged.
  Date: 2026-06-06

- Decision: `V0_0_1` builds its `MigrationScript` names with the same `version </> fileName` path
  (e.g. `"v0.0.1/01_uuidv7.sql"`) it used before.
  Rationale: `hasql-migration` records the migration name in its schema-tracking table; preserving the
  exact name keeps a database migrated by the old `typeid-hs` package consistent with one migrated by
  the renamed package, so already-migrated databases are not re-run or flagged.
  Date: 2026-06-06


## Context and Orientation

Assume no prior knowledge of this repository beyond the working tree.

**State of the repository at the start of this plan (after plan 1).** Plan 1 created a multi-package
layout. The tree looks like this:

```text
.
|-- cabal.project                 # multi-package; lists ./typeid-hs-sql; keeps the hasql-migration git pin
|-- typeid-hs.cabal               # OLD single-package definition, still on disk, NOT listed in cabal.project
|-- src/                          # OLD source tree, still on disk
|   `-- TypeId/Db/Migration/...
|-- typeid-hs-sql/                # NEW shared-core package created by plan 1
|   |-- typeid-hs-sql.cabal
|   |-- database/v0.0.1/*.sql     # the SQL now lives here (moved out of the old root database/)
|   `-- src/TypeId/Db/Sql.hs      # exposes version, migrationFiles, sqlFiles
`-- flake.nix, nix/, README.md, mori.dhall
```

Your job is to turn the OLD `typeid-hs.cabal` + `src/` into a new package directory
`typeid-hs-hasql-migration/`, renamed and refactored, and to delete the OLD copies.

**The shared interface you will consume** (defined by plan 1, do not redefine it):

```haskell
module TypeId.Db.Sql
  ( version        -- :: String, "v0.0.1"
  , migrationFiles -- :: [FilePath], ["01_uuidv7.sql","02_base32.sql","03_typeid.sql","04_operator.sql"]
  , sqlFiles       -- :: [(FilePath, ByteString)], each name + bytes, in migrationFiles order
  ) where
```

**The existing source modules (their current full contents).** These move verbatim into the new
package, except `V0_0_1.hs` which is rewritten in Milestone 2. They are reproduced here so this plan is
self-contained.

`src/TypeId/Db/Migration.hs`:

```haskell
module TypeId.Db.Migration
  ( migrate,
    validate,
    getMigrations,
    M.version,
    migrations,
  )
where

import Hasql.Migration (MigrationCommand (MigrationInitialization), MigrationError, SchemaMigration)
import Hasql.Session (Session)
import TypeId.Db.Migration.Migrations qualified as M
import TypeId.Db.Migration.Sessions qualified as S

migrate :: Session (Either MigrationError ())
migrate = S.migrate migrations

validate :: Session (Either [MigrationError] ())
validate = S.validate migrations

getMigrations :: Session [SchemaMigration]
getMigrations = S.getMigrations

migrations :: [MigrationCommand]
migrations = MigrationInitialization : M.migrations
```

`src/TypeId/Db/Migration/Migrations.hs`:

```haskell
module TypeId.Db.Migration.Migrations
  ( migrations,
    Version,
    version,
  )
where

import Hasql.Migration (MigrationCommand)
import TypeId.Db.Migration.Migrations.V0_0_1 qualified as V001

migrations :: [MigrationCommand]
migrations = V001.migrations

type Version = String

version :: Version
version = V001.version
```

`src/TypeId/Db/Migration/Migrations/V0_0_1.hs` (the module you will rewrite in Milestone 2 — current
contents shown so you know what it does today):

```haskell
{-# LANGUAGE TemplateHaskell #-}

module TypeId.Db.Migration.Migrations.V0_0_1
  ( migrations,
    version,
  )
where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedDir, makeRelativeToProject)
import Data.Maybe (fromJust)
import Hasql.Migration (MigrationCommand (MigrationScript))
import System.FilePath ((</>))

version :: String
version = "v0.0.1"

migrations :: [MigrationCommand]
migrations = mkMigration <$> migrationFiles
  where
    mkMigration filePath =
      MigrationScript (version </> filePath) . fromJust $
        lookup filePath files

files :: [(FilePath, ByteString)]
files = $(makeRelativeToProject "database/v0.0.1" >>= embedDir)

migrationFiles :: [FilePath]
migrationFiles =
  [ "01_uuidv7.sql",
    "02_base32.sql",
    "03_typeid.sql",
    "04_operator.sql"
  ]
```

`src/TypeId/Db/Migration/Sessions.hs`:

```haskell
module TypeId.Db.Migration.Sessions (migrate, validate, getMigrations) where

import Hasql.Migration (MigrationCommand, MigrationError, SchemaMigration)
import Hasql.Migration qualified as M
import Hasql.Session (Session)
import Hasql.Transaction.Sessions
import TypeId.Db.Migration.Transactions qualified as T

migrate :: (Foldable t) => t MigrationCommand -> Session (Either MigrationError ())
migrate commands = transaction Serializable Write (T.migrate commands)

validate ::
  (Applicative t, Monoid (t MigrationError), Traversable t) =>
  t MigrationCommand ->
  Session (Either (t MigrationError) ())
validate commands = transaction ReadCommitted Read (T.validate commands)

getMigrations :: Session [SchemaMigration]
getMigrations = transaction ReadCommitted Read M.getMigrations
```

`src/TypeId/Db/Migration/Statements.hs` and `src/TypeId/Db/Migration/Transactions.hs` are moved
verbatim with no changes. (Their contents involve `getSearchPath`/`setSearchPath` statements and the
`migrate`/`validate` transaction logic; they do not embed SQL and need no edits. Move them as-is — they
travel inside the `src/` tree you `git mv` in Milestone 1.)

**The existing `typeid-hs.cabal` (full current content)** — you will base the new `.cabal` on this:

```cabal
cabal-version: 3.4
name: typeid-hs
version: 0.1.0.0
license:
author: Nadeem Bitar
maintainer: nadeem@topagentnetwork.com
build-type: Simple
extra-source-files: database/**/*.sql

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
    DeriveAnyClass
    DerivingStrategies
    DuplicateRecordFields
    LambdaCase
    OverloadedLabels
    OverloadedStrings

library
  import: common-options
  hs-source-dirs: src
  default-language: GHC2021
  ghc-options: -threaded
  exposed-modules:
    TypeId.Db.Migration
    TypeId.Db.Migration.Migrations
    TypeId.Db.Migration.Migrations.V0_0_1
    TypeId.Db.Migration.Sessions
    TypeId.Db.Migration.Statements
    TypeId.Db.Migration.Transactions

  build-depends:
    base >=4.17 && <5,
    bytestring ^>=0.12,
    file-embed,
    filepath,
    hasql,
    hasql-migration,
    hasql-transaction,
    lens ^>=5.3,
    text ^>=2.1.1,
    transformers,
    validation >=1.2,
```

**Toolchain.** GHC 9.12.4 / `cabal` from the Nix dev shell (`flake.nix`, `nix/haskell.nix`). Prefix
commands with `nix develop` if cabal is not on your PATH. The `cabal.project` still pins the
`shinzui/hasql-migration` fork via `source-repository-package`; that pin is required by this package —
preserve it.

**Term definitions.**
- *`hasql-migration`*: a Haskell library that applies SQL migrations through a `hasql` `Session`. A
  `MigrationCommand` is its representation of one migration step; `MigrationScript name sql` is a
  named SQL script, and `MigrationInitialization` sets up its bookkeeping table.
- *`Session`*: `hasql`'s monad for running statements against a connection.


## Plan of Work

Three milestones. Milestone 1 is a pure move + rename (no behavior change). Milestone 2 is the one real
refactor: the embedding module starts consuming `typeid-hs-sql`. Milestone 3 proves the public API and
behavior are unchanged.

**Milestone 1 — Move and rename the package.** Create `typeid-hs-hasql-migration/`, move `src/` into it,
write `typeid-hs-hasql-migration/typeid-hs-hasql-migration.cabal` (the old `.cabal` content with the
name changed, `typeid-hs-sql` added, and `file-embed`/`extra-source-files` removed), delete the old root
`typeid-hs.cabal`, and add `./typeid-hs-hasql-migration` to `cabal.project`. Because the SQL no longer
lives at the old embedded path, the package does not build until Milestone 2 rewires `V0_0_1`; therefore
Milestone 1's acceptance is **structural** (directories moved, files removed, `cabal.project` updated),
verified by the file-existence checks in Concrete Steps. Build acceptance arrives at Milestone 2.

**Milestone 2 — Refactor `V0_0_1` onto `typeid-hs-sql`.** Rewrite
`typeid-hs-hasql-migration/src/TypeId/Db/Migration/Migrations/V0_0_1.hs` to import `TypeId.Db.Sql` and
build its `MigrationCommand` list from `sqlFiles`/`migrationFiles`/`version` instead of embedding. The
`TemplateHaskell` pragma and the `file-embed` import are gone. At the end,
`cabal build typeid-hs-hasql-migration` succeeds.

**Milestone 3 — Verify unchanged API and behavior.** Confirm in GHCi that the public functions have the
same types as before, and (if PostgreSQL is available) run the migrations end-to-end and confirm the
TypeID objects are created.


## Concrete Steps

All commands from the repository root; prefix with `nix develop` if needed.

### Milestone 1

1. Create the new package directory and move the source tree into it:

```bash
mkdir -p typeid-hs-hasql-migration
git mv src typeid-hs-hasql-migration/src
```

2. Remove the old root package definition (its content now lives in the new `.cabal` you write next):

```bash
git rm typeid-hs.cabal
```

3. Create `typeid-hs-hasql-migration/typeid-hs-hasql-migration.cabal`. This is the old content with
   three changes: the `name` is `typeid-hs-hasql-migration`; `extra-source-files` and the `file-embed`
   dependency are removed (the SQL is no longer embedded here — it comes from `typeid-hs-sql`); and
   `typeid-hs-sql` is added to `build-depends`. `filepath` is kept because `V0_0_1` still uses
   `System.FilePath.(</>)` to build migration names:

```cabal
cabal-version: 3.4
name: typeid-hs-hasql-migration
version: 0.1.0.0
synopsis: PostgreSQL TypeID migrations via hasql-migration
description:
  Applies the TypeID PostgreSQL migrations (from typeid-hs-sql) using the
  hasql-migration library. Renamed from the package formerly known as typeid-hs.
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
    DeriveAnyClass
    DerivingStrategies
    DuplicateRecordFields
    LambdaCase
    OverloadedLabels
    OverloadedStrings

library
  import: common-options
  hs-source-dirs: src
  default-language: GHC2021
  ghc-options: -threaded
  exposed-modules:
    TypeId.Db.Migration
    TypeId.Db.Migration.Migrations
    TypeId.Db.Migration.Migrations.V0_0_1
    TypeId.Db.Migration.Sessions
    TypeId.Db.Migration.Statements
    TypeId.Db.Migration.Transactions

  build-depends:
    base >=4.17 && <5,
    bytestring ^>=0.12,
    filepath,
    hasql,
    hasql-migration,
    hasql-transaction,
    lens ^>=5.3,
    text ^>=2.1.1,
    transformers,
    typeid-hs-sql,
    validation >=1.2,
```

4. Add this package to `cabal.project`. Read the current file first (plan 1 left it listing
   `./typeid-hs-sql`), then append `./typeid-hs-hasql-migration` under `packages:`, preserving the
   `source-repository-package` pin. The result must be:

```text
packages:
  ./typeid-hs-sql
  ./typeid-hs-hasql-migration

source-repository-package
  type: git
  location: https://github.com/shinzui/hasql-migration
  tag: 4aaff6c0919d1fe8e1c248c3ce4ce05775c59c8c
```

5. Structural check for Milestone 1 (the package will not yet build — that is Milestone 2):

```bash
test -f typeid-hs-hasql-migration/typeid-hs-hasql-migration.cabal && \
test -f typeid-hs-hasql-migration/src/TypeId/Db/Migration.hs && \
test ! -e typeid-hs.cabal && test ! -d src && \
echo "Milestone 1 structure OK"
```

   Expected: prints `Milestone 1 structure OK`.

### Milestone 2

6. Rewrite `typeid-hs-hasql-migration/src/TypeId/Db/Migration/Migrations/V0_0_1.hs` to consume
   `typeid-hs-sql`. The new content (no `TemplateHaskell`, no `file-embed`; it imports `TypeId.Db.Sql`
   and uses its `sqlFiles`/`version`/`migrationFiles`):

```haskell
module TypeId.Db.Migration.Migrations.V0_0_1
  ( migrations,
    version,
  )
where

import Data.Maybe (fromJust)
import Hasql.Migration (MigrationCommand (MigrationScript))
import System.FilePath ((</>))
import TypeId.Db.Sql qualified as Sql

-- | The schema version, sourced from typeid-hs-sql.
version :: String
version = Sql.version

-- | The ordered hasql-migration commands for v0.0.1, built from the SQL bytes
-- exposed by typeid-hs-sql. Each migration is named "v0.0.1/<file>" exactly as
-- before, so databases migrated by the previous typeid-hs package remain
-- consistent.
migrations :: [MigrationCommand]
migrations = mkMigration <$> Sql.migrationFiles
  where
    mkMigration filePath =
      MigrationScript (version </> filePath) . fromJust $
        lookup filePath Sql.sqlFiles
```

   This preserves the exact migration names (`version </> filePath`, e.g. `"v0.0.1/01_uuidv7.sql"`) and
   the exact ordering (driven by `Sql.migrationFiles`). `fromJust (lookup filePath Sql.sqlFiles)` is
   safe because `Sql.migrationFiles` and `Sql.sqlFiles` share the same keys by construction.

7. Build the package:

```bash
cabal build typeid-hs-hasql-migration
```

   Expected: clean compile. If you see an error that `Data.FileEmbed`/`file-embed` is missing, a stale
   import remains — re-check that the new `V0_0_1.hs` has no `file-embed` references and that the
   `.cabal` no longer lists `file-embed`. If you see `Could not find module TypeId.Db.Sql`, plan 1 is
   not complete or `typeid-hs-sql` was not added to `build-depends`.

8. Build everything to confirm the multi-package project is coherent:

```bash
cabal build all
```

   Expected: both `typeid-hs-sql` and `typeid-hs-hasql-migration` build.

### Milestone 3

9. Confirm the public API types are unchanged. Open a REPL and check each exported value's type:

```bash
cabal repl typeid-hs-hasql-migration
```

   Inside the REPL:

```haskell
import TypeId.Db.Migration
:type migrate
:type validate
:type getMigrations
:type migrations
version
```

   Expected (these must match the pre-rename signatures exactly):

```text
ghci> :type migrate
migrate :: Session (Either MigrationError ())
ghci> :type validate
validate :: Session (Either [MigrationError] ())
ghci> :type getMigrations
getMigrations :: Session [SchemaMigration]
ghci> :type migrations
migrations :: [MigrationCommand]
ghci> version
"v0.0.1"
```

   Exit with `:quit`.

10. (Behavioral, requires PostgreSQL.) The Nix dev shell provides `pkgs.postgresql`. Start a throwaway
    database and run the migrations end-to-end. One reproducible path:

```bash
export PGDATA="$(mktemp -d)/pgdata"
initdb -U postgres "$PGDATA" >/dev/null
pg_ctl -D "$PGDATA" -o "-p 5599" -l "$PGDATA/log" start
createdb -U postgres -p 5599 typeid_test
```

    Then run a tiny driver from a REPL against that database (the same code as the README's "Running
    Migrations" example, pointed at port 5599):

```bash
cabal repl typeid-hs-hasql-migration
```

```haskell
import Hasql.Connection (acquire, release)
import Hasql.Session (run)
import qualified TypeId.Db.Migration as Migration
Right conn <- acquire "host=localhost port=5599 dbname=typeid_test user=postgres"
res <- run Migration.migrate conn
res
```

    Expected: `res` is `Right (Right ())`, meaning the session ran and the migration succeeded.

11. Confirm the TypeID objects exist (proves the SQL actually applied, not just that the call returned):

```bash
psql -U postgres -p 5599 -d typeid_test -c "SELECT typeid_generate_text('user');"
```

    Expected: one row whose value looks like `user_01h455vb4pex5vsknk084sn02q` (a `user_` prefix followed
    by 26 base32 characters). Tear down the throwaway database afterward:

```bash
pg_ctl -D "$PGDATA" stop
```


## Validation and Acceptance

This plan is complete when:

1. `cabal build all` succeeds from clean, with `typeid-hs-hasql-migration` building with no warnings:

```bash
cabal clean && cabal build all
```

2. The public API of `TypeId.Db.Migration` is the same as before: `migrate`, `validate`,
   `getMigrations`, `migrations`, and `version` have the signatures shown in Milestone 3 step 9.

3. The package name is `typeid-hs-hasql-migration` and the old `typeid-hs` package no longer exists:

```bash
test ! -e typeid-hs.cabal && test ! -d src && \
grep -q "name: typeid-hs-hasql-migration" typeid-hs-hasql-migration/typeid-hs-hasql-migration.cabal && \
echo "rename OK"
```

4. (If PostgreSQL was available) the end-to-end run returned `Right (Right ())` and
   `typeid_generate_text('user')` produced a `user_`-prefixed TypeID, as in Milestone 3 steps 10–11.

When these hold, update the MasterPlan Exec-Plan Registry to mark EP-2 Complete and check off the EP-2
entries in the MasterPlan Progress section. Record in the MasterPlan Surprises & Discoveries section
anything that affected the shared `cabal.project` or the `TypeId.Db.Sql` interface.


## Idempotence and Recovery

The moves and removals in Milestone 1 are not idempotent (re-running `git mv src ...` or
`git rm typeid-hs.cabal` after they have succeeded fails). Before re-running, check whether
`typeid-hs-hasql-migration/src` already exists and whether `typeid-hs.cabal` is already gone, and skip
the corresponding step. The `.cabal`, `.hs`, and `cabal.project` writes are idempotent. `cabal clean &&
cabal build` is always safe to repeat. The throwaway PostgreSQL in Milestone 3 is fully disposable — if
a run leaves it half-set-up, `pg_ctl -D "$PGDATA" stop` and removing `$PGDATA` resets it.

If you need to abort before committing, `git status` shows the moves; `git restore --staged --worktree
.` (and `git checkout -- typeid-hs.cabal src` if needed) recovers the pre-plan state, since all changes
here are tracked moves and edits.


## Interfaces and Dependencies

**Consumes (hard dependency on plan 1):** `TypeId.Db.Sql` from package `typeid-hs-sql`, specifically
`version :: String`, `migrationFiles :: [FilePath]`, and `sqlFiles :: [(FilePath, ByteString)]`. This
plan does not redefine those; it imports them.

**Libraries this package depends on:** `base`, `bytestring`, `filepath`, `hasql`, `hasql-migration`,
`hasql-transaction`, `lens`, `text`, `transformers`, `validation`, and `typeid-hs-sql`. It no longer
depends on `file-embed` (embedding moved to `typeid-hs-sql`).

**Public interface preserved (must not change):** module `TypeId.Db.Migration` exporting
`migrate :: Session (Either MigrationError ())`, `validate :: Session (Either [MigrationError] ())`,
`getMigrations :: Session [SchemaMigration]`, `migrations :: [MigrationCommand]`, and
`version :: String`. The modules `TypeId.Db.Migration.Migrations`, `...Migrations.V0_0_1`, `...Sessions`,
`...Statements`, and `...Transactions` remain exposed with their existing names.

**Shared build file:** appends `./typeid-hs-hasql-migration` to `cabal.project` and removes the
now-obsolete root package. See MasterPlan Integration Points entry 1. Do not edit `mori.dhall` or the
root `README.md` — those belong to `docs/plans/4-wire-nix-mori-docs-for-the-split-packages.md`.
