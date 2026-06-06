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
