let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/02a8a876f6f7074510eb03071116d57f5529378b/package.dhall
        sha256:a19f5dd9181db28ba7a6a1b77b5ab8715e81aba3e2a8f296f40973003a0b4412

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "typeid-hs"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some "PostgreSQL migrations for TypeID using hasql-migration"
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
        , name = "typeid-hs"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "."
        , description = Some "PostgreSQL migrations for TypeID using hasql-migration"
        }
      ]
    , dependencies =
      [ "shinzui/hasql-migration"
      , "hasql/hasql"
      , "ekmett/lens"
      ]
    }
