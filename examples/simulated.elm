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

import Html exposing (Html, div, h1, text, input, button, a, img, p)
import Html.Attributes exposing (href, id, alt, src, width, height, style)
import Html.Events exposing (onClick)
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

type alias Model =
  { dbDict : DB.StringDict      -- used by the backend simulator
  , profile : Maybe DB.Profile  -- Nothing until logged in
  , keys : List String          -- keys returned by DB.scan
  , valueDict : DB.StringDict   -- used by this code to cache key/value pairs
  , key : String                -- displayed key input
  , value : String              -- displayed value input
  , error : String
  }

profile : DB.Profile
profile =
  DB.makeProfile "someone@somewhere.net" "John Doe" "random-sequence-1234"

loginReceiver : DB.Profile -> Model -> (Model, Cmd Msg)
loginReceiver profile model =
  ( { model | profile = Just profile }
  , DB.scan 0 database model
  )

getReceiver : String -> String -> Model -> (Model, Cmd Msg)
getReceiver key value model =
  ( { model |
      value = value
    , valueDict = Dict.insert key value model.valueDict
    }
  , Cmd.none
  )

putReceiver : String -> String -> Model -> (Model, Cmd Msg)
putReceiver key value model =
  ( { model | valueDict = Dict.insert key value model.valueDict }
  , Cmd.none
  )

scanReceiver : List String -> Model -> (Model, Cmd Msg)
scanReceiver keys model =
  ( { model |
      keys = keys
    , valueDict = Dict.empty
    }
  , Cmd.none
  )

dispatcher : DB.ResultDispatcher Model Msg
dispatcher =
  DB.makeResultDispatcher
    loginReceiver getReceiver putReceiver scanReceiver

backendCmd : Int -> DB.Properties -> Cmd Msg
backendCmd tag properties =
  Task.perform
    (\x -> Nop)
    (\x -> BackendMsg tag properties)
    (Task.succeed 1)

database : DB.Database Model Msg
database = DB.makeSimulatedDb
             profile .dbDict setDbDict backendCmd dispatcher

setDbDict : Dict String String -> Model -> Model
setDbDict dict model =
  { model | dbDict = dict }

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

type Msg
  = UpdateKey String
  | UpdateValue String
  | BackendMsg Int DB.Properties
  | Nop

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
  div []
    [ text "Hello World!"
    , p []
        [ text "Code at: "
        , a [ href "https://github.com/billstclair/elm-dynamodb" ]
          [ text "github.com/billstclair/elm-dynamodb" ]
        ]
    ]
