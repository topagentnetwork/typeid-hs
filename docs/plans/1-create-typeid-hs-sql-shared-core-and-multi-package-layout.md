---
id: 1
slug: create-typeid-hs-sql-shared-core-and-multi-package-layout
title: "Create typeid-hs-sql shared core and multi-package layout"
kind: exec-plan
created_at: 2026-06-06T14:28:17Z
intention: "intention_01kteks21kes6rcgdxpc96x5s2"
master_plan: "docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md"
---

# Create typeid-hs-sql shared core and multi-package layout

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository currently builds a single Haskell library, `typeid-hs`, that ships PostgreSQL
TypeID migrations and applies them via the `hasql-migration` library. The raw SQL lives in
`database/v0.0.1/*.sql` and is embedded into the library with Template Haskell, then immediately
wrapped in `hasql-migration` types. Because the SQL and the `hasql-migration` machinery are
welded together in one package, there is no way to reuse the SQL with a different migration tool.

This plan creates the foundation for splitting that apart. After this plan, there is a new,
deliberately tiny cabal package named `typeid-hs-sql` that embeds the four SQL files once and
exposes them as ordinary Haskell values — the version string, the ordered list of file names, and
each file's name plus its raw bytes — with **no dependency on `hasql` or `codd`**. The repository
is converted from a single-package build into a multi-package "cabal monorepo" (several packages
built from one `cabal.project`).

You can see it working by running `cabal build typeid-hs-sql` and then, in a GHCi session, printing
the exposed values to confirm the four SQL files are embedded in the correct order with their real
contents.

