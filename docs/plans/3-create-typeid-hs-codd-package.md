---
id: 3
slug: create-typeid-hs-codd-package
title: "Create typeid-hs-codd package"
kind: exec-plan
created_at: 2026-06-06T14:28:17Z
intention: "intention_01kteks21kes6rcgdxpc96x5s2"
master_plan: "docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md"
---

# Create typeid-hs-codd package

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today the only way to apply the TypeID PostgreSQL migrations from Haskell is through the
`hasql-migration` library. This plan adds a second, independent way: a new cabal package
`typeid-hs-codd` that applies the **same** SQL through the `codd` migration library
(`mzabani/codd`). After this plan, a project standardized on `codd` can depend on `typeid-hs-codd`,
obtain the TypeID migrations as `codd` values, and apply them with `codd`'s forward-only,
schema-verifying engine — installing exactly the same PostgreSQL objects (`uuid_generate_v7()`,
`base32_encode`/`base32_decode`, the `typeid` composite type, `typeid_generate*`, `typeid_parse`,
`typeid_print`, `typeid_check*`, and the `===` operator).

`codd` is fundamentally different from `hasql-migration`. It is forward-only (no down migrations),
configured by a `CoddSettings` record (connection string, schema selection, an on-disk
"expected-schema" snapshot directory), and its headline feature is verifying the live database
schema against that snapshot. `codd` has no honest analogue of `hasql-migration`'s `validate`.
Following `codd`'s own guidance for libraries, this package therefore ships the migrations as
**Haskell values** (`[AddedSqlMigration m]`) and offers thin helpers to apply them, leaving the
consuming service to own its expected-schema snapshot and to choose strict or lax verification.
This API shape was decided in the MasterPlan Decision Log.

You can see it working by building `typeid-hs-codd`, then applying the migrations against a real
PostgreSQL database and confirming `SELECT typeid_generate_text('user')` returns a TypeID.

