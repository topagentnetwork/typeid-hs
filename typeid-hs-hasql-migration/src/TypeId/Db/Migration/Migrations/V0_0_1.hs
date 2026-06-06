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
