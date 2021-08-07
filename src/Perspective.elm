module Perspective exposing (..)

import FullyQualifiedName as FQN exposing (FQN)
import Hash exposing (Hash)
import Json.Decode as Decode exposing (field)


type Perspective
    = Codebase Hash
    | Namespace { codebaseHash : Hash, fqn : FQN }


codebaseHash : Perspective -> Hash
codebaseHash perspective =
    case perspective of
        Codebase hash_ ->
            hash_

        Namespace d ->
            d.codebaseHash


fqn : Perspective -> FQN
fqn perspective =
    case perspective of
        Codebase _ ->
            FQN.fromString "."

        Namespace d ->
            d.fqn


toParams : Perspective -> PerspectiveParams
toParams perspective =
    case perspective of
        Codebase hash ->
            ByCodebase (Absolute hash)

        Namespace d ->
            ByNamespace (Absolute d.codebaseHash) d.fqn


fromParams : PerspectiveParams -> Maybe Perspective
fromParams params =
    case params of
        ByCodebase Relative ->
            Nothing

        ByNamespace Relative _ ->
            Nothing

        ByCodebase (Absolute h) ->
            Just (Codebase h)

        ByNamespace (Absolute h) fqn_ ->
            Just (Namespace { codebaseHash = h, fqn = fqn_ })



-- Decode ---------------------------------------------------------------------


decode : PerspectiveParams -> Decode.Decoder Perspective
decode perspectiveParams =
    let
        make codebaseHash_ =
            case perspectiveParams of
                ByCodebase _ ->
                    Codebase codebaseHash_

                ByNamespace _ fqn_ ->
                    Namespace { codebaseHash = codebaseHash_, fqn = fqn_ }
    in
    Decode.map make (field "namespaceListingHash" Hash.decode)



-- PerspectiveParams ----------------------------------------------------------
-- These are how a perspective is represented in the url, supporting relative
-- URLs; "latest" vs the absolute URL with a codebase hash.


type CodebasePerspectiveParam
    = Relative
    | Absolute Hash


type PerspectiveParams
    = ByCodebase CodebasePerspectiveParam
    | ByNamespace CodebasePerspectiveParam FQN