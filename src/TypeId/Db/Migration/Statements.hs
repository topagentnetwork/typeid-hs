module TypeId.Db.Migration.Statements
  ( getSearchPath,
    setSearchPath,
  )
where

import Data.Text (Text)
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Statement

getSearchPath :: Statement () Text
getSearchPath =
  Statement sql E.noParams decoder True
  where
    decoder = D.singleRow ((D.column . D.nonNullable) D.text)
    sql = "select setting from pg_settings where name = 'search_path'"

setSearchPath :: Statement Text ()
setSearchPath = Statement sql encoder D.noResult True
  where
    encoder = E.param (E.nonNullable E.text)
    sql = "update pg_settings set setting = $1 where name = 'search_path'"