This is the root of the larger initiative described in
`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md`. Two later plans —
`docs/plans/2-rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql.md` and
`docs/plans/3-create-typeid-hs-codd-package.md` — build migration backends on top of the
`TypeId.Db.Sql` interface this plan defines. Nothing in those plans can compile until this plan's
interface exists, so the interface defined here is a hard contract: define it exactly as specified
in the Interfaces and Dependencies section below.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: `typeid-hs-sql` package directory, `.cabal`, and SQL files in place (2026-06-06)
- [x] Milestone 1: `cabal.project` converted to multi-package and seeded with `./typeid-hs-sql` (2026-06-06)
- [x] Milestone 2: `TypeId.Db.Sql` module embeds the SQL and exposes `version`/`migrationFiles`/`sqlFiles` (2026-06-06)
- [x] Milestone 2: `cabal build typeid-hs-sql` succeeds (2026-06-06)
- [x] Milestone 3: GHCi check confirms four files embedded in order with real contents (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- `git mv database/v0.0.1 typeid-hs-sql/database/v0.0.1` left an empty `database/` directory
  behind on the filesystem (git stops tracking the moved files but does not prune the now-empty
  parent dir). The acceptance check `test ! -d database` therefore failed until the leftover dir
  was removed with `rmdir database`. Anyone re-running Milestone 1 should `rmdir database` after the
  move. Evidence: `if [ -d database ]; then echo "database/ EXISTS" ...` printed `database/ EXISTS`.


## Decision Log

- Decision: `typeid-hs-sql` exposes `sqlFiles :: [(FilePath, ByteString)]` plus an explicit
  `migrationFiles :: [FilePath]` ordering list, rather than relying on `embedDir`'s implicit ordering.
  Rationale: `Data.FileEmbed.embedDir` returns files in an order that is not guaranteed to be the
  migration order. The existing code already keeps an explicit ordered `migrationFiles` list and looks
  each file up by name; preserving that pattern keeps ordering correct and obvious, and gives consumers
  both the ordering and the bytes.
  Date: 2026-06-06

- Decision: The SQL files move into `typeid-hs-sql/database/v0.0.1/` rather than staying at the repo root.
  Rationale: `file-embed`'s `makeRelativeToProject` and cabal's `extra-source-files`/sdist resolve
  against the owning package's directory. Keeping the SQL inside `typeid-hs-sql` makes embedding and
  source-distribution correct. See the MasterPlan Integration Points entry 3.
  Date: 2026-06-06


## Outcomes & Retrospective

EP-1 is complete. The repository is now a multi-package cabal project whose `cabal.project`
lists `./typeid-hs-sql` and preserves the `hasql-migration` source-repository pin. The new
`typeid-hs-sql` package embeds the four SQL files once (the only copy now lives at
`typeid-hs-sql/database/v0.0.1/`, the root `database/` directory is gone) and exposes the hard
contract `version :: String`, `migrationFiles :: [FilePath]`, and
`sqlFiles :: [(FilePath, ByteString)]` from `TypeId.Db.Sql` with no dependency on `hasql` or
`codd`. A clean `cabal build typeid-hs-sql` compiles warning-free, and the GHCi check confirmed
the four files are embedded in canonical order with non-empty real SQL bytes (the first file
begins with the UUIDv7 comment). The old `typeid-hs.cabal` and `src/` remain on disk but are
unlisted in `cabal.project`; EP-2 removes them.

The interface defined here matches MasterPlan Integration Points entry 2 exactly, so EP-2 and
EP-3 can be implemented against it without changes. No deviations from the plan were required.
Only lesson learned: see Surprises — `git mv` of a subdirectory leaves the empty parent dir,
which the acceptance check flags.

(Note: this section header was absent from the generated skeleton and added during EP-1
implementation, as the ExecPlan spec requires every plan to maintain an Outcomes section.)


## Context and Orientation

You are working in a Haskell library repository. Assume no prior knowledge of it.

**Current top-level layout (before this plan):**

```text
.
|-- typeid-hs.cabal            # the single package definition
|-- cabal.project             # build config: packages: . + a git pin for hasql-migration
|-- src/                      # all Haskell source for the single package
|   `-- TypeId/Db/Migration/...
|-- database/
|   `-- v0.0.1/
|       |-- 01_uuidv7.sql
|       |-- 02_base32.sql
|       |-- 03_typeid.sql
|       `-- 04_operator.sql
|-- flake.nix, nix/, README.md, mori.dhall
```

**What the SQL is.** The four files under `database/v0.0.1/` are plain PostgreSQL definitions
(a UUIDv7 generator function, base32 encode/decode functions, the `typeid` composite type and its
functions, and a `===` operator). They contain no Haskell- or tool-specific content. They must be
applied in this order: `01_uuidv7.sql`, `02_base32.sql`, `03_typeid.sql`, `04_operator.sql`
(later files reference objects created by earlier ones).

**How the SQL is currently embedded.** The file `src/TypeId/Db/Migration/Migrations/V0_0_1.hs`
uses Template Haskell from the `file-embed` package to embed the whole `database/v0.0.1` directory
at compile time, then wraps each file in a `hasql-migration` value. The relevant lines today are:

```haskell
version :: String
version = "v0.0.1"

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

`makeRelativeToProject` resolves a path relative to the package root (the directory containing the
`.cabal` file). `embedDir` returns `[(FilePath, ByteString)]` of every file in that directory, where
each `FilePath` is the file's name relative to the embedded directory (e.g. `"01_uuidv7.sql"`). The
code then looks each name up in that list using the explicit `migrationFiles` ordering. This plan
extracts exactly that embedding-and-ordering logic into the new `typeid-hs-sql` package, stopping
**before** any `hasql-migration` wrapping (that wrapping stays in the renamed hasql backend, handled
by `docs/plans/2-rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql.md`).

**The existing `typeid-hs.cabal`** declares a `common common-options` stanza with a fixed set of
`ghc-options` warnings and a set of `default-extensions`. The library uses `default-language: GHC2021`.
You will reproduce a minimal version of this for `typeid-hs-sql`. The full current `typeid-hs.cabal`
content is reproduced in the Concrete Steps so you do not need to open it (but it is still present in
the working tree at this point — EP-2 removes it later).

**The existing `cabal.project`:**

```text
packages: .

source-repository-package
  type: git
  location: https://github.com/shinzui/hasql-migration
  tag: 4aaff6c0919d1fe8e1c248c3ce4ce05775c59c8c
```

The `source-repository-package` stanza pins a fork of `hasql-migration`. It is **not** needed by
`typeid-hs-sql` (which has no `hasql` dependency at all) but it must be preserved in `cabal.project`
because the hasql backend still needs it. Do not delete it.

**Toolchain.** The Nix dev shell provides GHC 9.12.4, `cabal`, and HLS (see `flake.nix` and
`nix/haskell.nix`). Run `cabal` commands from inside `nix develop` if cabal is not otherwise on your
PATH. All `cabal` commands in this plan are run from the repository root unless stated otherwise.

**Term definitions.**
- *cabal monorepo / multi-package project*: a repository whose `cabal.project` lists more than one
  package directory under `packages:`, so `cabal build` can build several packages together.
- *`file-embed`*: a Haskell library providing Template Haskell helpers (`embedDir`,
  `makeRelativeToProject`) that read files at compile time and bake their bytes into the executable.
- *`extra-source-files`*: a cabal field listing non-Haskell files (here, the `.sql` files) that must
  be shipped in a source distribution and are available at build time.


## Plan of Work

The work is three milestones. Milestone 1 creates the package skeleton and the multi-package build
configuration. Milestone 2 writes the one module that embeds and exposes the SQL. Milestone 3 proves
the values are correct at runtime.

**Milestone 1 — Package skeleton and multi-package layout.** Create the directory
`typeid-hs-sql/`, move the four SQL files into `typeid-hs-sql/database/v0.0.1/`, write
`typeid-hs-sql/typeid-hs-sql.cabal`, and convert the root `cabal.project` from `packages: .` to a
multi-package list seeded with `./typeid-hs-sql`. At the end, `cabal build typeid-hs-sql` resolves
the package (it will not have a module yet — that is Milestone 2 — but `cabal build` should report
the package and only fail, if at all, on the empty module list). Acceptance: `cabal build all`
recognizes `typeid-hs-sql` as a target.

**Milestone 2 — The `TypeId.Db.Sql` module.** Add `typeid-hs-sql/src/TypeId/Db/Sql.hs` with the
embedding logic moved out of the old `V0_0_1.hs`, exposing exactly `version`, `migrationFiles`, and
`sqlFiles`. Wire it into the `.cabal` `exposed-modules`. Acceptance: `cabal build typeid-hs-sql`
succeeds with no warnings (the package uses `-Wall` via the common options).

**Milestone 3 — Runtime verification.** Load the module in GHCi and confirm the exposed values are
correct: four files, in the documented order, with non-empty real SQL bytes. Acceptance: the GHCi
transcript matches the expected output shown in Concrete Steps.


## Concrete Steps

All commands run from the repository root. If `cabal`/`ghc` are not on your PATH, prefix the session
with `nix develop` (so the GHC 9.12.4 toolchain from the flake is available).

### Milestone 1

1. Create the package directory and move the SQL into it (this relocates the only copy of the SQL —
   see MasterPlan Integration Points entry 3):

```bash
mkdir -p typeid-hs-sql/src/TypeId/Db
mkdir -p typeid-hs-sql/database
git mv database/v0.0.1 typeid-hs-sql/database/v0.0.1
```

   After this, `typeid-hs-sql/database/v0.0.1/` holds the four `.sql` files and the root `database/`
   directory is gone. (If `git mv` is unavailable, use `mkdir -p typeid-hs-sql/database && mv
   database/v0.0.1 typeid-hs-sql/database/`.)

2. Create `typeid-hs-sql/typeid-hs-sql.cabal` with this content. It mirrors the warning flags and
   extensions of the existing `typeid-hs.cabal` but depends only on `base`, `bytestring`, `file-embed`,
   and `filepath` — deliberately no `hasql`, `hasql-migration`, `lens`, `text`, or `validation`:

```cabal
cabal-version: 3.4
name: typeid-hs-sql
version: 0.1.0.0
synopsis: Embedded PostgreSQL TypeID SQL, tool-agnostic
description:
  Embeds the TypeID PostgreSQL migration SQL and exposes it as plain Haskell
  values (version, ordered file names, and each file's bytes). Intended to be
  consumed by migration-tool-specific backends such as typeid-hs-hasql-migration
  and typeid-hs-codd.
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

library
  import: common-options
  hs-source-dirs: src
  default-language: GHC2021
  exposed-modules:
    TypeId.Db.Sql

  build-depends:
    base >=4.17 && <5,
    bytestring ^>=0.12,
    file-embed,
    filepath,
```

3. Convert the root `cabal.project`. Read it first, then replace `packages: .` with a multi-package
   list that names the new package directory, while preserving the `source-repository-package` pin
   exactly. The result must be:

```text
packages:
  ./typeid-hs-sql

source-repository-package
  type: git
  location: https://github.com/shinzui/hasql-migration
  tag: 4aaff6c0919d1fe8e1c248c3ce4ce05775c59c8c
```

   Note: at this moment the old root `typeid-hs.cabal` still exists but is **no longer listed** in
   `cabal.project` (it was covered by `packages: .`). That is intentional and temporary; EP-2 removes
   the old `.cabal` and `src/` and adds `./typeid-hs-hasql-migration`. Leaving `typeid-hs.cabal` on
   disk but unlisted is harmless for building `typeid-hs-sql`.

4. Confirm the package is recognized (it will fail to build until Milestone 2 adds the module — that is
   expected; you are only confirming cabal sees the package and the multi-package project parses):

```bash
cabal build typeid-hs-sql --dry-run
```

   Expected: cabal parses the project and lists `typeid-hs-sql` as the target. If it instead complains
   that `cabal.project` is malformed or that no such package exists, fix the `cabal.project` formatting
   (two-space indentation under `packages:`).

### Milestone 2

5. Create `typeid-hs-sql/src/TypeId/Db/Sql.hs` with the embedding logic extracted from the old
   `V0_0_1.hs`. This is the canonical definition of the shared interface (see Interfaces and
   Dependencies):

```haskell
{-# LANGUAGE TemplateHaskell #-}

module TypeId.Db.Sql
  ( version,
    migrationFiles,
    sqlFiles,
  )
where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedDir, makeRelativeToProject)
import Data.Maybe (fromJust)

-- | The schema version these SQL files implement. Currently "v0.0.1".
version :: String
version = "v0.0.1"

-- | The migration file base names, in the exact order they must be applied.
-- Later files depend on objects created by earlier ones, so this ordering is
-- significant and must not be re-sorted by consumers.
migrationFiles :: [FilePath]
migrationFiles =
  [ "01_uuidv7.sql",
    "02_base32.sql",
    "03_typeid.sql",
    "04_operator.sql"
  ]

-- | Each migration's base name paired with its embedded raw SQL bytes, in the
-- same order as 'migrationFiles'. Consumers map these into their migration
-- tool's own representation (e.g. hasql-migration's MigrationScript or codd's
-- AddedSqlMigration). The bytes are embedded at compile time from
-- database/v0.0.1 inside this package.
sqlFiles :: [(FilePath, ByteString)]
sqlFiles = [(name, lookupBytes name) | name <- migrationFiles]
  where
    lookupBytes name = fromJust (lookup name embeddedDir)

-- | All files under database/v0.0.1, embedded at compile time. The order is
-- whatever embedDir returns; 'sqlFiles' re-imposes the canonical ordering.
embeddedDir :: [(FilePath, ByteString)]
embeddedDir = $(makeRelativeToProject "database/v0.0.1" >>= embedDir)
```

   Notes for the implementer: `makeRelativeToProject "database/v0.0.1"` resolves relative to the
   `typeid-hs-sql` package root (the directory containing `typeid-hs-sql.cabal`), so it finds the SQL
   you moved in step 1. `fromJust` is safe here because every name in `migrationFiles` corresponds to a
   real file in the embedded directory; if a name is misspelled, the build will still succeed but the
   value will crash at evaluation — the Milestone 3 GHCi check exists precisely to catch that.

6. Build the package:

```bash
cabal build typeid-hs-sql
```

   Expected: it compiles cleanly. Because the common options include `-Wall` and `-Wmissing-export-lists`,
   any unused import or missing export list is a warning; the module above is written to produce none.
   If you see a warning about `embeddedDir` being unused, that means `sqlFiles` was not written to use it
   — re-check the code.

### Milestone 3

7. Verify the runtime values in GHCi:

```bash
cabal repl typeid-hs-sql
```

   Then inside the REPL:

```haskell
import TypeId.Db.Sql
import qualified Data.ByteString.Char8 as BC
version
map fst sqlFiles
map (\(n, b) -> (n, BC.length b > 0)) sqlFiles
BC.putStrLn (BC.take 60 (snd (head sqlFiles)))
```

   Expected transcript (lengths/first line shown for orientation; the booleans must all be `True`):

```text
ghci> version
"v0.0.1"
ghci> map fst sqlFiles
["01_uuidv7.sql","02_base32.sql","03_typeid.sql","04_operator.sql"]
ghci> map (\(n, b) -> (n, BC.length b > 0)) sqlFiles
[("01_uuidv7.sql",True),("02_base32.sql",True),("03_typeid.sql",True),("04_operator.sql",True)]
ghci> BC.putStrLn (BC.take 60 (snd (head sqlFiles)))
-- Function to generate new v7 UUIDs.
-- In the future we might
```

   Exit GHCi with `:quit`.


## Validation and Acceptance

The change is effective when all of the following hold:

1. `cabal build typeid-hs-sql` succeeds from a clean state with no warnings:

```bash
cabal clean && cabal build typeid-hs-sql
```

2. The exposed values are correct, as shown by the Milestone 3 GHCi transcript: `version` is
   `"v0.0.1"`, `map fst sqlFiles` is exactly the four file names in the documented order, every file's
   byte length is greater than zero, and the first file begins with the UUIDv7 comment.

3. The SQL exists in exactly one location: `typeid-hs-sql/database/v0.0.1/*.sql`. There is no root
   `database/` directory:

```bash
test ! -d database && echo "root database/ removed OK"
ls typeid-hs-sql/database/v0.0.1
```

   Expected: prints `root database/ removed OK` and then the four `.sql` file names.

4. `cabal.project` lists `./typeid-hs-sql` and still contains the `hasql-migration`
   `source-repository-package` pin (grep both):

```bash
grep -q "./typeid-hs-sql" cabal.project && grep -q "shinzui/hasql-migration" cabal.project && echo "cabal.project OK"
```

When all four hold, this plan is complete. Update the MasterPlan Exec-Plan Registry to mark EP-1
Complete and check off the EP-1 entries in the MasterPlan Progress section.


## Idempotence and Recovery

The directory/file moves in Milestone 1 are not idempotent (running `git mv database/v0.0.1 ...` twice
fails because the source no longer exists). That is fine: before re-running, check whether
`typeid-hs-sql/database/v0.0.1` already exists and skip the move if so. The `.cabal`, `cabal.project`,
and `.hs` file writes are idempotent (writing the same content twice is harmless). `cabal clean`
followed by `cabal build` is always safe to repeat.

If something goes wrong and you need to start over before committing, `git status` will show the moved
files and new files; `git restore --staged --worktree database typeid-hs-sql cabal.project` (adjusting
paths) returns to the pre-plan state since nothing here is destructive beyond moves tracked by git.


## Interfaces and Dependencies

**Library:** `file-embed` (Template Haskell embedding), `bytestring` (for `ByteString`), `filepath`
(available if needed for path joins; the module above does not use it directly but it is listed for
parity with the original and in case ordering helpers are added). `base` only otherwise. This package
must **not** depend on `hasql`, `hasql-migration`, `codd`, `lens`, `text`, or `validation`.

**The `TypeId.Db.Sql` interface (hard contract for EP-2 and EP-3).** At the end of this plan, the
module `TypeId.Db.Sql` in package `typeid-hs-sql` must export exactly these three values with these
types:

```haskell
version        :: String                      -- currently "v0.0.1"
migrationFiles :: [FilePath]                  -- ordered base names, see body
sqlFiles       :: [(FilePath, ByteString)]    -- name + embedded bytes, in migrationFiles order
```

`docs/plans/2-rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql.md` consumes `sqlFiles`
and `version` to build `Hasql.Migration.MigrationCommand` values.
`docs/plans/3-create-typeid-hs-codd-package.md` consumes `sqlFiles` and `version` to build `codd`
`AddedSqlMigration` values. If you must change any of these names or types, you must update the
MasterPlan's Integration Points entry 2 and record the change in the MasterPlan Surprises & Discoveries
section so the two dependent plans are not silently broken.

**Build configuration this plan owns initially:** the root `cabal.project` `packages:` list. EP-2 and
EP-3 each append their own package directory to it (see MasterPlan Integration Points entry 1). The
`source-repository-package` pin for `hasql-migration` must be preserved.
