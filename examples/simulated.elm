----------------------------------------------------------------------
--
-- simulated.elm
-- Example appication for talking to the simulated Amazon DynamoDB backend
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

import DynamoBackend as DB
import ExampleModel exposing (..)

import Html exposing (Html, div, h1, text, input, button, a, img, p)
import Html.Attributes exposing (href, id, alt, src, width, height, style)
import Html.Events exposing (onClick, onInput)
import Html.App as App
import String
import List
import Debug exposing (log)
import Task
import Dict exposing (Dict)

main =
  App.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

-- MODEL

database : DB.Database Model Msg
database =
  let dispatcher =
        DB.ResultDispatcher
          loginReceiver getReceiver putReceiver scanReceiver logoutReceiver
  in
    DB.makeSimulatedDb
      profile .dbDict setDbDict backendCmd dispatcher

init : (Model, Cmd msg)
init =
  ( { dbDict = Dict.empty
    , profile = Nothing
    , keys = []
    , valueDict = Dict.empty
    , key = ""
    , value = ""
    , error = ""
    }
  , Cmd.none 
  )

-- UPDATE

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Nop ->
      ( model, Cmd.none )
    UpdateKey key ->
      ( { model | key = key }
      , Cmd.none
      )
    UpdateValue value ->
      ( { model | value = value }
      , Cmd.none
      )
    Login ->
      case model.profile of
        Nothing -> (model, DB.login 0 database model)
        Just _ -> (model, Cmd.none)
    Logout ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just _ -> (model, DB.logout 0 database model)
    Get ->
      case model.key of
        "" -> (model, Cmd.none)
        key -> (model, DB.get 0 key database model)
    Put ->
      case model.key of
        "" -> (model, Cmd.none)
        key -> case model.value of
                 "" -> (model, Cmd.none)
                 value -> DB.put 0 key value database model
    BackendMsg tag properties ->
      case DB.update tag properties database model of
        Err error ->
          -- Eventually, this will want to retry
          ( { model | error = error.message }
          , Cmd.none
          )
        Ok (model', cmd) ->
          ( { model' | error = "" }
          , cmd
          )

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none

-- VIEW

br : Html msg
br = Html.br [][]

view : Model -> Html Msg
view model =
  div [ style [ ("width", "40em")
              , ("margin", "5em auto")
              , ("padding", "2em")
              , ("border", "solid blue")
              ]
      ]
    [ case model.profile of
        Nothing ->
          div []
              [ button [ onClick Login ] [ text "Login" ]
              ]
        Just profile ->
          div []
              [
               text "Key: "
              , input [ onInput UpdateKey ] []
              , text " Value: "
              , input [ onInput UpdateValue ] []
              ]
    , br
    , p []
      [ text "Code at: "
      , a [ href "https://github.com/billstclair/elm-dynamodb" ]
        [ text "github.com/billstclair/elm-dynamodb" ]
      ]
    ]