This plan is part of the initiative in
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md`. It has a hard
dependency on plan 1: the module `TypeId.Db.Sql` (package `typeid-hs-sql`) must exist and export
`version :: String`, `migrationFiles :: [FilePath]`, and `sqlFiles :: [(FilePath, ByteString)]`. It
has **no dependency** on plan 2 (the `hasql-migration` package); the two backends are independent
and may be built in parallel.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 0 (spike): folded into M1+M3 — the codd API was first verified against the pinned source (`/Users/shinzui/Keikaku/hub/haskell/codd-project/codd`), then proven live in M3 (2026-06-06)
- [x] Milestone 1: `typeid-hs-codd/` package + `.cabal`; `codd` dependency resolves (clean solve, no `allow-newer`); empty lib builds (2026-06-06)
- [x] Milestone 2: `TypeId.Db.Codd.Migration` exposes `version`, `migrations`, `applyTypeIdMigrations`, `migrateFromEnv`; builds clean (2026-06-06)
- [x] Milestone 3: end-to-end apply against PostgreSQL 17; all four migrations committed in order; TypeID objects verified present (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The pinned codd commit was not fetchable; pinned to `origin/master` instead.** The plan pinned
  `codd` at `b1cf7e52da5799a76e538e9382d55e84d67b0656`, but `cabal` failed with
  `fatal: remote error: upload-pack: not our ref b1cf7e52...`. That commit is a local-only,
  docs-only commit ("docs: add codd adoption guide") on the mori checkout that was never pushed.
  The remote's `origin/master` is `d176b3088f23ef2218c7a1f31835e8ee0c0601aa`, and
  `git diff --stat origin/master HEAD -- codd/` is empty (identical `codd/` source). The
  `cabal.project` pin was changed to `d176b3088f23ef2218c7a1f31835e8ee0c0601aa`, which the remote
  serves (`git ls-remote origin master` confirms). Cross-plan note: EP-4's `mori.dhall`/README
  should reference this fetchable commit, not the unpushed one.

- **`codd` solved cleanly under GHC 9.12.4 with no `allow-newer`.** The plain git pin resolved:
  `codd-0.1.8` plus transitive `uuid`, `formatting`, `haxl`, `unliftio`, `postgresql-simple`,
  `streaming`. No Hackage fallback and no `allow-newer` lines were needed.

- **Two extra direct dependencies required:** `exceptions` (for `Control.Monad.Catch (MonadThrow)`)
  and `unliftio-core` (for `Control.Monad.IO.Unlift (MonadUnliftIO)`). GHC reported them as hidden
  packages until added to `build-depends`.

- **A type-inference fix was needed for the `PureStream` monad.** `codd`'s `MigrationStream` class
  has no functional dependency, so GHC would not unify the `PureStream`'s monad with the parsing
  monad and reported `The type variable 'm0' is ambiguous`. The fix: give `migrations` an explicit
  `forall m.` (ScopedTypeVariables, on by default in GHC2021), a local signature on the worker
  `parseOne :: (Int, FilePath) -> m (AddedSqlMigration m)`, and an explicit annotation
  `stream = PureStream (...) :: PureStream m`.

- **CRITICAL DESIGN DISCOVERY — `LaxCheck` is NOT "no verification".** The plan (and the MasterPlan
  Decision Log) assumed `migrateFromEnv` could use `LaxCheck` with an empty
  `CODD_EXPECTED_SCHEMA_DIR` and get a `SchemasDiffer` result. In reality, `codd`'s *both*
  `laxCheckLastAction` and `strictCheckLastAction` call `readRepsFromDisk` on the expected-schema
  snapshot; a *missing* snapshot is a hard I/O error, not a "differ" outcome. The first run threw
  `*** Exception: user error (File /tmp/codd-empty-schema/v17/db-settings was expected but does not
  exist)` and the whole migration transaction rolled back (verified: `typeid_generate_text` and
  `codd.sql_migrations` did not exist afterward). `applyMigrations` only ever returns `SchemasMatch`
  or `SchemasDiffer` — `SchemasNotVerified` is reserved for the no-check path. Resolution:
  `migrateFromEnv` was changed to use `Codd.applyMigrationsNoCheck` (which reads no snapshot) and
  return `SchemasNotVerified`. This better honors the MasterPlan's *intent* ("default to no schema
  verification; consumer owns the snapshot") than `LaxCheck` did. `applyTypeIdMigrations` retains its
  `VerifySchemas` parameter, so a consumer who owns a snapshot can still pass `LaxCheck`/`StrictCheck`.
  Evidence after the fix: the log shows all four migrations applied and `COMMITed transaction`,
  `migrateFromEnv` returned `SchemasNotVerified`, and `SELECT typeid_generate_text('user')` returned
  `user_01kteqv370e2btyfanv9dvby71`. Recorded in the MasterPlan Surprises & Discoveries and Decision Log.


## Decision Log

- Decision: Expose `migrations :: (Monad m, EnvVars m) => m [AddedSqlMigration m]` as the primary API,
  plus `applyTypeIdMigrations` (polymorphic, injects our migrations into `Codd.applyMigrations`) and
  `migrateFromEnv` (concrete `IO`, builds `CoddSettings` from environment variables and runs with
  `LaxCheck`).
  Rationale: Matches `codd`'s library guidance (ship migrations as values), keeps the core API
  monad-polymorphic so it composes with a service's own migration list, and offers one batteries-included
  `IO` entry point for the simple case. See MasterPlan Decision Log.
  Date: 2026-06-06

- Decision: Generate `codd`-style timestamped migration names with a `-typeid-` namespace, derived
  deterministically from a fixed base timestamp plus the file's index — e.g.
  `2024-01-01-00-00-01-typeid-01-uuidv7.sql`.
  Rationale: `codd` parses each migration's timestamp out of its name and orders migrations by it. We
  must supply names in `YYYY-MM-DD-HH-MM-SS-...` form. A fixed base date keeps names reproducible (no
  wall-clock dependence), the per-index second keeps order stable and matching `Sql.migrationFiles`, and
  the `-typeid-` namespace prevents collisions with a consumer's own migrations (per `codd`'s adoption
  guidance).
  Date: 2026-06-06

- Decision: Pin `codd` via a `source-repository-package` to `https://github.com/shinzui/codd-project`
  (subdir `codd`) rather than relying on the Hackage `codd` package, mirroring how this repo already
  pins the `hasql-migration` fork.
  Rationale: `codd` 0.1.8 may lack version bounds for GHC 9.12.4, and this repo already prefers pinned
  forks for its database tooling. The local mori-registered checkout
  (`/Users/shinzui/Keikaku/hub/haskell/codd-project`) is the same repository and can be read for source
  reference. If a plain Hackage `codd` dependency happens to solve cleanly, that is acceptable too — see
  Milestone 1.
  Date: 2026-06-06

