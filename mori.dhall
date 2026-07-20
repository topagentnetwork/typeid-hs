let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/026ae74331e5c516542af1dd96f041c658ed4621/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "typeid-hs"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some "PostgreSQL TypeID migrations, shipped as hasql-migration, codd, and pg-migrate backends over a shared SQL core"
      , domains = [ "TypeID", "Database" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{
        , name = "typeid-hs"
        , github = Some "topagentnetwork/typeid-hs"
        }
      ]
    , packages =
      [ Schema.Package::{
        , name = "typeid-hs-sql"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-sql"
        , description = Some "Embedded TypeID PostgreSQL SQL, tool-agnostic"
        }
      , Schema.Package::{
        , name = "typeid-hs-hasql-migration"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-hasql-migration"
        , description = Some
            "PostgreSQL TypeID migrations via hasql-migration (deprecated; use typeid-hs-pg-migrate)"
        , lifecycle = Some Schema.Lifecycle.Deprecated
        }
      , Schema.Package::{
        , name = "typeid-hs-codd"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-codd"
        , description = Some
            "PostgreSQL TypeID migrations via codd (deprecated; use typeid-hs-pg-migrate)"
        , lifecycle = Some Schema.Lifecycle.Deprecated
        }
      , Schema.Package::{
        , name = "typeid-hs-pg-migrate"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "typeid-hs-pg-migrate"
        , description = Some "PostgreSQL TypeID migrations via pg-migrate"
        }
      ]
    , dependencies =
      [ "shinzui/hasql-migration"
      , "hasql/hasql"
      , "ekmett/lens"
      , "mzabani/codd"
      , "shinzui/pg-migrate"
      ]
    }
