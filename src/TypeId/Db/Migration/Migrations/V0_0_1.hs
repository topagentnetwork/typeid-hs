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
