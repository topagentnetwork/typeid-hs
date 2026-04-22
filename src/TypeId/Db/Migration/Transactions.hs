module TypeId.Db.Migration.Transactions (migrate, validate) where

import Control.Lens (view)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Foldable (fold)
import Data.Functor ((<&>))
import Data.Text (Text)
import Data.Validation (Validation (..))
import Data.Validation qualified as V
import Hasql.Migration (MigrationCommand (..), MigrationError)
import Hasql.Migration qualified as M
import Hasql.Transaction
import TypeId.Db.Migration.Statements qualified as S

getSearchPath :: Transaction Text
getSearchPath = statement () S.getSearchPath

setSearchPath :: Text -> Transaction ()
setSearchPath searchPath = statement searchPath S.setSearchPath

migrate :: (Foldable t) => t MigrationCommand -> Transaction (Either MigrationError ())
migrate migrations = condemnIfNeeded . runExceptT $ do
  searchPath <- lift getSearchPath
  mapM_ runMigration migrations
  lift $ setSearchPath searchPath
  where
    condemnIfNeeded m = do
      res <- m
      case res of
        Left _ -> condemn
        Right () -> pure ()
      pure res

validate ::
  ( Applicative t,
    Monoid (t MigrationError),
    Traversable t
  ) =>
  t MigrationCommand ->
  Transaction (Either (t MigrationError) ())
validate migrations = do
  searchPath <- getSearchPath
  result <-
    traverse validateMigration migrations
      <&> view V.either
        . fold
  setSearchPath searchPath
  pure result

runMigration :: MigrationCommand -> ExceptT MigrationError Transaction ()
runMigration = ExceptT . fmap (maybe (Right ()) Left) . M.runMigration

validateMigration :: (Applicative f) => MigrationCommand -> Transaction (Validation (f MigrationError) ())
validateMigration command =
  M.runMigration (MigrationValidation command)
    <&> maybe (Success ()) (Failure . pure)
