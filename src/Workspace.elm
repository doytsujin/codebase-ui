module Workspace exposing
    ( Model
    , Msg
    , OutMsg(..)
    , init
    , open
    , subscriptions
    , update
    , view
    )

import Api exposing (ApiBasePath, ApiRequest)
import Browser.Dom as Dom
import Definition.Doc as Doc
import Definition.Reference as Reference exposing (Reference)
import Env exposing (Env)
import HashQualified exposing (HashQualified(..))
import Html exposing (Html, a, article, div, h2, header, p, section, span, strong, text)
import Html.Attributes exposing (class, href, id, rel, target)
import Http
import KeyboardShortcut exposing (KeyboardShortcut(..))
import KeyboardShortcut.Key exposing (Key(..))
import KeyboardShortcut.KeyboardEvent as KeyboardEvent exposing (KeyboardEvent)
import Route exposing (Route(..))
import Task
import UI
import UI.Button as Button
import UI.Icon as Icon
import Workspace.WorkspaceItem as WorkspaceItem exposing (Item(..), WorkspaceItem(..))
import Workspace.WorkspaceItems as WorkspaceItems exposing (WorkspaceItems)
import Workspace.Zoom as Zoom exposing (Zoom(..))



-- MODEL


type alias Model =
    { workspaceItems : WorkspaceItems
    , keyboardShortcut : KeyboardShortcut.Model
    }


init : Env -> Maybe Reference -> ( Model, Cmd Msg )
init env mRef =
    let
        model =
            { workspaceItems = WorkspaceItems.init Nothing
            , keyboardShortcut = KeyboardShortcut.init env.operatingSystem
            }
    in
    case mRef of
        Nothing ->
            ( model, Cmd.none )

        Just ref ->
            let
                ( m, c, _ ) =
                    open env model ref
            in
            ( m, c )



-- UPDATE


type Msg
    = NoOp
    | Find
    | OpenDefinitionRelativeTo Reference Reference
    | CloseDefinition Reference
    | UpdateZoom Reference Zoom
    | ToggleDocFold Reference Doc.FoldId
    | FetchItemFinished Reference (Result Http.Error Item)
    | Keydown KeyboardEvent
    | KeyboardShortcutMsg KeyboardShortcut.Msg


type OutMsg
    = None
    | Focused Reference
    | Emptied
    | ShowFinderRequest


update : Env -> Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update env msg ({ workspaceItems } as model) =
    case msg of
        NoOp ->
            ( model, Cmd.none, None )

        Find ->
            ( model, Cmd.none, ShowFinderRequest )

        OpenDefinitionRelativeTo relativeToRef ref ->
            openItem env.apiBasePath model (Just relativeToRef) ref

        CloseDefinition ref ->
            let
                nextModel =
                    { model | workspaceItems = WorkspaceItems.remove workspaceItems ref }
            in
            ( nextModel, Cmd.none, openDefinitionsFocusToOutMsg nextModel.workspaceItems )

        UpdateZoom ref zoom ->
            let
                updateMatching workspaceItem =
                    case workspaceItem of
                        Success r d ->
                            if ref == r then
                                Success r { d | zoom = zoom }

                            else
                                workspaceItem

                        _ ->
                            workspaceItem
            in
            ( { model | workspaceItems = WorkspaceItems.map updateMatching workspaceItems }
            , Cmd.none
            , None
            )

        ToggleDocFold ref docId ->
            let
                updateMatching workspaceItem =
                    case workspaceItem of
                        Success r d ->
                            if ref == r then
                                Success r { d | docFoldToggles = Doc.toggleFold d.docFoldToggles docId }

                            else
                                workspaceItem

                        _ ->
                            workspaceItem
            in
            ( { model | workspaceItems = WorkspaceItems.map updateMatching workspaceItems }
            , Cmd.none
            , None
            )

        FetchItemFinished ref itemResult ->
            let
                workspaceItem =
                    case itemResult of
                        Err e ->
                            WorkspaceItem.Failure ref e

                        Ok i ->
                            WorkspaceItem.Success ref
                                { item = i
                                , zoom = Zoom.Medium
                                , docFoldToggles = Doc.emptyDocFoldToggles
                                }

                nextWorkspaceItems =
                    WorkspaceItems.replace workspaceItems ref workspaceItem
            in
            ( { model | workspaceItems = nextWorkspaceItems }
            , Cmd.none
            , openDefinitionsFocusToOutMsg nextWorkspaceItems
            )

        Keydown event ->
            let
                ( keyboardShortcut, kCmd ) =
                    KeyboardShortcut.collect model.keyboardShortcut event.key

                shortcut =
                    KeyboardShortcut.fromKeyboardEvent model.keyboardShortcut event

                ( nextModel, cmd, out ) =
                    handleKeyboardShortcut { model | keyboardShortcut = keyboardShortcut } shortcut
            in
            ( nextModel, Cmd.batch [ cmd, Cmd.map KeyboardShortcutMsg kCmd ], out )

        KeyboardShortcutMsg kMsg ->
            let
                ( keyboardShortcut, cmd ) =
                    KeyboardShortcut.update kMsg model.keyboardShortcut
            in
            ( { model | keyboardShortcut = keyboardShortcut }, Cmd.map KeyboardShortcutMsg cmd, None )



