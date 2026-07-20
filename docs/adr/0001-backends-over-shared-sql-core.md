# 1. Migration backends over one shared SQL core

- Status: Accepted
- Date: 2026-07-20
- Supersedes: —
- Superseded by: —

## Context

`typeid-hs` installs a fixed set of PostgreSQL objects for [TypeID](https://github.com/jetify-com/typeid):
a UUIDv7 generator, base32 encode/decode, a `typeid` composite type, the
`typeid_generate*`/`typeid_parse`/`typeid_print`/`typeid_check*` functions, and a `===` operator.
That object set is identical no matter which migration tool applies it, but consuming projects
standardize on different Haskell migration libraries (hasql-migration, codd, pg-migrate). A single
package tied to one migration tool would force its dependency closure — and its workflow — on every
consumer.

Two cross-cutting facts shaped the layout:

- The migration tools this fleet uses (`hasql-migration` fork, `codd`, `pg-migrate`) are **not on
  Hackage**, or are pinned to fleet-specific forks/tags.
- Each tool has its own notion of who owns configuration (connection settings, schema verification,
  ledger schema, lock/timeout policy). That is properly the consuming application's concern, not the
  library's.

This ADR was distilled at the completion of `docs/plans/5-create-typeid-hs-pg-migrate-package.md`,
which added the third backend. The same decisions were made across the earlier split
(`docs/masterplans/1-split-typeid-hs-into-hasql-migration-and-codd-packages.md` and
`docs/plans/3-create-typeid-hs-codd-package.md`); this ADR promotes them to durable project context.

## Decision

1. **One tool-agnostic SQL core, N thin backend packages.** `typeid-hs-sql` embeds the ordered SQL
   at compile time and exposes it as plain values (`version :: String`,
   `migrationFiles :: [FilePath]`, `sqlFiles :: [(FilePath, ByteString)]`), depending on none of the
   migration tools. Each backend is a separate cabal package that consumes `typeid-hs-sql` and adapts
   those bytes into exactly one tool's representation:
   - `typeid-hs-hasql-migration` (module `TypeId.Db.Migration`)
   - `typeid-hs-codd` (module `TypeId.Db.Codd.Migration`)
   - `typeid-hs-pg-migrate` (module `TypeId.Db.PgMigrate.Migration`)

   A consumer depends on exactly one backend; it pulls in `typeid-hs-sql` transitively. There is
   never a second copy of the SQL, and no manifest to keep in sync (for `pg-migrate` specifically,
   this means using the pure `migrationComponentFromEmbeddedSql` smart constructor fed directly from
   `Sql.sqlFiles`, **not** `pg-migrate-embed`'s Template Haskell `embedMigrationManifest`).

2. **Pin fleet database tooling by `source-repository-package`, not Hackage.** Migration engines not
   published to Hackage are pinned in `cabal.project` by git `source-repository-package` at an
   explicit tag/commit (peeling the tag to its commit in the pin), with `subdir:` when the library
   lives in a subdirectory of a multi-package repository. Verify the pinned commit against the
   upstream release tag, and prefer a scoped `allow-newer` / `constraints` entry over widening
   library bounds when a transitive solve needs help. Current pins: `shinzui/hasql-migration`,
   `mzabani/codd`, and `shinzui/pg-migrate` (`v1.1.0.0` = `f39d64e…`, `subdir: pg-migrate`).

3. **The library owns the migrations; the application owns the database and its config.** No backend
   ships its own ledger, schema snapshot, connection settings, or run/verification policy. Each
   exposes (a) the migrations as composable values in the tool's own vocabulary, and (b) a thin
   batteries-included runner for the simplest case. The consuming application supplies connection
   settings and chooses policy (codd's `StrictCheck`/`LaxCheck` + `CODD_EXPECTED_SCHEMA_DIR`;
   pg-migrate's `RunOptions` ledger/lock/timeout and plan composition).

## Consequences

- Adding a fourth backend is a mechanical, self-contained change: a new sibling package consuming
  `typeid-hs-sql`, a `source-repository-package` pin if the tool is not on Hackage, a `mori.dhall`
  package entry + dependency, and a README "Usage — <tool> backend" section. No existing backend
  changes; each stays independently buildable and keeps its tool's dependency closure out of the
  others.
- The SQL is authored and tested in one place; all backends install the byte-identical object set.
- Consumers can compose TypeID with their own migrations in their tool's native model (e.g.
  splicing pg-migrate's `typeIdComponent` into their own ordered plan, declaring a dependency on the
  stable component name `"typeid"` exported as `componentNameText`).
- The trade-off is more packages and a `cabal.project` that pins several git repositories; this is
  accepted as the cost of keeping each backend thin and independently adoptable.
