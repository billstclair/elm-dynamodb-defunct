----------------------------------------------------------------------
--
-- SharedUI.elm
-- Shared part of example applications for Amazon DynamoDB backend
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module SharedUI exposing ( Model, Msg (..), Database
                         , sharedInit, sharedView, update
                         , dispatcher, makeMsgCmd
                         , getDbDict, setDbDict)

import DynamoBackend as DB

import Html exposing ( Html, Attribute
                     , div, h1, h2, text, input, button, a, img, p
                     , table, tr, td, th)
import Html.Attributes exposing ( href, id, alt, src, width, height, style, value)
import Html.Events exposing (onClick, onInput, on, keyCode)
import Html.App as App
import String
import Char
import List
import List.Extra as LE
import Debug exposing (log)
import Task
import Dict exposing (Dict)
import Json.Decode as Json

-- MODEL

type alias Model =
  { dbDict : DB.StringDict      -- used by the backend simulator
  , database : DbType
  , profile : Maybe DB.Profile  -- Nothing until logged in
  , keys : List String          -- keys returned by DB.scan
  , valueDict : DB.StringDict   -- used by this code to cache key/value pairs
  , key : String                -- displayed key input
  , value : String              -- displayed value input
  , error : String
  }

mdb : Model -> Database
mdb model =
  case model.database of
    Db res -> res
  
type alias Database =
  DB.Database Model Msg

-- Hack to prevent recursive type aliases
type DbType
  = Db Database

loginReceiver : DB.Profile -> Database -> Model -> (Model, Cmd Msg)
loginReceiver profile database model =
  ( { model | profile = Just profile }
  , DB.scan 0 database model
  )

insertInKeys : String -> List String -> List String
insertInKeys key keys =
  if not (List.member key keys) then
    List.sort (key :: keys)
  else
    keys

getReceiver : String -> String -> Database -> Model -> (Model, Cmd Msg)
getReceiver key value database model =
  ( if value == "" then
      { model | value = value }
      else
        { model |
          value = value
        , keys = insertInKeys key model.keys
        , valueDict = Dict.insert key value model.valueDict
        }
  , Cmd.none
  )

putReceiver : String -> String -> Database -> Model -> (Model, Cmd Msg)
putReceiver key value database model =
  ( if value == "" then
      { model |
        keys = LE.remove key model.keys
      , valueDict = Dict.remove key model.valueDict
      }
    else
      { model |
        keys = insertInKeys key model.keys
      , valueDict = Dict.insert key value model.valueDict
      }
  , Cmd.none
  )

scanReceiver : List String -> Database -> Model -> (Model, Cmd Msg)
scanReceiver keys database model =
  ( { model |
      keys = keys
    , valueDict = Dict.empty
    }
  , Cmd.none
  )

logoutReceiver : Database -> Model -> (Model, Cmd Msg)
logoutReceiver database model =
  ( { model |
      profile = Nothing
    , key = ""
    , value = ""
    , keys = []
    , valueDict = Dict.empty
    }
  , Cmd.none
  )

makeMsgCmd : Msg -> Cmd Msg
makeMsgCmd msg =
  Task.perform
    (\x -> Nop)
    (\x -> msg)
    (Task.succeed 1)

backendCmd : Int -> DB.Properties -> Cmd Msg
backendCmd tag properties =
  makeMsgCmd <| BackendMsg tag properties

dispatcher : DB.ResultDispatcher Model Msg
dispatcher =
  DB.ResultDispatcher
    loginReceiver getReceiver putReceiver scanReceiver logoutReceiver

getDbDict = .dbDict

setDbDict : Dict String String -> Model -> Model
setDbDict dict model =
  { model | dbDict = dict }

sharedInit : Database -> (Model, Cmd msg)
sharedInit database =
  ( { dbDict = Dict.empty
    , database = Db database
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
  | Keydown Int
  | Login
  | Logout
  | Get
  | Put
  | SetKey String
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
    Keydown key ->
      ( model
      , if key == 13 then       --carriage return
          makeMsgCmd Put
        else
          Cmd.none
      )
    Login ->
      case model.profile of
        Nothing -> (model, DB.login 0 (mdb model) model)
        Just _ -> (model, Cmd.none)
    Logout ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just _ -> (model, DB.logout 0 (mdb model) model)
    Get ->
      case model.key of
        "" -> (model, Cmd.none)
        key -> (model, DB.get 0 key (mdb model) model)
    Put ->
      case model.key of
        "" -> (model, Cmd.none)
        key ->
          DB.put 0 key model.value (mdb model) model
    SetKey key ->
      ( { model | key = key }
      , makeMsgCmd Get
      )
    BackendMsg tag properties ->
      case DB.update tag properties (mdb model) model of
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
-- In the apps that import this module

-- VIEW

stringFromCode : Int -> String
stringFromCode code =
  String.fromList [ (Char.fromCode code) ]

nbsp : String
nbsp = stringFromCode 160   -- \u00A0

copyright: String
copyright = stringFromCode 169  -- \u00A9

br : Html msg
br = Html.br [][]

borderStyle : Attribute msg
borderStyle =
  style [("border", "1px solid black")]

onKeydown : (Int -> msg) -> Attribute msg
onKeydown tagger =
  on "keydown" (Json.map tagger keyCode)

sharedView : String -> Model -> Html Msg
sharedView subheader model =
  div [ style [ ("width", "40em")
              , ("margin", "5em auto")
              , ("padding", "2em")
              , ("border", "solid blue")
              ]
      ]
    [ h1 []
        [ text "Amazon DynamoDB Backend Example" ]
    , h2 []
        [ text subheader ]
    ,case model.profile of
        Nothing ->
          div []
              [ button [ onClick Login ] [ text "Login" ]
              ]
        Just profile ->
          div []
              [
               p []
                 [ text <| profile.name ++ "<" ++ profile.email ++ "> "
                 , button [ onClick Logout ] [ text "Logout" ]
                 ]
              , div []
                [ text "Key: "
                , input
                    [ onInput UpdateKey
                    , onKeydown Keydown
                    , value model.key
                    ] []
                , text " Value: "
                , input
                    [ onInput UpdateValue
                    , onKeydown Keydown
                    , value model.value
                    ] []
                , text " "
                , button [ onClick Put ] [ text "Put" ]
                , text " "
                , button [ onClick Get ] [ text "Get" ]
                , div [ style [("color", "red")] ]
                    [ text <| case model.error of
                                "" -> nbsp
                                err -> err
                    ]
                ]
              , table [ borderStyle ]
                ((tr [] [ th [ borderStyle
                             , style [("width", "10em")]
                             ]
                            [ text "Key" ]
                        , th [ borderStyle
                             , style [("width", "20em")]
                             ]
                          [ text "Value" ]
                        ])
                ::
                   (rowLoop model.keys model.valueDict [])
                )
              , p []
                [ text "Click on a key in the table to fetch its value." ]
              ]
    , p []
      [ text "Code at: "
      , a [ href "https://github.com/billstclair/elm-dynamodb" ]
        [ text "github.com/billstclair/elm-dynamodb" ]
      ]
    ]

rowLoop : List String -> DB.StringDict -> List (Html Msg) -> List (Html Msg)
rowLoop keys dict res =
  case keys of
    [] -> List.reverse res
    ( key :: tail ) ->
      let value = case Dict.get key dict of
                    Nothing -> nbsp
                    Just v -> v
          row = tr []
                [ td [ borderStyle
                     , onClick <| SetKey key ]
                    [ text key ]
                , td [ borderStyle ]
                    [ text value ]
                ]
      in
        rowLoop tail dict (row :: res)
