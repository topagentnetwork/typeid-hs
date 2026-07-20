module TypeId.Db.PgMigrate.Migration
  ( version,
    componentNameText,
    typeIdComponent,
    typeIdPlan,
    TypeIdMigrateError (..),
    migrateTypeId,
  )
where

import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Text (Text)
import Database.PostgreSQL.Migrate
  ( DefinitionError,
    MigrationComponent,
    MigrationError,
    MigrationPlan,
    MigrationReport,
    PlanError,
    RunOptions,
    migrationComponentFromEmbeddedSql,
    migrationPlan,
    runMigrationPlan,
  )
import Hasql.Connection.Settings qualified as Settings
import TypeId.Db.Sql qualified as Sql

-- | The schema version these migrations implement, sourced from typeid-hs-sql.
version :: String
version = Sql.version

-- | The stable pg-migrate component name that owns the TypeID migrations.
-- Exported so a consuming application can declare a dependency on it (for
-- example @Set.singleton componentNameText@) when composing its own plan.
componentNameText :: Text
componentNameText = "typeid"

-- | The TypeID migrations as a pg-migrate component, built from the ordered SQL
-- exposed by typeid-hs-sql. Each SQL file's base name becomes a migration name
-- by dropping the @.sql@ suffix (e.g. @01_uuidv7.sql@ becomes migration
-- @01_uuidv7@), so the durable migration identities are @typeid/01_uuidv7@,
-- @typeid/02_base32@, @typeid/03_typeid@, and @typeid/04_operator@.
--
-- Returns 'Left' only if the embedded SQL or a derived name is invalid, which
-- cannot happen for the fixed, tested SQL shipped by typeid-hs-sql; in practice
-- this is always 'Right'.
typeIdComponent :: Either DefinitionError MigrationComponent
typeIdComponent =
  migrationComponentFromEmbeddedSql
    componentNameText
    Set.empty
    -- Sql.sqlFiles is statically non-empty (four entries), so fromList is total here.
    (NonEmpty.fromList Sql.sqlFiles)

-- | A single-component plan containing only the TypeID migrations, for the
-- batteries-included case where an application applies just these migrations.
-- Applications that compose TypeID with their own migrations should instead use
-- 'typeIdComponent' directly and build their own plan with 'migrationPlan'.
typeIdPlan :: Either DefinitionError (Either PlanError MigrationPlan)
typeIdPlan = do
  component <- typeIdComponent
  pure (migrationPlan (component :| []))

-- | Flattened failure for the batteries-included 'migrateTypeId' runner.
data TypeIdMigrateError
  = -- | The embedded SQL or a derived migration name was invalid (never happens
    -- for the shipped SQL).
    TypeIdDefinitionError DefinitionError
  | -- | The single-component plan was rejected (never happens for one component).
    TypeIdPlanError PlanError
  | -- | pg-migrate failed while applying the plan against the database.
    TypeIdRunError MigrationError
  deriving stock (Show)

-- | Batteries-included entry point: build the single-component TypeID plan and
-- apply it against the database described by the given Hasql connection
-- settings, using the supplied pg-migrate 'RunOptions' (use 'defaultRunOptions'
-- for the standard @pgmigrate@ ledger, indefinite lock wait, and no events).
-- Applies the migrations in order under pg-migrate's advisory lock and records
-- them in the ledger; rerunning is idempotent (already-applied migrations are
-- reported as 'AlreadyApplied').
migrateTypeId ::
  RunOptions ->
  Settings.Settings ->
  IO (Either TypeIdMigrateError MigrationReport)
migrateTypeId options settings =
  case typeIdComponent of
    Left definitionError -> pure (Left (TypeIdDefinitionError definitionError))
    Right component ->
      case migrationPlan (component :| []) of
        Left planError -> pure (Left (TypeIdPlanError planError))
        Right plan ->
          first TypeIdRunError <$> runMigrationPlan options settings plan
