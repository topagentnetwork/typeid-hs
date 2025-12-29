# typeid-hs

PostgreSQL migrations for [TypeID](https://github.com/jetify-com/typeid) using [hasql-migration](https://hackage.haskell.org/package/hasql-migration).

TypeID is a type-safe, K-sortable, globally unique identifier inspired by Stripe IDs.

## Installation

Add `typeid-hs` to your `build-depends` in your `.cabal` file:

```cabal
build-depends:
  typeid-hs
```

## Usage

### Running Migrations

```haskell
import Hasql.Connection (acquire, release)
import Hasql.Session (run)
import TypeId.Db.Migration qualified as Migration

main :: IO ()
main = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  result <- run Migration.migrate connection
  case result of
    Right (Right ()) -> putStrLn "Migrations applied successfully"
    Right (Left migrationError) -> print migrationError
    Left sessionError -> print sessionError
  release connection
```

### Validating Migrations

Check migrations without executing them:

```haskell
import Hasql.Connection (acquire, release)
import Hasql.Session (run)
import TypeId.Db.Migration qualified as Migration

validateMigrations :: IO ()
validateMigrations = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  result <- run Migration.validate connection
  case result of
    Right (Right ()) -> putStrLn "All migrations valid"
    Right (Left errors) -> mapM_ print errors
    Left sessionError -> print sessionError
  release connection
```

### Checking Applied Migrations

```haskell
import Hasql.Connection (acquire, release)
import Hasql.Session (run)
import TypeId.Db.Migration qualified as Migration

listMigrations :: IO ()
listMigrations = do
  Right connection <- acquire "host=localhost dbname=mydb user=postgres"
  Right migrations <- run Migration.getMigrations connection
  mapM_ print migrations
  release connection
```

## What Gets Installed

The migrations install the following PostgreSQL objects:

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

```haskell
import TypeId.Db.Migration (version)

main = putStrLn version  -- "v0.0.1"
```
