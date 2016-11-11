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
                         , dispatcher, makeMsgCmd, backendCmd
                         , getProperties, setProperties
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
  , properties : DB.Properties  -- For DynamoBackend private state
  , profile : Maybe DB.Profile  -- Nothing until logged in
  , keys : List String          -- keys returned by DB.scan
  , valueDict : DB.StringDict   -- used by this code to cache key/value pairs
  , key : String                -- displayed key input
  , value : String              -- displayed value input
  , error : String
  , loggedInOnce : Bool
  }

mdb : Model -> Database
mdb model =
  case model.database of
    Db res -> res

getProperties = .properties

setProperties : DB.Properties -> Model -> Model
setProperties properties model =
  { model | properties = properties }
  
type alias Database =
  DB.Database Model Msg

-- Hack to prevent recursive type aliases
type DbType
  = Db Database

loginReceiver : DB.Profile -> Database -> Model -> (Model, Cmd Msg)
loginReceiver profile database model =
  ( { model |
      profile = Just profile
    , loggedInOnce = True
    }
  , if model.loggedInOnce then
      -- This should retry the command that got the AccessExpired error.
      -- Go ahead. Call me lazy.
      Cmd.none
    else
      DB.scan False profile.userId database model
  )

insertInKeys : String -> List String -> List String
insertInKeys key keys =
  if not (List.member key keys) then
    List.sort (key :: keys)
  else
    keys

getReceiver : String -> Maybe String -> Database -> Model -> (Model, Cmd Msg)
getReceiver key maybeValue database model =
    
  ( case maybeValue of
        Nothing ->
            { model | value = "" }
        Just value ->
            { model |
              value = value
            , keys = insertInKeys key model.keys
            , valueDict = Dict.insert key value model.valueDict
            }
  , Cmd.none
  )

putReceiver : String -> Maybe String -> Database -> Model -> (Model, Cmd Msg)
putReceiver key maybeValue database model =
  ( case maybeValue of
      Nothing ->
        { model |
          keys = LE.remove key model.keys
        , valueDict = Dict.remove key model.valueDict
        }
      Just value ->  
        { model |
          keys = insertInKeys key model.keys
        , valueDict = Dict.insert key value model.valueDict
        }
  , Cmd.none
  )

scanReceiver : List String -> List String -> Database -> Model -> (Model, Cmd Msg)
scanReceiver keys values database model =
  ( { model |
      keys = keys
    , valueDict = Dict.fromList <| List.map2 (,) keys values
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
  Task.perform identity identity (Task.succeed msg)

backendCmd : DB.Properties -> Cmd Msg
backendCmd properties =
  makeMsgCmd <| BackendMsg properties

dispatcher : DB.ResultDispatcher Model Msg
dispatcher =
  DB.ResultDispatcher
    loginReceiver getReceiver putReceiver scanReceiver logoutReceiver

getDbDict = .dbDict

setDbDict : Dict String String -> Model -> Model
setDbDict dict model =
  { model | dbDict = dict }

sharedInit : Database -> (Model, Cmd Msg)
sharedInit database =
  ( { dbDict = Dict.empty
    , database = Db database
    , properties = []
    , profile = Nothing
    , keys = []
    , valueDict = Dict.empty
    , key = ""
    , value = ""
    , error = ""
    , loggedInOnce = False
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
  | Refresh
  | SetKey String
  | BackendMsg DB.Properties
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
        Nothing -> (model, DB.login (mdb model) model)
        Just _ -> (model, Cmd.none)
    Logout ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just _ -> (model, DB.logout (mdb model) model)
    Get ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just profile ->
          case model.key of
            "" -> (model, Cmd.none)
            key -> (model, DB.get profile.userId key (mdb model) model)
    Put ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just profile ->
          case model.key of
            "" -> (model, Cmd.none)
            key ->
              let value = model.value
              in
                  if value == "" then
                    DB.remove profile.userId key (mdb model) model
                  else
                    DB.put profile.userId key value (mdb model) model
    Refresh ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just profile ->
          (model, DB.scan True profile.userId (mdb model) model)
    SetKey key ->
      ( { model | key = key }
      , makeMsgCmd Get
      )
    BackendMsg properties ->
      case DB.update properties (mdb model) model of
        Err error ->
          case error.errorType of
            DB.AccessExpired ->
              ( { model | error = "" }
              , makeMsgCmd Login
              )
            _ ->
              ( { model | error = DB.formatError error }
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

loginButton : Model -> Html Msg
loginButton model =
  if DB.isRealDatabase <| mdb model then
    img [ onClick Login
        , style [ ("border", "0") ]
        , alt "Login with Amazon"
        , src "https://images-na.ssl-images-amazon.com/images/G/01/lwa/btnLWA_gold_156x32.png"
        , width 156
        , height 32
        ]
        []
  else
    button [ onClick Login ] [ text "Login" ]    
    
errorDiv : Model -> Html Msg
errorDiv model =
  div [ style [("color", "red")] ]
    [ text <| case model.error of
                "" -> nbsp
                err -> err
    ]
    
tableAttributes : Model -> List (Attribute Msg)
tableAttributes model =
  if DB.isRealDatabase <| mdb model then
    [ ]
  else
    [ borderStyle ]

sharedView : String -> Model -> Html Msg
sharedView subheader model =
  div [ style [ ("width", "40em")
              , ("margin", "5em auto")
              , ("padding", "2em")
              , ("border", "solid blue")
              ]
      ]
    [ h1 [ style [("margin-bottom", "0")] ]
        [ text "Amazon DynamoDB Backend Example" ]
    , div [ id "amazon-root" ] [] --this id is required by the Amazon JavaScript
    , h2 [ style [("margin-top", "0")] ]
        [ text subheader ]
    ,case model.profile of
        Nothing ->
          div []
              [ loginButton model
              , errorDiv model]
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
                , text " "
                , button [ onClick Refresh ] [ text "Refresh" ]
                , errorDiv model
                ]
              , table (tableAttributes model)
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
      , br
      , text "Instructions "
      , a [ href "https://github.com/billstclair/elm-dynamodb/tree/master/examples#use" ]
        [ text "here" ]
      , text "."
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
