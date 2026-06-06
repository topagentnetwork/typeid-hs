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
