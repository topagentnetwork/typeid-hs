module TypeId.Db.Migration.Sessions (migrate, validate, getMigrations) where

import Hasql.Migration (MigrationCommand, MigrationError, SchemaMigration)
import Hasql.Migration qualified as M
import Hasql.Session (Session)
import Hasql.Transaction.Sessions
import TypeId.Db.Migration.Transactions qualified as T

migrate :: (Foldable t) => t MigrationCommand -> Session (Either MigrationError ())
migrate commands = transaction Serializable Write (T.migrate commands)

validate ::
  (Applicative t, Monoid (t MigrationError), Traversable t) =>
  t MigrationCommand ->
  Session (Either (t MigrationError) ())
validate commands = transaction ReadCommitted Read (T.validate commands)

getMigrations :: Session [SchemaMigration]
getMigrations = transaction ReadCommitted Read M.getMigrations
