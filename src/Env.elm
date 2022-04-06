module Env exposing (..)

import Api exposing (ApiBasePath(..))
import Browser.Navigation as Nav
import Code.CodebaseApi as CodebaseApi
import Code.Config
import Code.Perspective exposing (Perspective)
import Lib.Api
import Lib.OperatingSystem as OS exposing (OperatingSystem)


type alias Env =
    { operatingSystem : OperatingSystem
    , basePath : String
    , apiBasePath : ApiBasePath
    , navKey : Nav.Key
    , perspective : Perspective
    }


type alias Flags =
    { operatingSystem : String
    , basePath : String
    , apiBasePath : List String
    }


init : Flags -> Nav.Key -> Perspective -> Env
init flags navKey perspective =
    { operatingSystem = OS.fromString flags.operatingSystem
    , basePath = flags.basePath
    , apiBasePath = ApiBasePath flags.apiBasePath
    , navKey = navKey
    , perspective = perspective
    }


toCodeConfig : CodebaseApi.ToApiEndpointUrl -> Env -> Code.Config.Config
toCodeConfig toApiEndpointUrl env =
    let
        (ApiBasePath path) =
            env.apiBasePath

        apiBasePath =
            Lib.Api.ApiBasePath path
    in
    { operatingSystem = env.operatingSystem
    , perspective = env.perspective
    , toApiEndpointUrl = toApiEndpointUrl
    , apiBasePath = apiBasePath
    }
