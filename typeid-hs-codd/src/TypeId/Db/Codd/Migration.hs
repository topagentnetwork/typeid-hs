{-# LANGUAGE FlexibleContexts #-}

module TypeId.Db.Codd.Migration
  ( version,
    migrations,
    applyTypeIdMigrations,
    migrateFromEnv,
  )
where

import Codd
  ( ApplyResult (SchemasNotVerified),
    CoddSettings,
    VerifySchemas,
    applyMigrations,
    applyMigrationsNoCheck,
  )
import Codd.Environment (getCoddSettings)
import Codd.Logging (CoddLogger, runCoddLogger)
import Codd.Parsing
  ( AddedSqlMigration,
    EnvVars,
    PureStream (PureStream),
    parseAddedSqlMigration,
  )
import Codd.Query (NotInTxn)
import Control.Monad.Catch (MonadThrow)
import Control.Monad.IO.Unlift (MonadUnliftIO)
import Data.Maybe (fromJust)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (DiffTime, secondsToDiffTime)
import Streaming.Prelude qualified as S
import TypeId.Db.Sql qualified as Sql

-- | The schema version these migrations implement, sourced from typeid-hs-sql.
version :: String
version = Sql.version

-- | The TypeID migrations as codd values, built from the SQL exposed by
-- typeid-hs-sql. Polymorphic in the monad so a service can splice these into
-- its own migration list before calling codd. Each migration is given a
-- deterministic codd-style timestamped, "-typeid-"-namespaced name so codd
-- orders them correctly and they do not collide with the consumer's own
-- migrations.
migrations :: forall m. (Monad m, EnvVars m) => m [AddedSqlMigration m]
migrations = traverse parseOne (zip [1 :: Int ..] Sql.migrationFiles)
  where
    parseOne :: (Int, FilePath) -> m (AddedSqlMigration m)
    parseOne (i, name) = do
      let bytes = fromJust (lookup name Sql.sqlFiles)
          coddName = "2024-01-01-00-00-" <> pad i <> "-typeid-" <> name
          stream = PureStream (S.yield (decodeUtf8 bytes)) :: PureStream m
      result <- parseAddedSqlMigration coddName stream
      either (error . (("parse codd migration " <> name <> ": ") <>)) pure result
    -- Zero-pad the per-index second so the name keeps the YYYY-MM-DD-HH-MM-SS
    -- shape codd's timestamp parser requires (e.g. index 1 -> "01").
    pad n =
      let s = show n
       in if length s < 2 then '0' : s else s

-- | Apply the TypeID migrations using the supplied codd settings and
-- verification mode. The service owns the CoddSettings (connection string,
-- schema selection, expected-schema snapshot) and decides StrictCheck/LaxCheck.
applyTypeIdMigrations ::
  (MonadUnliftIO m, CoddLogger m, MonadThrow m, EnvVars m, NotInTxn m) =>
  CoddSettings ->
  DiffTime ->
  VerifySchemas ->
  m ApplyResult
applyTypeIdMigrations settings timeout verify = do
  migs <- migrations
  applyMigrations settings (Just migs) timeout verify

-- | Batteries-included entry point: read CoddSettings from environment
-- variables (CODD_CONNECTION, CODD_MIGRATION_DIRS, CODD_EXPECTED_SCHEMA_DIR,
-- and optional CODD_SCHEMAS/...), then apply the TypeID migrations with a
-- five-second connection timeout and __no schema verification__, returning
-- 'SchemasNotVerified'.
--
-- This deliberately does not verify the live schema against an on-disk
-- snapshot. In codd, both 'StrictCheck' and 'LaxCheck' read an expected-schema
-- snapshot from @CODD_EXPECTED_SCHEMA_DIR@ and fail hard if that snapshot is
-- absent (a missing snapshot is an I/O error, not a "schemas differ" result).
-- Because this library does not ship a snapshot — the consuming service owns
-- it — the simple entry point must not require one. A service that owns a
-- snapshot and wants verification should call 'applyTypeIdMigrations' directly
-- with 'StrictCheck' or 'LaxCheck' and its own 'CoddSettings'.
migrateFromEnv :: IO ApplyResult
migrateFromEnv = runCoddLogger $ do
  settings <- getCoddSettings
  migs <- migrations
  _ <- applyMigrationsNoCheck settings (Just migs) (secondsToDiffTime 5) (\_conn -> pure ())
  pure SchemasNotVerified
