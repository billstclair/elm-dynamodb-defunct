----------------------------------------------------------------------
--
-- dynamodb.elm
-- Example application for talking to Amazon's DynamoDB
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

port module DynamoDB exposing (..)

import UrlParser

import Html exposing (Html, div, h1, text, input, button, a, img, p)
import Html.Attributes exposing (href, id, alt, src, width, height, style)
import Html.Events exposing (onClick)
import Navigation as App exposing (Location)
import String
import List
import List.Extra as LE
import Time exposing (Time, minute, second)
import Random
import Debug exposing (log)
import Http
import Task
import Json.Decode as JD

type alias Properties =
  List (String, String)

-- Bool argument ignored.
-- Must have a div with an id of "amazon-root" before calling.
port installLoginScript : Bool -> Cmd msg

-- (login state) includes the state in the returned Properties to loginResponse
port login : String -> Cmd msg

-- Arrives in response to a login command
port loginResponse : (Properties -> msg) -> Sub msg

-- Bool argument ignored
port logout : Bool -> Cmd msg

-- Writing and reading properties.
port saveProperties : (String, Properties) -> Cmd msg
port requestProperties : String -> Cmd msg
port receiveProperties : (Maybe Properties -> msg) -> Sub msg

main =
  App.programWithFlags
    (App.makeParser locationParser)
    { init = init
    , view = view
    , update = update
    , urlUpdate = urlUpdate
    , subscriptions = subscriptions
    }

-- MODEL

--The browser query string as (key, value) pairs
type alias URLQuery =
  List (String, String)

type alias Model =
  { href : String
  , query : URLQuery
  , location : Location
  , dynamoDbProperties: Properties
  , loginProperties : Properties
  , loginLoaded : Bool
  , error : String
  , profile : Properties
  , state : Int
  , expectedState : String
  }

init : Properties -> Location -> (Model, Cmd Msg)
init properties location =
  let (href, query) = UrlParser.parseUrl location.href
  in
      ( { href = href
        , query = query
        , location = location
        , dynamoDbProperties = properties
        , loginProperties = []
        , loginLoaded = False
        , error = ""
        , profile = []
        , state = 0
        , expectedState = ""
        }
      , installLoginScript True
      )

-- UPDATE

type Msg
  = Login
  | LoginResponse Properties
  | FetchProfileError Http.Error
  | ProfileReceived Properties
  | Logout
  | GenerateState Time
  | SetState Int

{-
$c = curl_init('https://api.amazon.com/user/profile');
curl_setopt($c, CURLOPT_HTTPHEADER, array('Authorization: bearer ' . $_REQUEST['access_token']));
curl_setopt($c, CURLOPT_RETURNTRANSFER, true);
-}
defaultSettings : Http.Settings
defaultSettings =
  let settings = Http.defaultSettings
  in
      { settings | timeout = Time.minute }

getAmazonUserProfile : String -> Cmd Msg
getAmazonUserProfile accessToken =
  let task = Http.send
               defaultSettings
               { verb = "GET"
               , headers = [("Authorization", "bearer " ++ accessToken)]
               , url = "https://api.amazon.com/user/profile"
               , body = Http.empty
               }
      decoded = Http.fromJson (JD.keyValuePairs JD.string) task
  in
      Task.perform FetchProfileError ProfileReceived decoded

handleLoginResponse : Properties -> Model -> (Model, Cmd Msg)
handleLoginResponse properties model =
  let model' = { model | loginProperties = properties }
      expectedState = model.expectedState
  in
      case getProp "error_description" properties of
          Just err ->
            ( { model' | error = "Login error: " ++ err }, Cmd.none )
          Nothing ->
            let err = case getProp "state" properties of
                          Nothing -> "No state returned from login"
                          Just state ->
                            if state == expectedState then
                              ""
                            else
                              "Cross-site Request Forgery attempt."
            in
                if err /= "" then
                  ( { model' | error = err }, Cmd.none )
                else
                  case getProp "access_token" properties of
                      Nothing ->
                        ( { model' | error = "No access token returned from login." }
                        , Cmd.none
                        )
                      Just accessToken ->
                        ( model'
                        , getAmazonUserProfile accessToken
                        )

handleProfileError : Http.Error -> Model -> (Model, Cmd Msg)
handleProfileError error model =
  let msg = case error of
                Http.Timeout -> "timeout"
                Http.NetworkError -> "network error"
                Http.UnexpectedPayload json ->
                  "Unexpected Payload: " ++ json
                Http.BadResponse code err ->
                  "Bad Response: " ++ (toString code) ++ err
                  
        in
            ( { model | error = "Profile fetch error: " ++ msg }
            , Cmd.none
            )

handleLogin : Model -> (Model, Cmd Msg)
handleLogin model =
  let state = toString model.state
  in
      ( { model | expectedState = state }
      , login state)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
      Login ->
        handleLogin model
      LoginResponse properties ->
        handleLoginResponse properties model
      FetchProfileError error ->
        handleProfileError error model
      ProfileReceived response ->
        ( { model | profile = response }, Cmd.none)
      Logout ->
        ( { model |
           loginProperties = []
          , profile = []
          }
        , logout True
        )
      GenerateState time ->
        ( model
        , Random.generate SetState <| Random.int Random.minInt Random.maxInt
        )
      SetState state ->
        ( { model | state = state }
        , Cmd.none
        )

getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

-- URLUPDATE

locationParser : Location -> Location
locationParser a =
  a

urlUpdate : Location -> Model -> (Model, Cmd Msg)
urlUpdate location model =
  ({ model | location = location }, Cmd.none)

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch [ loginResponse LoginResponse
            , Time.every second GenerateState
            ]

-- VIEW

br : Html msg
br = Html.br [][]

view : Model -> Html Msg
view model =
  div []
    [ h1 [] [ text "DynamoDB Example" ]
    , div [ id "amazon-root" ] [] --this id is required by the Amazon JavaScript
    , text "Error: "
    , text <| model.error
    , br
    , text "DynamoDB Properties: "
    , text <| toString model.dynamoDbProperties
    , br
    , text "Login Properties: "
    , text <| toString model.loginProperties
    , br
    , text "href: "
    , text <| toString model.href
    , br
    , text "Query: "
    , text <| toString model.query
    , br
    , text "Profile: "
    , text <| toString model.profile
    , br
    , a [ href "#"
        , id "LoginWithAmazon"
        ]
        [ img
            [ onClick Login
            , style [ ("border", "0") ]
            , alt "Login with Amazon"
            , src "https://images-na.ssl-images-amazon.com/images/G/01/lwa/btnLWA_gold_156x32.png"
            , width 156
            , height 32
            ]
            []
        ]
    , case (getProp "name" model.profile) of
          Nothing -> text ""
          Just name ->
            div []
              [ br
              , text "Logged in as: "
              , text name
              ,br
              , a [ href "#"
                  , id "Logout"
                  , onClick Logout
                  ]
                  [ text "Logout" ]
            ]
    , p []
        [ text "Code at: "
        , a [ href "https://github.com/billstclair/elm-dynamodb" ]
          [ text "github.com/billstclair/elm-dynamodb" ]
        ]
    ]
