module Main exposing (..)

import App
import Browser


main : Program () App.Model App.Msg
main =
    Browser.application
        { init = App.init
        , update = App.update
        , view = App.view
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = App.LinkClicked
        , onUrlChange = App.UrlChanged
        }