-- UPDATE HELPERS


type alias WithWorkspaceItems m =
    { m | workspaceItems : WorkspaceItems }


open : { a | apiBasePath : ApiBasePath } -> WithWorkspaceItems m -> Reference -> ( WithWorkspaceItems m, Cmd Msg, OutMsg )
open cfg model ref =
    openItem cfg.apiBasePath model Nothing ref


openItem : ApiBasePath -> WithWorkspaceItems m -> Maybe Reference -> Reference -> ( WithWorkspaceItems m, Cmd Msg, OutMsg )
openItem apiBasePath ({ workspaceItems } as model) relativeToRef ref =
    -- We don't want to refetch or replace any already open definitions, but we
    -- do want to focus and scroll to it
    if WorkspaceItems.member workspaceItems ref then
        let
            nextWorkspaceItems =
                WorkspaceItems.focusOn workspaceItems ref
        in
        ( { model | workspaceItems = nextWorkspaceItems }
        , scrollToDefinition ref
        , openDefinitionsFocusToOutMsg nextWorkspaceItems
        )

    else
        let
            toInsert =
                WorkspaceItem.Loading ref

            nextWorkspaceItems =
                case relativeToRef of
                    Nothing ->
                        WorkspaceItems.prependWithFocus workspaceItems toInsert

                    Just r ->
                        WorkspaceItems.insertWithFocusBefore workspaceItems r toInsert
        in
        ( { model | workspaceItems = nextWorkspaceItems }
        , Cmd.batch [ Api.perform apiBasePath (fetchDefinition ref), scrollToDefinition ref ]
        , openDefinitionsFocusToOutMsg nextWorkspaceItems
        )


openDefinitionsFocusToOutMsg : WorkspaceItems -> OutMsg
openDefinitionsFocusToOutMsg openDefs =
    let
        toFocusedOut workspaceItem =
            case workspaceItem of
                Success ref _ ->
                    Focused ref

                _ ->
                    None
    in
    openDefs
        |> WorkspaceItems.focus
        |> Maybe.map toFocusedOut
        |> Maybe.withDefault Emptied


handleKeyboardShortcut : Model -> KeyboardShortcut -> ( Model, Cmd Msg, OutMsg )
handleKeyboardShortcut ({ workspaceItems } as model) shortcut =
    let
        scrollToCmd =
            WorkspaceItems.focus
                >> Maybe.map WorkspaceItem.reference
                >> Maybe.map scrollToDefinition
                >> Maybe.withDefault Cmd.none

        nextDefinition =
            let
                next =
                    WorkspaceItems.next model.workspaceItems
            in
            ( { model | workspaceItems = next }, scrollToCmd next, openDefinitionsFocusToOutMsg next )

        prevDefinitions =
            let
                prev =
                    WorkspaceItems.prev model.workspaceItems
            in
            ( { model | workspaceItems = prev }, scrollToCmd prev, openDefinitionsFocusToOutMsg prev )

        moveDown =
            let
                next =
                    WorkspaceItems.moveDown model.workspaceItems
            in
            ( { model | workspaceItems = next }, scrollToCmd next, openDefinitionsFocusToOutMsg next )

        moveUp =
            let
                next =
                    WorkspaceItems.moveUp model.workspaceItems
            in
            ( { model | workspaceItems = next }, scrollToCmd next, openDefinitionsFocusToOutMsg next )
    in
    case shortcut of
        Chord Alt ArrowDown ->
            moveDown

        Chord Alt ArrowUp ->
            moveUp

        {- TODO: Support vim keys for moving. The reason this isn't straight
           forward is that Alt+j results in the "∆" character instead of a "j"
           (k is "˚") on a Mac. We could add those characters as Chord Alt (Raw
           "∆"), but is it uniform that Alt+j produces "∆" across all standard
           international keyboard layouts? KeyboardEvent.code could be used
           instead of KeyboardEvent.key as it will produce the physical key
           pressed as opposed to the key produced —  this of course is strange
           for things like question marks...

              Chord Alt (J _) ->
                  moveDown
              Chord Alt (K _) ->
                  moveUp
        -}
        Sequence _ ArrowDown ->
            nextDefinition

        Sequence _ (J _) ->
            nextDefinition

        Sequence _ ArrowUp ->
            prevDefinitions

        Sequence _ (K _) ->
            prevDefinitions

        Sequence _ Space ->
            let
                cycleZoom items ref =
                    let
                        mapper item =
                            case item of
                                Success r data ->
                                    if r == ref then
                                        Success r { data | zoom = Zoom.cycle data.zoom }

                                    else
                                        item

                                _ ->
                                    item
                    in
                    WorkspaceItems.map mapper items

                cycled =
                    model.workspaceItems
                        |> WorkspaceItems.focus
                        |> Maybe.map (WorkspaceItem.reference >> cycleZoom model.workspaceItems)
                        |> Maybe.withDefault model.workspaceItems
            in
            ( { model | workspaceItems = cycled }, Cmd.none, None )

        Sequence _ (X _) ->
            let
                without =
                    workspaceItems
                        |> WorkspaceItems.focus
                        |> Maybe.map (WorkspaceItem.reference >> WorkspaceItems.remove workspaceItems)
                        |> Maybe.withDefault workspaceItems
            in
            ( { model | workspaceItems = without }
            , Cmd.none
            , openDefinitionsFocusToOutMsg without
            )

        _ ->
            ( model, Cmd.none, None )



