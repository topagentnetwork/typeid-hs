module TypeId.Db.Migration
  ( migrate,
    validate,
    getMigrations,
    M.version,
    migrations,
  )
where

import Hasql.Migration (MigrationCommand (MigrationInitialization), MigrationError, SchemaMigration)
import Hasql.Session (Session)
import TypeId.Db.Migration.Migrations qualified as M
import TypeId.Db.Migration.Sessions qualified as S

migrate :: Session (Either MigrationError ())
migrate = S.migrate migrations

validate :: Session (Either [MigrationError] ())
validate = S.validate migrations

getMigrations :: Session [SchemaMigration]
getMigrations = S.getMigrations

migrations :: [MigrationCommand]
migrations = MigrationInitialization : M.migrations
