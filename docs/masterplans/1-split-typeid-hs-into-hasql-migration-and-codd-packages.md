---
id: 1
slug: split-typeid-hs-into-hasql-migration-and-codd-packages
title: "Split typeid-hs into hasql-migration and codd packages"
kind: master-plan
created_at: 2026-06-06T14:28:09Z
intention: "intention_01kteks21kes6rcgdxpc96x5s2"
---

# Split typeid-hs into hasql-migration and codd packages

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

Today this repository is a single Haskell library named `typeid-hs`. It ships a set of
PostgreSQL functions, types, and an operator that implement TypeID (a type-safe,
K-sortable, globally unique identifier) and applies them to a database using the
`hasql-migration` library. The actual SQL lives in `database/v0.0.1/*.sql` and is embedded
into the library with Template Haskell. The only way to consume these migrations is through
`hasql-migration`.

After this initiative, the same SQL is delivered through **three** cabal packages in one
repository (a cabal "monorepo" — multiple packages built from one `cabal.project`):

- `typeid-hs-sql` — a small, tool-agnostic package that embeds the raw SQL once and exposes
  it as ordinary Haskell values (the version string, the ordered list of file names, and each
  file's name plus its bytes). It depends on neither `hasql` nor `codd`.
- `typeid-hs-hasql-migration` — the existing `hasql-migration` backend, renamed from
  `typeid-hs`. Its public modules and behavior are preserved exactly (`TypeId.Db.Migration`
  and friends), but its internals now consume `typeid-hs-sql` instead of embedding the SQL
  themselves.
- `typeid-hs-codd` — a new backend that applies the same SQL through the `codd` migration
  library (`mzabani/codd`). It exposes the migrations as `codd` values and a thin function to
  apply them, embracing `codd`'s forward-only, schema-verifying model.

The user-visible outcome: a downstream project can choose its migration tooling. A project
already standardized on `hasql`/`hasql-migration` depends on `typeid-hs-hasql-migration`; a
project standardized on `codd` depends on `typeid-hs-codd`. Both install the identical set of
PostgreSQL objects (`uuid_generate_v7()`, `base32_encode`/`base32_decode`, the `typeid`
composite type, `typeid_generate*`, `typeid_parse`, `typeid_print`, `typeid_check*`, and the
`===` operator).

**Explicitly in scope:** the three-package split; preserving the existing public API under the
renamed `typeid-hs-hasql-migration`; a working `codd` backend; updating build wiring
(`cabal.project`, the Nix flake, `mori.dhall`) and the README.

**Explicitly out of scope:** changing the SQL itself or adding new TypeID functionality;
publishing to Hackage; adding a CI pipeline; adding `codd`'s on-disk expected-schema snapshot
files to this repository (the `codd` backend ships migrations as values and leaves
schema-snapshot ownership to the consuming service, per `codd`'s own guidance).

**Breaking change, accepted deliberately:** the package `typeid-hs` ceases to exist; it is
renamed to `typeid-hs-hasql-migration`. Existing consumers must update their `build-depends`.
This was chosen over keeping the `typeid-hs` name because a bare `typeid-hs` name is confusing
once two backends exist.


## Decomposition Strategy

The initiative decomposes by **functional concern**, not by file. The hard problem is
coordination: all three packages must agree on one shared interface (the SQL exposed by
`typeid-hs-sql`) and one shared configuration file (`cabal.project`). That shared interface is
what makes a MasterPlan the right tool here.

Four child plans, grouped into three phases:

**Phase 1 — Foundation (EP-1).** Convert the repository from a single package into a
multi-package layout and create `typeid-hs-sql`. This must come first because both backends
depend on the `TypeId.Db.Sql` interface it defines. Until that interface exists and is stable,
neither backend can be written against it.

**Phase 2 — Backends (EP-2, EP-3), run in parallel.** EP-2 renames and refactors the existing
`hasql-migration` code onto `typeid-hs-sql`. EP-3 builds the new `codd` backend on
`typeid-hs-sql`. These two share no code: one depends only on `hasql`/`hasql-migration`, the
other only on `codd`. They touch different directories. They can be implemented concurrently
once EP-1 is complete, with only one shared file to reconcile (`cabal.project`).

**Phase 3 — Finalization (EP-4).** Update the Nix flake, `mori.dhall`, and the README to
reflect the final three-package reality and document the migration path for consumers. This
comes last because it needs the final package names, module names, and public APIs to be
settled by EP-2 and EP-3.

**Alternatives considered and rejected.** (1) *Two packages, no shared core*, with both
backends embedding a shared root `database/` directory via `file-embed`. Rejected because
`file-embed`'s `makeRelativeToProject` resolves against the package root, and cabal's
`extra-source-files`/sdist only reliably bundle files inside the package directory; embedding
`../database` from a subpackage builds locally but is not packaged correctly in an sdist. The
shared-core package sidesteps this by exposing the SQL as a Haskell value that backends
*consume* rather than *re-embed*. (2) *Keeping the `typeid-hs` name* for the hasql backend.
Rejected by explicit user decision: the name is confusing once a second backend exists.
(3) *Folding the finalization work into each backend plan*. Rejected because `mori.dhall`, the
flake, and the README describe the repository as a whole and are cleaner to reconcile once in a
single pass after both backends exist.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Create typeid-hs-sql shared core and multi-package layout | docs/plans/1-create-typeid-hs-sql-shared-core-and-multi-package-layout.md | None | None | Complete |
| 2 | Rename and refactor typeid-hs-hasql-migration onto typeid-hs-sql | docs/plans/2-rename-and-refactor-typeid-hs-hasql-migration-onto-typeid-hs-sql.md | EP-1 | None | Complete |
| 3 | Create typeid-hs-codd package | docs/plans/3-create-typeid-hs-codd-package.md | EP-1 | None | Not Started |
| 4 | Wire nix, mori, and docs for the split packages | docs/plans/4-wire-nix-mori-docs-for-the-split-packages.md | EP-1 | EP-2, EP-3 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 is the root. It creates the `typeid-hs-sql` package and the `TypeId.Db.Sql` module, which
exposes `version :: String`, `migrationFiles :: [FilePath]` (the canonical ordering), and
`sqlFiles :: [(FilePath, ByteString)]` (each migration's name and embedded bytes). Both backends
read their SQL from this module rather than embedding it, so neither can compile until EP-1's
interface exists. EP-1 also converts `cabal.project` from `packages: .` to a multi-package list
and is the package that owns the initial `cabal.project` content.

EP-2 has a hard dependency on EP-1: the renamed `typeid-hs-hasql-migration` package's
`TypeId.Db.Migration.Migrations.V0_0_1` module is rewritten to map `typeid-hs-sql`'s `sqlFiles`
into `Hasql.Migration.MigrationCommand` values, so it will not compile without the `TypeId.Db.Sql`
module.

EP-3 has a hard dependency on EP-1 for the same reason: its `TypeId.Db.Codd.Migration` module
maps `typeid-hs-sql`'s `sqlFiles` into `codd`'s `AddedSqlMigration` values.

EP-2 and EP-3 have **no dependency on each other** and can be implemented in parallel once EP-1
is complete. They share no code and live in separate directories. Their only point of contact is
the `cabal.project` packages list (see Integration Points).

EP-4 has a hard dependency on EP-1 (the multi-package layout must exist) and soft dependencies on
EP-2 and EP-3 (it documents and wires the final package names and APIs, so it is most accurate
once both backends are done). EP-4 can begin partially before EP-2/EP-3 finish, but its README
migration guide and `mori.dhall` dependency list should not be finalized until the backends'
public surfaces are settled.


## Integration Points

**1. `cabal.project` packages list** — touched by EP-1, EP-2, EP-3 (and verified by EP-4).
The shared artifact is the `packages:` stanza listing each package directory. EP-1 is responsible
for converting it from `packages: .` to a multi-package list and seeding it with `./typeid-hs-sql`.
EP-2 adds `./typeid-hs-hasql-migration` and removes the now-obsolete root package entry. EP-3 adds
`./typeid-hs-codd`. Each plan adds only its own line. To avoid conflicts, every plan must read the
current `cabal.project` immediately before editing and append its package path rather than rewriting
the whole list. The `source-repository-package` stanza pinning the `shinzui/hasql-migration` fork
(currently in `cabal.project`) must be preserved by every plan that edits the file. EP-3 must add an
analogous `source-repository-package`/dependency entry for `codd` if `codd` is not resolvable from
the configured package set (see EP-3 for the resolution decision).

**2. The `TypeId.Db.Sql` module interface** — defined by EP-1, consumed by EP-2 and EP-3.
This is the central shared interface of the whole initiative. EP-1 is responsible for defining it
exactly as:

```haskell
module TypeId.Db.Sql
  ( version        -- :: String, currently "v0.0.1"
  , migrationFiles -- :: [FilePath], the ordered base file names
  , sqlFiles       -- :: [(FilePath, ByteString)], each migration's name and embedded bytes, in order
  ) where
```

The ordering of `migrationFiles` and `sqlFiles` is significant — migrations must run in the order
`01_uuidv7.sql`, `02_base32.sql`, `03_typeid.sql`, `04_operator.sql`. EP-2 and EP-3 must consume
this ordering verbatim and must not re-sort or re-embed. If EP-1 changes any name in this interface,
it must update this Integration Points entry and notify EP-2 and EP-3 via the Surprises & Discoveries
section.

**3. The `database/` SQL files location** — moved by EP-1.
The four SQL files currently at `database/v0.0.1/*.sql` move into the `typeid-hs-sql` package
directory (to `typeid-hs-sql/database/v0.0.1/*.sql`) so that `file-embed` and `extra-source-files`
resolve within that package. EP-2 must **delete** its old embedding (the root `database/` directory
and the `embedDir` call in `V0_0_1.hs`) rather than keep a second copy. EP-3 must not create a third
copy. After EP-1, the SQL exists in exactly one place: inside `typeid-hs-sql`.

**4. `mori.dhall` project manifest** — primarily EP-4, but each plan may add its package entry.
The shared artifact is the `packages` and `dependencies` lists in `mori.dhall`. To minimize churn,
EP-1, EP-2, and EP-3 leave `mori.dhall` alone, and EP-4 rewrites the `packages` list to the three
final packages and the `dependencies` list to include `codd` (plus the existing `hasql`,
`hasql-migration`, and `lens`). If a plan finds it must touch `mori.dhall` earlier, it records that
in the MasterPlan Surprises & Discoveries section.

**5. The root `README.md`** — owned by EP-4.
Only EP-4 edits the README, rewriting it to describe both backends and the consumer migration path.
EP-2 and EP-3 must not edit the root README; if they need package-level usage docs, they add a
`README.md` inside their own package directory.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan
and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-1: Multi-package `cabal.project` builds and `typeid-hs-sql` compiles
- [x] EP-1: `TypeId.Db.Sql` exposes `version`, `migrationFiles`, `sqlFiles` from embedded SQL
- [x] EP-2: `typeid-hs-hasql-migration` package exists, renamed from `typeid-hs`
- [x] EP-2: `V0_0_1` consumes `typeid-hs-sql`; old root package and `database/` removed
- [x] EP-2: Public API (`TypeId.Db.Migration` et al.) and behavior preserved; builds clean
- [ ] EP-3: `typeid-hs-codd` package exists and resolves the `codd` dependency
- [ ] EP-3: `TypeId.Db.Codd.Migration` exposes `migrations` and `migrate` over `codd`
- [ ] EP-3: Migrations apply against a real PostgreSQL; TypeID objects verified present
- [ ] EP-4: `mori.dhall` lists three packages and the `codd` dependency
- [ ] EP-4: Nix flake builds/checks all three packages from the dev shell
- [ ] EP-4: README documents both backends and the consumer migration path


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- **hasql session-runner API changed (affects EP-4's README example).** Discovered during EP-2
  Milestone 3: the resolved `hasql` is 1.10.3.2, which no longer exports `run` from
  `Hasql.Session`. The session runner is now
  `Hasql.Connection.use :: Connection -> Session a -> IO (Either SessionError a)` (reversed argument
  order vs. the old `Hasql.Session.run :: Session a -> Connection -> IO (Either QueryError a)`, and a
  new `SessionError` result type). This does **not** affect any package's source — neither backend
  calls `run`/`use`; they only build migration values. It affects the documented "Running Migrations"
  usage example, which EP-4 owns. **EP-4 must write the README example with `Hasql.Connection.use`,
  not `Hasql.Session.run`.** Evidence: `cabal repl` reported `Module 'Hasql.Session' does not export
  'run'`; the verified end-to-end driver `Conn.use c Migration.migrate >>= print` printed
  `Right (Right ())`, and `typeid_generate_text('user')` returned `user_01kteq5as6epdv2fj9p4a17d6w`.


## Decision Log

- Decision: Split into three packages — `typeid-hs-sql` (shared core), `typeid-hs-hasql-migration`,
  and `typeid-hs-codd` — rather than two packages sharing a root `database/` directory.
  Rationale: `file-embed`/sdist only reliably package files inside a package directory; a shared-core
  package exposes the SQL as a Haskell value that backends consume instead of re-embedding from a
  sibling directory, which avoids broken sdists and keeps the version string and file ordering in
  one place.
  Date: 2026-06-06

- Decision: Rename the existing `typeid-hs` package to `typeid-hs-hasql-migration` (a breaking rename),
  rather than keeping the `typeid-hs` name for the hasql backend.
  Rationale: Explicit user decision — a bare `typeid-hs` name is confusing once two backends exist.
  Consumers are expected to update their `build-depends`. Symmetric naming makes the two backends'
  roles obvious.
  Date: 2026-06-06

- Decision: The `typeid-hs-codd` package exposes a codd-idiomatic API (a `migrations` value of type
  `[AddedSqlMigration m]` plus a thin `migrate` wrapper over `Codd.applyMigrations`), defaulting to
  no schema verification (`LaxCheck`), rather than mimicking the hasql backend's `migrate`/`validate`
  Either-returning shape.
  Rationale: `codd` is forward-only and verifies the live schema against a consumer-owned on-disk
  snapshot; it has no honest analogue of `hasql-migration`'s `validate`. `codd`'s own guidance is for
  libraries to ship migrations as Haskell values and let the consuming service own the expected-schema
  snapshot and choose `StrictCheck`. Faking a `validate` would mislead.
  Date: 2026-06-06

- Decision: New package versions all start at `0.1.0.0`.
  Rationale: `typeid-hs-sql` and `typeid-hs-codd` are new package names; `typeid-hs-hasql-migration` is
  a new package name carrying the previously-0.1.0.0 code. Starting all three at `0.1.0.0` is the
  clearest baseline for the new naming scheme.
  Date: 2026-06-06

- Decision: Do not commit `codd` expected-schema snapshot files to this repository.
  Rationale: This is a library, not a service. Per `codd`'s adoption guidance, the consuming service
  owns `CODD_EXPECTED_SCHEMA_DIR`. Shipping a snapshot here would impose this repo's environment
  (roles, encoding, schema set) on every consumer.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

(To be filled during and after implementation.)