-- EFFECTS


fetchDefinition : Reference -> ApiRequest Item Msg
fetchDefinition ref =
    Api.getDefinition [ (Reference.hashQualified >> HashQualified.toString) ref ]
        |> Api.toRequest WorkspaceItem.decodeItem (FetchItemFinished ref)


scrollToDefinition : Reference -> Cmd Msg
scrollToDefinition ref =
    let
        id =
            "definition-" ++ Reference.toString ref
    in
    Task.sequence
        [ Dom.getElement id |> Task.map (.element >> .y)
        , Dom.getElement "workspace-content" |> Task.map (.element >> .y)
        , Dom.getViewportOf "workspace-content" |> Task.map (.viewport >> .y)
        ]
        |> Task.andThen
            (\outcome ->
                case outcome of
                    elY :: viewportY :: viewportScrollTop :: [] ->
                        Dom.setViewportOf "workspace-content" 0 (viewportScrollTop + (elY - viewportY))
                            |> Task.onError (\_ -> Task.succeed ())

                    _ ->
                        Task.succeed ()
            )
        |> Task.attempt (always NoOp)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    KeyboardEvent.subscribe KeyboardEvent.Keydown Keydown



-- VIEW


viewEmptyState : Env.AppContext -> Html Msg
viewEmptyState appContext =
    let
        fauxDefinition =
            div [ class "faux-definition" ]
                [ UI.loadingPlaceholderRow
                , UI.loadingPlaceholderRow
                ]
    in
    case appContext of
        Env.Ucm ->
            article
                [ id "workspace" ]
                [ section [ class "workspace-empty-state ucm" ]
                    [ section
                        [ class "content" ]
                        [ h2 [] [ text "Your ", span [ class "context" ] [ text "Local" ], text " Unison Codebase" ]
                        , p [] [ text "Browse, search, read docs, open definition and explore explore your local codebase." ]
                        , p []
                            [ text "Check out "
                            , a [ href "https://share.unison-lang.org", rel "noopener", target "_blank" ] [ strong [] [ text "Unison Share" ] ]
                            , text " for community projects."
                            ]
                        , fauxDefinition
                        , fauxDefinition
                        , section [ class "actions" ]
                            [ Button.buttonIconThenLabel Find Icon.search "Find Definitions"
                                |> Button.primaryMono
                                |> Button.medium
                                |> Button.view
                            ]
                        ]
                    ]
                ]

        Env.UnisonShare ->
            article
                [ id "workspace" ]
                [ section [ class "workspace-empty-state unison-share" ]
                    [ section
                        [ class "content" ]
                        [ h2 [] [ text "Unison ", span [ class "context" ] [ text "Share" ] ]
                        , p [] [ text "Explore to discover and share Unison libraries, documentation, types, and terms." ]
                        , fauxDefinition
                        , fauxDefinition
                        , section [ class "actions" ]
                            [ Button.buttonIconThenLabel Find Icon.search "Find Definitions"
                                |> Button.primaryMono
                                |> Button.medium
                                |> Button.view
                            ]
                        ]
                    ]
                ]


view : Env -> Model -> Html Msg
view env model =
    case model.workspaceItems of
        WorkspaceItems.Empty ->
            viewEmptyState env.appContext

        WorkspaceItems.WorkspaceItems _ ->
            article [ id "workspace" ]
                [ header
                    [ id "workspace-toolbar" ]
                    [ Button.button Find "Find" |> Button.view
                    ]
                , section
                    [ id "workspace-content" ]
                    [ section [ class "definitions-pane" ] (viewWorkspaceItems model.workspaceItems) ]
                ]


viewItem : WorkspaceItem -> Bool -> Html Msg
viewItem workspaceItem isFocused =
    let
        ref =
            WorkspaceItem.reference workspaceItem
    in
    WorkspaceItem.view
        (CloseDefinition ref)
        (OpenDefinitionRelativeTo ref)
        (UpdateZoom ref)
        (ToggleDocFold ref)
        workspaceItem
        isFocused


viewWorkspaceItems : WorkspaceItems -> List (Html Msg)
viewWorkspaceItems =
    WorkspaceItems.mapToList viewItem