- Decision (revised during implementation): `migrateFromEnv` applies the migrations with **no schema
  verification** via `Codd.applyMigrationsNoCheck` and returns `SchemasNotVerified`, rather than calling
  `applyTypeIdMigrations ... LaxCheck` as originally drafted.
  Rationale: Implementation revealed that `codd`'s `LaxCheck` is not "no verification" — both `LaxCheck`
  and `StrictCheck` read an expected-schema snapshot from `CODD_EXPECTED_SCHEMA_DIR` and fail hard (an
  I/O error that rolls back the whole migration) when that snapshot is absent. Since this library ships
  no snapshot (the consumer owns it), the batteries-included entry point must not require one. Using
  `applyMigrationsNoCheck` makes `migrateFromEnv` actually usable without a snapshot and honestly reports
  `SchemasNotVerified`. The verification-aware path is preserved: `applyTypeIdMigrations` still takes a
  `VerifySchemas` argument, so a consumer that owns a snapshot can pass `LaxCheck` or `StrictCheck`. See
  Surprises & Discoveries for evidence, and the MasterPlan Surprises & Discoveries / Decision Log.
  Date: 2026-06-06

- Decision (resolved during implementation): pin `codd` at the fetchable commit
  `d176b3088f23ef2218c7a1f31835e8ee0c0601aa` (the remote's `origin/master`) instead of the
  plan's `b1cf7e52da5799a76e538e9382d55e84d67b0656`.
  Rationale: `b1cf7e52` is an unpushed, docs-only local commit; the remote rejects it
  (`not our ref`). `d176b30` is the pushed tip with byte-identical `codd/` source. See Surprises.
  Date: 2026-06-06


## Outcomes & Retrospective

EP-3 is complete. A new package `typeid-hs-codd` applies the same TypeID SQL through `codd`. Its
module `TypeId.Db.Codd.Migration` exports `version :: String`,
`migrations :: (Monad m, EnvVars m) => m [AddedSqlMigration m]` (the migrations as codd values,
named with deterministic `2024-01-01-00-00-0N-typeid-<file>` timestamps so codd orders them and
they do not collide with a consumer's own migrations), `applyTypeIdMigrations` (verification-aware,
takes `CoddSettings`/`DiffTime`/`VerifySchemas`), and `migrateFromEnv :: IO ApplyResult` (reads
`CoddSettings` from environment and applies with no verification). `codd` is pinned in
`cabal.project` at the fetchable `d176b3088f23ef2218c7a1f31835e8ee0c0601aa`; the dependency graph
solved cleanly under GHC 9.12.4 with no `allow-newer`. A clean `cabal build typeid-hs-codd`
compiles warning-free.

Verified end-to-end against PostgreSQL 17: `migrateFromEnv` applied all four migrations in one
committed transaction (`COMMITed transaction` / `Successfully applied all migrations`), returned
`SchemasNotVerified`, codd recorded all four rows in `codd.sql_migrations` in order, and
`SELECT typeid_generate_text('user')` returned `user_01kteqv370e2btyfanv9dvby71`.

The most important lesson is the `LaxCheck` discovery (see Surprises and the revised Decision Log):
`LaxCheck` reads an on-disk snapshot and is unusable without one, so `migrateFromEnv` uses
`applyMigrationsNoCheck`. The plan's Milestone 0/1/3 examples that pair `LaxCheck` with an empty
expected-schema dir would throw; the working pattern for a snapshot-less apply is
`applyMigrationsNoCheck`. Two extra direct deps (`exceptions`, `unliftio-core`) and a `forall m.` +
`PureStream m` annotation were also needed. EP-4 should document the `migrateFromEnv` (no-check) vs
`applyTypeIdMigrations` (snapshot-owning) distinction.

(Note: this section header was absent from the generated skeleton and added during EP-3
implementation, as the ExecPlan spec requires every plan to maintain an Outcomes section.)


## Context and Orientation

Assume no prior knowledge of this repository beyond the working tree.

**Repository state at the start of this plan.** Plan 1 created the multi-package layout and the shared
`typeid-hs-sql` package. The tree includes:

```text
.
|-- cabal.project                 # multi-package; lists ./typeid-hs-sql (and ./typeid-hs-hasql-migration if plan 2 is done)
|-- typeid-hs-sql/
|   |-- typeid-hs-sql.cabal
|   |-- database/v0.0.1/*.sql
|   `-- src/TypeId/Db/Sql.hs       # exposes version, migrationFiles, sqlFiles
`-- flake.nix, nix/, README.md, mori.dhall
```

You will add a new sibling directory `typeid-hs-codd/`.

**The shared interface you consume** (defined by plan 1, do not redefine it):

```haskell
module TypeId.Db.Sql
  ( version        -- :: String, "v0.0.1"
  , migrationFiles -- :: [FilePath], ["01_uuidv7.sql","02_base32.sql","03_typeid.sql","04_operator.sql"]
  , sqlFiles       -- :: [(FilePath, ByteString)], each name + bytes, in migrationFiles order
  ) where
```

**The `codd` API you will use.** The following are accurate signatures and module locations for `codd`
(verified against the source at `/Users/shinzui/Keikaku/hub/haskell/codd-project/codd`; that is the same
repository this plan pins). Treat these as the contract; if any differ at implementation time, the spike
in Milestone 0 will surface it.

From module `Codd` (re-exports `CoddSettings(..)`, `ApplyResult(..)`, `VerifySchemas(..)`):

```haskell
applyMigrations ::
  (MonadUnliftIO m, CoddLogger m, MonadThrow m, EnvVars m, NotInTxn m) =>
  CoddSettings ->
  Maybe [AddedSqlMigration m] ->   -- Just xs bypasses on-disk collection and uses xs
  DiffTime ->                      -- connection timeout
  VerifySchemas ->                 -- LaxCheck | StrictCheck
  m ApplyResult

data ApplyResult = SchemasDiffer SchemasPair | SchemasMatch DbRep | SchemasNotVerified
data VerifySchemas = LaxCheck | StrictCheck
```

From module `Codd.Parsing` (exports `AddedSqlMigration(..)`, `PureStream(..)`,
`parseAddedSqlMigration`, the `EnvVars` class, and the `MigrationStream` class):

```haskell
newtype PureStream m = PureStream { unPureStream :: Stream (Of Text) m () }
-- instance (Monad m) => MigrationStream m (PureStream m)

parseAddedSqlMigration ::
  (Monad m, MigrationStream m s, EnvVars m) =>
  String ->          -- the migration's file name; codd parses its timestamp from this name
  s ->               -- a migration stream; PureStream wraps in-memory Text
  m (Either String (AddedSqlMigration m))

class EnvVars m where
  getEnvVars :: [Text] -> m (Map Text Text)
-- instance EnvVars IO
-- instance (MonadTrans t, Monad m, EnvVars m) => EnvVars (t m)
```

From module `Codd.Environment` (also re-exported names): `getCoddSettings :: (MonadIO m) => m CoddSettings`
reads `CODD_CONNECTION`, `CODD_MIGRATION_DIRS`, `CODD_EXPECTED_SCHEMA_DIR`, and optional `CODD_SCHEMAS`,
`CODD_EXTRA_ROLES`, `CODD_RETRY_POLICY`, `CODD_TXN_ISOLATION`, `CODD_SCHEMA_ALGO`. `CoddSettings` is a
record with fields `migsConnString`, `sqlMigrations`, `onDiskReps`, `namespacesToCheck`,
`extraRolesToCheck`, `retryPolicy`, `txnIsolationLvl`, `schemaAlgoOpts`. Building one by hand is possible
but verbose; this plan uses `getCoddSettings` and lets the consumer (and the validation step) supply
configuration via environment variables.

From module `Codd.Logging`: `runCoddLogger :: (MonadIO m) => LoggingT m a -> m a` (and
`runWithoutLogging :: (MonadIO m) => LoggingT m a -> m a`). `LoggingT` has a `CoddLogger` instance and
derives `MonadIO`, `MonadUnliftIO`, `MonadThrow`, and `MonadTrans`. The five constraints on
`applyMigrations` are all satisfied by the concrete monad `LoggingT IO`: `MonadUnliftIO (LoggingT IO)`
and `MonadThrow (LoggingT IO)` are derived; `CoddLogger (LoggingT IO)` has an instance; `EnvVars (LoggingT
IO)` comes from the `MonadTrans t` instance over `EnvVars IO`; and `NotInTxn (LoggingT IO)` comes from
`NotInTxn IO` lifted through `LoggingT`. So `runCoddLogger (someApplyMigrationsAction :: LoggingT IO a)`
discharges everything to `IO`.

**Why a stream for in-memory bytes.** `parseAddedSqlMigration` reads its SQL from a `MigrationStream`.
For SQL already in memory (our embedded bytes), wrap it in `PureStream` around a one-element
`streaming` stream of `Text`: `PureStream (Streaming.yield (decodeUtf8 bytes))`. Decode the embedded
`ByteString` to `Text` with `Data.Text.Encoding.decodeUtf8` (the SQL files are UTF-8).

**Term definitions.**
- *`codd`*: a PostgreSQL migration tool and Haskell library; forward-only; verifies the live schema
  against an on-disk JSON snapshot. Version ~0.1.8.
- *`AddedSqlMigration m`*: `codd`'s in-memory representation of one parsed migration plus its timestamp.
- *`CoddSettings`*: `codd`'s configuration record (connection, schema selection, snapshot directory, …).
- *`VerifySchemas`*: `StrictCheck` (fail on schema mismatch) or `LaxCheck` (apply, then log mismatch
  without failing).
- *`PureStream` / `MigrationStream`*: `codd`'s abstraction for feeding migration text from memory or a
  file.

**Toolchain.** GHC 9.12.4 / `cabal` from the Nix dev shell (`flake.nix`, `nix/haskell.nix`). Prefix
commands with `nix develop` if cabal is not on your PATH. The dev shell provides `pkgs.postgresql` for
the live-database steps. All commands run from the repository root unless noted.


## Plan of Work

Four milestones. Milestone 0 is an explicit **prototyping spike** — `codd`'s programmatic API is the main
unknown in this whole initiative, so we de-risk it against a live database before committing to the
package's public API. Milestone 1 stands up the package and proves the `codd` dependency resolves under
GHC 9.12.4. Milestone 2 writes the public module. Milestone 3 validates end-to-end.

**Milestone 0 — Spike: prove the codd programmatic path (prototyping).** In a scratch module (not part of
the final package — e.g. a `cabal repl`-loadable file under `typeid-hs-codd/spike/`), build a single
`AddedSqlMigration` from one of our SQL files via `PureStream` + `parseAddedSqlMigration`, then call
`Codd.applyMigrations` against a throwaway PostgreSQL to apply it. Goal: confirm the exact imports, the
`PureStream` construction, the `CoddSettings` you can get from `getCoddSettings`, and that `LaxCheck`
applies migrations even with an empty expected-schema directory. Acceptance: the scratch program applies
the UUIDv7 function and `SELECT uuid_generate_v7();` returns a UUID. Record any API deviations in
Surprises & Discoveries. This spike is discarded (or kept under `spike/`, excluded from the library)
once Milestone 2 promotes its findings into the real module.

**Milestone 1 — Package skeleton and codd dependency resolution.** Create `typeid-hs-codd/` with a
`.cabal` depending on `typeid-hs-sql`, `codd`, `text`, `bytestring`, `streaming`, `time`, and
`unliftio`/`resourcet` as needed. Pin `codd` in `cabal.project` via `source-repository-package` (subdir
`codd`) unless a plain Hackage dependency solves. Add `./typeid-hs-codd` to `cabal.project`. Acceptance:
`cabal build typeid-hs-codd` resolves and builds an empty/placeholder library (proves the dependency
graph solves under GHC 9.12.4 — the riskiest build concern).

**Milestone 2 — The `TypeId.Db.Codd.Migration` module.** Promote the spike into the real module exposing
`migrations`, `applyTypeIdMigrations`, and `migrateFromEnv`. Acceptance: `cabal build typeid-hs-codd`
compiles cleanly with `-Wall`.

**Milestone 3 — End-to-end validation.** Apply the migrations against a throwaway PostgreSQL via
`migrateFromEnv` and confirm the TypeID objects exist.


## Concrete Steps

All commands from the repository root; prefix with `nix develop` if needed.

### Milestone 0 — Spike

1. Stand up a throwaway PostgreSQL (reused by later milestones):

```bash
export PGDATA="$(mktemp -d)/pgdata"
initdb -U postgres "$PGDATA" >/dev/null
pg_ctl -D "$PGDATA" -o "-p 5599" -l "$PGDATA/log" start
createdb -U postgres -p 5599 typeid_codd_test
```

2. Create a scratch package skeleton just so `cabal repl` can load `codd` and `typeid-hs-sql` together.
   Make `typeid-hs-codd/typeid-hs-codd.cabal` (minimal, refined in Milestone 1) and add
   `./typeid-hs-codd` to `cabal.project` plus the `codd` pin (see Milestone 1 steps 6–8 — do those now,
   then return here). Put the scratch code at `typeid-hs-codd/spike/Spike.hs` and add an executable or
   `repl` target, or simply load it ad hoc with `cabal repl typeid-hs-codd` after temporarily exposing it.

3. In the spike, exercise the `codd` path against one SQL file. The essential shape to confirm:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Spike where

import Codd (applyMigrations, VerifySchemas (LaxCheck))
import Codd.Environment (getCoddSettings)
import Codd.Logging (runCoddLogger)
import Codd.Parsing (AddedSqlMigration, PureStream (PureStream), parseAddedSqlMigration)
import Data.Maybe (fromJust)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (secondsToDiffTime)
import qualified Streaming.Prelude as S
import qualified TypeId.Db.Sql as Sql

-- Build one AddedSqlMigration from the first embedded SQL file.
oneMigration :: (Monad m, Codd.Parsing.EnvVars m) => m (AddedSqlMigration m)
oneMigration = do
  let name  = "01_uuidv7.sql"
      bytes = fromJust (lookup name Sql.sqlFiles)
      coddName = "2024-01-01-00-00-01-typeid-01-uuidv7.sql"
      stream = PureStream (S.yield (decodeUtf8 bytes))
  r <- parseAddedSqlMigration coddName stream
  either (error . (("parse " <> name <> ": ") <>)) pure r

spike :: IO ()
spike = runCoddLogger $ do
  settings <- getCoddSettings
  mig <- oneMigration
  res <- applyMigrations settings (Just [mig]) (secondsToDiffTime 5) LaxCheck
  liftIO (print res)
```

   Set the codd environment so `getCoddSettings` succeeds (override migrations is `Just`, but
   `getCoddSettings` still requires the dir vars to be present; point them at empty existing dirs):

```bash
mkdir -p /tmp/codd-empty-migs /tmp/codd-empty-schema
export CODD_CONNECTION='postgres://postgres@localhost:5599/typeid_codd_test'
export CODD_MIGRATION_DIRS='/tmp/codd-empty-migs'
export CODD_EXPECTED_SCHEMA_DIR='/tmp/codd-empty-schema'
export CODD_SCHEMAS='public'
```

   Then run `spike` (e.g. from `cabal repl` `:main`/`spike`, or a temporary executable). Expected: it
   prints an `ApplyResult` (likely `SchemasDiffer ...` because the empty snapshot does not match — that
   is fine under `LaxCheck`) and exits successfully.

4. Confirm the SQL actually applied:

```bash
psql -U postgres -p 5599 -d typeid_codd_test -c "SELECT uuid_generate_v7();"
```

   Expected: one row containing a UUID value. Record in Surprises & Discoveries any place the real `codd`
   API differed from the signatures in Context (e.g. an extra constraint, a different import for
   `EnvVars`, or `decodeUtf8` needing the total `decodeUtf8'`).

### Milestone 1 — Package skeleton and codd dependency

5. Create `typeid-hs-codd/typeid-hs-codd.cabal`:

```cabal
cabal-version: 3.4
name: typeid-hs-codd
version: 0.1.0.0
synopsis: PostgreSQL TypeID migrations via codd
description:
  Applies the TypeID PostgreSQL migrations (from typeid-hs-sql) using the codd
  migration library. Ships the migrations as codd AddedSqlMigration values and
  provides thin helpers to apply them; the consuming service owns its
  expected-schema snapshot and chooses strict or lax verification.
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
    TypeId.Db.Codd.Migration

  build-depends:
    base >=4.17 && <5,
    bytestring ^>=0.12,
    codd,
    streaming,
    text ^>=2.1.1,
    time,
    typeid-hs-sql,
```

6. Add the package and the `codd` pin to `cabal.project`. Read the current file first, append
   `./typeid-hs-codd` under `packages:`, and add a `source-repository-package` stanza for `codd`,
   preserving the existing `hasql-migration` pin. Target result (the `hasql-migration` stanza and the
   `./typeid-hs-hasql-migration` line are present only if plan 2 has run; keep whatever is already there
   and add your two pieces):

```text
packages:
  ./typeid-hs-sql
  ./typeid-hs-hasql-migration
  ./typeid-hs-codd

source-repository-package
  type: git
  location: https://github.com/shinzui/hasql-migration
  tag: 4aaff6c0919d1fe8e1c248c3ce4ce05775c59c8c

source-repository-package
  type: git
  location: https://github.com/shinzui/codd-project
  tag: b1cf7e52da5799a76e538e9382d55e84d67b0656
  subdir: codd
```

   The `codd` commit `b1cf7e52da5799a76e538e9382d55e84d67b0656` is the current HEAD of the
   mori-registered checkout at `/Users/shinzui/Keikaku/hub/haskell/codd-project`; if that commit is not
   fetchable, obtain a current one with `git -C /Users/shinzui/Keikaku/hub/haskell/codd-project rev-parse
   HEAD`. `codd`'s `.cabal` lives in the `codd/` subdirectory, hence `subdir: codd`.

7. Resolve the dependency. First create a minimal placeholder module so the library has something to
   build, then attempt the build:

```bash
mkdir -p typeid-hs-codd/src/TypeId/Db/Codd
```

   Create `typeid-hs-codd/src/TypeId/Db/Codd/Migration.hs` as a temporary placeholder exporting nothing
   substantial:

```haskell
module TypeId.Db.Codd.Migration () where
```

   Then:

```bash
cabal build typeid-hs-codd
```

   Expected: cabal fetches and builds `codd` and its transitive dependencies, then builds the placeholder
   library. **If version solving fails** (e.g. `codd` bounds exclude GHC 9.12.4's `base`/`time`), add an
   `allow-newer` line to `cabal.project` scoped to codd, for example:

```text
allow-newer: codd:base, codd:time, codd:template-haskell
```

   Re-run `cabal build typeid-hs-codd`. Record in Surprises & Discoveries whichever resolution was needed
   (plain Hackage, the git pin, and/or `allow-newer`), because plan 4 documents the final dependency
   story in `mori.dhall`.

### Milestone 2 — The real module

8. Replace the placeholder with the real `typeid-hs-codd/src/TypeId/Db/Codd/Migration.hs`, promoting the
   spike. Use the exact import names confirmed in Milestone 0 (adjust if the spike found deviations):

```haskell
{-# LANGUAGE FlexibleContexts #-}

module TypeId.Db.Codd.Migration
  ( version,
    migrations,
    applyTypeIdMigrations,
    migrateFromEnv,
  )
where

import Codd (ApplyResult, CoddSettings, VerifySchemas (LaxCheck), applyMigrations)
import Codd.Environment (getCoddSettings)
import Codd.Logging (CoddLogger, runCoddLogger)
import Codd.Parsing
  ( AddedSqlMigration,
    EnvVars,
    PureStream (PureStream),
    parseAddedSqlMigration,
  )
import Codd.Query (NotInTxn)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.IO.Unlift (MonadUnliftIO)
import Control.Monad.Catch (MonadThrow)
import Data.Maybe (fromJust)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (DiffTime, secondsToDiffTime)
import qualified Streaming.Prelude as S
import qualified TypeId.Db.Sql as Sql
import Text.Printf (printf)

-- | The schema version these migrations implement, sourced from typeid-hs-sql.
version :: String
version = Sql.version

-- | The TypeID migrations as codd values, built from the SQL exposed by
-- typeid-hs-sql. Polymorphic in the monad so a service can splice these into
-- its own migration list before calling codd. Each migration is given a
-- deterministic codd-style timestamped, "-typeid-"-namespaced name so codd
-- orders them correctly and they do not collide with the consumer's own
-- migrations.
migrations :: (Monad m, EnvVars m) => m [AddedSqlMigration m]
migrations = traverse parseOne (zip [1 :: Int ..] Sql.migrationFiles)
  where
    parseOne (i, name) = do
      let bytes    = fromJust (lookup name Sql.sqlFiles)
          coddName = printf "2024-01-01-00-00-%02d-typeid-%s" i name
          stream   = PureStream (S.yield (decodeUtf8 bytes))
      result <- parseAddedSqlMigration coddName stream
      either (error . ((("parse codd migration " <> name <> ": ") <>))) pure result

-- | Apply the TypeID migrations using the supplied codd settings and
-- verification mode. The service owns the CoddSettings (connection string,
-- schema selection, expected-schema snapshot) and decides StrictCheck/LaxCheck.
applyTypeIdMigrations ::
  (MonadUnliftIO m, CoddLogger m, MonadThrow m, EnvVars m, NotInTxn m) =>
  CoddSettings ->
  DiffTime ->
  VerifySchemas ->
  m ApplyResult
applyTypeIdMigrations settings timeout verify = do
  migs <- migrations
  applyMigrations settings (Just migs) timeout verify

-- | Batteries-included entry point: read CoddSettings from environment
-- variables (CODD_CONNECTION, CODD_MIGRATION_DIRS, CODD_EXPECTED_SCHEMA_DIR,
-- and optional CODD_SCHEMAS/...), then apply the TypeID migrations with a
-- five-second connection timeout and LaxCheck (apply, log any schema mismatch,
-- do not fail solely on mismatch). Returns codd's ApplyResult.
migrateFromEnv :: IO ApplyResult
migrateFromEnv = runCoddLogger $ do
  settings <- getCoddSettings
  applyTypeIdMigrations settings (secondsToDiffTime 5) LaxCheck
```

   Notes for the implementer: the import of `NotInTxn` is from `Codd.Query` (confirm in Milestone 0). If
   `printf` typing is awkward, build the name with plain string concatenation instead — the only
   requirement is a `YYYY-MM-DD-HH-MM-SS-...` prefix with a per-index second and the `-typeid-` namespace.
   Keep `migrations` monomorphism-free by leaving the `(Monad m, EnvVars m)` constraint; do not pin it to
   `IO`.

9. Build:

```bash
cabal build typeid-hs-codd
```

   Expected: clean compile. Resolve any `-Wall` warnings (unused imports such as `MonadIO` if it turns
   out unneeded). Then build the whole project:

```bash
cabal build all
```

### Milestone 3 — End-to-end validation

10. Ensure the throwaway PostgreSQL from Milestone 0 is running (or recreate it), and the codd env vars
    point at it (CODD_CONNECTION on port 5599, empty migration/schema dirs as in step 3). Apply the
    migrations through the real entry point:

```bash
cabal repl typeid-hs-codd
```

```haskell
import TypeId.Db.Codd.Migration (migrateFromEnv)
res <- migrateFromEnv
res
```

    Expected: prints an `ApplyResult` (a `SchemasDiffer`/`SchemasMatch`/`SchemasNotVerified` value) and
    does not throw. Under `LaxCheck` an empty expected-schema snapshot yields a `SchemasDiffer`, which is
    expected and not a failure.

11. Confirm all TypeID objects were installed (proves the full migration set applied in order):

```bash
psql -U postgres -p 5599 -d typeid_codd_test -c "SELECT typeid_generate_text('user');"
```

    Expected: one row whose value looks like `user_01h455vb4pex5vsknk084sn02q`. Then tear down:

```bash
pg_ctl -D "$PGDATA" stop
```


## Validation and Acceptance

This plan is complete when:

1. `cabal build typeid-hs-codd` succeeds from clean with no warnings, proving the `codd` dependency
   resolves under GHC 9.12.4:

```bash
cabal clean && cabal build typeid-hs-codd
```

2. `TypeId.Db.Codd.Migration` exports `version`, `migrations`, `applyTypeIdMigrations`, and
   `migrateFromEnv` with the signatures in Milestone 2. Check `migrations`' polymorphic type in GHCi:

```haskell
:type TypeId.Db.Codd.Migration.migrations
-- migrations :: (Monad m, EnvVars m) => m [AddedSqlMigration m]
```

3. Applying the migrations against a live PostgreSQL installs the TypeID objects:
   `migrateFromEnv` returns an `ApplyResult` without throwing, and
   `SELECT typeid_generate_text('user')` returns a `user_`-prefixed TypeID (Milestone 3 steps 10–11).

When these hold, update the MasterPlan Exec-Plan Registry to mark EP-3 Complete, check off the EP-3
entries in the MasterPlan Progress section, and record the final `codd` dependency-resolution outcome
(git pin vs Hackage, any `allow-newer`) in the MasterPlan Surprises & Discoveries section so plan 4 can
document it.


## Idempotence and Recovery

The `.cabal`, `cabal.project`, and `.hs` writes are idempotent. `cabal clean && cabal build` is always
safe to repeat. The throwaway PostgreSQL is disposable: `pg_ctl -D "$PGDATA" stop` and removing `$PGDATA`
fully resets it; re-running `initdb`/`createdb` from scratch is the recovery path. Applying the
migrations twice to the same database is safe to attempt — `codd` records applied migrations and will not
re-run them; if you want a clean slate, drop and recreate `typeid_codd_test`. The spike artifacts under
`typeid-hs-codd/spike/` (if kept) must be excluded from the library's `exposed-modules`/`hs-source-dirs`
so they do not ship; delete them once Milestone 2 is done.

If `codd` fails to fetch or solve, the recovery path is, in order: (a) confirm the pinned commit is
fetchable; (b) try a plain Hackage `codd` dependency by removing the git pin; (c) add scoped
`allow-newer` entries. Record whichever worked.


## Interfaces and Dependencies

**Consumes (hard dependency on plan 1):** `TypeId.Db.Sql` from package `typeid-hs-sql`
(`version`, `migrationFiles`, `sqlFiles`).

**Libraries:** `codd` (the migration engine and its `Codd`, `Codd.Parsing`, `Codd.Environment`,
`Codd.Logging`, `Codd.Query` modules), `streaming` (for `Streaming.Prelude.yield` to build a
`PureStream`), `text` (for `decodeUtf8`), `bytestring`, `time` (for `DiffTime`/`secondsToDiffTime`), and
`base`. Additional transitive constraints (`unliftio`, `mtl`, `resourcet`) come in via `codd`; add them
to `build-depends` only if the compiler reports them as direct imports.

**Public interface produced by this plan:** module `TypeId.Db.Codd.Migration` in package
`typeid-hs-codd`, exporting:

```haskell
version               :: String
migrations            :: (Monad m, EnvVars m) => m [AddedSqlMigration m]
applyTypeIdMigrations :: (MonadUnliftIO m, CoddLogger m, MonadThrow m, EnvVars m, NotInTxn m)
                      => CoddSettings -> DiffTime -> VerifySchemas -> m ApplyResult
migrateFromEnv        :: IO ApplyResult
```

**Shared build file:** appends `./typeid-hs-codd` to `cabal.project` and adds a `source-repository-package`
pin for `codd` (preserving the existing `hasql-migration` pin and any `./typeid-hs-hasql-migration`
entry). See MasterPlan Integration Points entry 1. Do not edit `mori.dhall` or the root `README.md` —
those belong to `docs/plans/4-wire-nix-mori-docs-for-the-split-packages.md`.
