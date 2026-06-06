# typeid-hs

PostgreSQL migrations for [TypeID](https://github.com/jetify-com/typeid), shipped as two
interchangeable backends over a shared SQL core. TypeID is a type-safe, K-sortable, globally
unique identifier inspired by Stripe IDs.

The SQL migrations are sourced from
[typeid-sql](https://github.com/jetify-com/opensource/tree/main/typeid/typeid-sql).

## Packages

This repository builds three packages:

- **`typeid-hs-sql`** — the embedded TypeID SQL exposed as plain Haskell values (the version
  string, the ordered file names, and each file's bytes). Tool-agnostic; depends on neither hasql
  nor codd. The two backends build on it.
- **`typeid-hs-hasql-migration`** — applies the migrations with
  [hasql-migration](https://hackage.haskell.org/package/hasql-migration). Choose this if your
  project already uses hasql.
- **`typeid-hs-codd`** — applies the same migrations with [codd](https://github.com/mzabani/codd).
  Choose this if your project uses codd's forward-only, schema-verifying workflow.

Depend on exactly one backend; it pulls in `typeid-hs-sql` for you. Both backends install the
identical set of PostgreSQL objects (see [What Gets Installed](#what-gets-installed)).

## Migrating from `typeid-hs`

The package formerly named `typeid-hs` is now `typeid-hs-hasql-migration`. Its modules and API are
unchanged — only the package name changed. Update your `build-depends`:

```cabal
build-depends:
  typeid-hs-hasql-migration   -- was: typeid-hs
```

No code changes are needed: `import TypeId.Db.Migration` and the
`migrate`/`validate`/`getMigrations` functions are identical.

## Usage — hasql-migration backend

Add `typeid-hs-hasql-migration` to your `build-depends`.

### Running Migrations

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Hasql.Connection (acquire, release, use)
import TypeId.Db.Migration qualified as Migration

main :: IO ()
main = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  result <- use connection Migration.migrate
  case result of
    Right (Right ()) -> putStrLn "Migrations applied successfully"
    Right (Left migrationError) -> print migrationError
    Left sessionError -> print sessionError
  release connection
```

`Migration.migrate` is a `hasql` `Session`; `Hasql.Connection.use` runs it against a connection and
returns `Either SessionError (Either MigrationError ())`.

### Validating Migrations

Check migrations without executing them:

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Hasql.Connection (acquire, release, use)
import TypeId.Db.Migration qualified as Migration

validateMigrations :: IO ()
validateMigrations = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  result <- use connection Migration.validate
  case result of
    Right (Right ()) -> putStrLn "All migrations valid"
    Right (Left errors) -> mapM_ print errors
    Left sessionError -> print sessionError
  release connection
```

### Checking Applied Migrations

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Hasql.Connection (acquire, release, use)
import TypeId.Db.Migration qualified as Migration

listMigrations :: IO ()
listMigrations = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  Right migrations <- use connection Migration.getMigrations
  mapM_ print migrations
  release connection
```

## Usage — codd backend

Add `typeid-hs-codd` to your `build-depends`. The migrations are exposed as codd
`AddedSqlMigration` values, plus helpers to apply them.

The batteries-included entry point reads its configuration from codd's environment variables and
applies the migrations without verifying the schema (it does not require an expected-schema
snapshot):

```haskell
import Codd (ApplyResult (..))
import TypeId.Db.Codd.Migration (migrateFromEnv)

main :: IO ()
main = do
  -- reads CODD_CONNECTION, CODD_MIGRATION_DIRS, CODD_EXPECTED_SCHEMA_DIR, and optional CODD_SCHEMAS
  result <- migrateFromEnv
  case result of
    SchemasMatch _ -> putStrLn "Migrations applied; schema matches the snapshot"
    SchemasDiffer _ -> putStrLn "Migrations applied; schema differs from the snapshot"
    SchemasNotVerified -> putStrLn "Migrations applied (schema not verified)"
```

To compose the TypeID migrations with your service's own migrations, use `migrations` (a list of
codd `AddedSqlMigration` values) and `applyTypeIdMigrations`, supplying your own `CoddSettings` and
choosing `StrictCheck` or `LaxCheck`:

```haskell
import Codd (CoddSettings, VerifySchemas (StrictCheck))
import Codd.Logging (runCoddLogger)
import Data.Time (secondsToDiffTime)
import TypeId.Db.Codd.Migration (applyTypeIdMigrations)

apply :: CoddSettings -> IO ()
apply settings = runCoddLogger $ do
  -- applyTypeIdMigrations runs in any monad satisfying codd's constraints;
  -- runCoddLogger discharges them to IO (LoggingT IO).
  _ <- applyTypeIdMigrations settings (secondsToDiffTime 5) StrictCheck
  pure ()
```

Note: codd verifies the live database schema against an on-disk snapshot. Both `StrictCheck` and
`LaxCheck` read that snapshot and fail if it is absent, so they require your service to own a
snapshot directory (`CODD_EXPECTED_SCHEMA_DIR`). This package does not ship a snapshot — that is the
consuming service's responsibility. Use `migrateFromEnv` (no verification) when you do not have a
snapshot.

## What Gets Installed

Both backends install the following PostgreSQL objects:

| Object | Description |
|--------|-------------|
| `uuid_generate_v7()` | Function to generate UUIDv7 values |
| `base32_encode(uuid)` | Encode UUID to base32 string |
| `base32_decode(text)` | Decode base32 string to UUID |
| `typeid` | Composite type with prefix and UUID |
| `typeid_generate(prefix)` | Generate a new TypeID |
| `typeid_generate_text(prefix)` | Generate TypeID as text |
| `typeid_parse(text)` | Parse text to TypeID |
| `typeid_print(typeid)` | Convert TypeID to text |
| `typeid_check(typeid, prefix)` | Validate TypeID prefix |
| `typeid_check_text(text, prefix)` | Validate text TypeID prefix |
| `===` operator | Compare TypeID with text |

## SQL Usage Examples

After running migrations, you can use TypeID in PostgreSQL:

```sql
-- Generate a new TypeID
SELECT typeid_generate('user');
-- Returns: (user,018e1a2b-3c4d-7e5f-8a9b-0c1d2e3f4a5b)

-- Generate as text
SELECT typeid_generate_text('user');
-- Returns: user_01h455vb4pex5vsknk084sn02q

-- Parse a TypeID string
SELECT typeid_parse('user_01h455vb4pex5vsknk084sn02q');
-- Returns: (user,018962e7-3a6d-7290-b088-5c4e3bdf918c)

-- Use in a table
CREATE TABLE users (
  id typeid PRIMARY KEY DEFAULT typeid_generate('user'),
  name text NOT NULL
);

-- Query with text comparison
SELECT * FROM users WHERE id === 'user_01h455vb4pex5vsknk084sn02q';
```

## Version

The schema version is available from both backends' top-level modules:

```haskell
import TypeId.Db.Migration (version)        -- hasql-migration backend
-- or
import TypeId.Db.Codd.Migration (version)   -- codd backend

main = putStrLn version  -- "v0.0.1"
```
