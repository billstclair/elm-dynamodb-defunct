---------------------------------------------------------------------
--
-- DynamoBackend.elm
-- Talk to Amazon's DynamoDB as a backend for an Elm web app.
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module DynamoBackend exposing ( Profile, Properties, StringDict
                              , Database, ResultDispatcher
                              , ErrorType(..), Error
                              , getProp
                              , DynamoServerInfo , makeDynamoDb, isRealDatabase
                              , makeSimulatedDb
                              , installLoginScript, login, put, get, scan, logout
                              , update
                              )

import String
import Dict exposing (Dict)
import Result exposing (Result(..))
import List
import List.Extra as LE
import Random
import Time
import Http
import Json.Decode as JD
import Task

import Debug exposing (log)

type alias Profile =
  { email : String
  , name : String
  , userId : String
  }

type ErrorType
  = Timeout
  | LoginExpired
  | Other

type alias Error =
  { errorType: ErrorType
  , message : String
  }

type alias ResultDispatcher model msg =
  { login : (Profile -> Database model msg -> model -> (model, Cmd msg))
  , get : (String -> String -> Database model msg -> model -> (model, Cmd msg))
  , put : (String -> String -> Database model msg -> model -> (model, Cmd msg))
  , scan : (List String -> Database model msg -> model -> (model, Cmd msg))
  , logout : (Database model msg -> model -> (model, Cmd msg))
  }

type alias Properties =
  List (String, String)

getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

setProp : String -> String -> Properties -> Properties
setProp key value properties =
  (key, value) :: (List.filter (\(k, _) -> k /= key) properties)

mergeProps : Properties -> Properties -> Properties
mergeProps from to =
  List.foldr
    (\pair props -> setProp (fst pair) (snd pair) props)
    to from

type alias DynamoServerInfo =
  { clientId : String
  , tableName : String
  , appName : String
  , roleArn : String
  , providerId: String
  , awsRegion : String
  }

type alias DynamoDb model msg =
  { serverInfo : DynamoServerInfo
  , getProperties : (model -> Properties)
  , setProperties : (Properties -> model -> model)
  , backendPort : Properties -> Cmd msg
  , backendMsg : Properties -> msg
  , dispatcher : ResultDispatcher model msg
  }

type alias StringDict =
  Dict String String

type alias SimDb model msg =
  { profile: Profile
  , getDict : (model -> StringDict)
  , setDict : (StringDict -> model -> model)
  , simulatedPort : (Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model msg
  }

type Database model msg
  = Simulated (SimDb model msg)
  | Dynamo (DynamoDb model msg)

makeDynamoDb
  serverInfo getProperties setProperties backendPort backendMsg dispatcher =
    Dynamo <|
      DynamoDb
        serverInfo getProperties setProperties backendPort backendMsg dispatcher

makeSimulatedDb profile getDict setDict simulatedPort dispatcher =
  Simulated <|
    SimDb profile getDict setDict simulatedPort dispatcher

isRealDatabase : Database model msg -> Bool
isRealDatabase database =
  case database of
    Simulated _ -> False
    Dynamo _ -> True
---
--- Simulated database API
---

simulatedInstallLoginScript : SimDb model msg -> model -> Cmd msg
simulatedInstallLoginScript database model =
  Cmd.none                      --not necessary for simulator

simulatedLogin : SimDb model msg -> model -> Cmd msg
simulatedLogin database model =
  let profile = database.profile
  in
    database.simulatedPort
      [ ("operation", "login")
      , ("email", profile.email)
      , ("name", profile.name)
      , ("user_id", profile.userId)
      ]
      
simulatedPut : String -> String -> SimDb model msg -> model -> (model, Cmd msg)
simulatedPut key value database model =
  if String.startsWith "!" value then
    -- This provides a way to test error handling
    ( model
    , database.simulatedPort
        [ ("error", String.dropLeft 1 value)
        ]
    )
  else
    let dict = database.getDict model
        model' =
          database.setDict
            (if value == "" then
               Dict.remove key dict
             else
               Dict.insert key value dict)
              model
    in
      ( model'
      , database.simulatedPort
          [ ("operation", "put")
          , ("key", key)
          , ("value", value)
          ]
      )

simulatedGet : String -> SimDb model msg -> model -> Cmd msg
simulatedGet key database model =
  let dict = database.getDict model
      value = case Dict.get key dict of
                Nothing -> ""
                Just v -> v
  in
    database.simulatedPort
      [ ("operation", "get")
      , ("key", key)
      , ("value", value)
      ]

simulatedScan : SimDb model msg -> model -> Cmd msg
simulatedScan database model =
  let dict = database.getDict model
      keys = String.join "\\" (Dict.keys dict)
  in
    database.simulatedPort
      [ ("operation", "scan")
      , ("keys", keys)
      ]

simulatedLogout : SimDb model msg -> model -> Cmd msg
simulatedLogout database model =
  database.simulatedPort
    [ ("operation", "logout")
    ]

--
-- Real database API. Not done yet.
--

dynamoInstallLoginScript : DynamoDb model msg -> model -> Cmd msg
dynamoInstallLoginScript database model =
  database.backendPort
    [ ("operation", "installLoginScript") ]

intGenerator : Random.Generator Int
intGenerator = Random.int Random.minInt Random.maxInt

genRandom : String -> DynamoDb model msg -> Cmd msg
genRandom operation database =
  Random.generate
    (\int ->
       database.backendMsg
         [ ("operation", operation)
         , ("random", toString int)
         ]
    )
    intGenerator

dynamoLogin : DynamoDb model msg -> model -> Cmd msg
dynamoLogin database model =
  genRandom "login-with-state" database

dynamoLoginWithState : String -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoLoginWithState state database model =
  let properties = database.getProperties model
      model' = database.setProperties
                 (setProp "expectedState" state properties) model
  in
    ( model'
    , database.backendPort
        [ ("operation", "login")
        , ("state", state)
        ]
    )

makeMsgCmd : msg -> Cmd msg
makeMsgCmd msg =
  Task.perform identity identity (Task.succeed msg)

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

fetchProfileError : DynamoDb model msg -> Http.Error -> msg
fetchProfileError database error =
  let msg = case error of
              Http.Timeout -> "timeout"
              Http.NetworkError -> "network error"
              Http.UnexpectedPayload json ->
                "Unexpected Payload: " ++ json
              Http.BadResponse code err ->
                "Bad Response: " ++ (toString code) ++ err
  in
    database.backendMsg
      [("error" , "Profile fetch error: " ++ msg)]
  
profileReceived : DynamoDb model msg -> Properties -> msg
profileReceived database properties =
  database.backendMsg
    <| setProp "operation" "login" properties

getAmazonUserProfile : String -> DynamoDb model msg -> Cmd msg
getAmazonUserProfile accessToken database =
  let task = Http.send
               defaultSettings
               { verb = "get"
               , headers = [("authorization", "bearer " ++ accessToken)]
               , url = "https://api.amazon.com/user/profile"
               , body = Http.empty
               }
      decoded = Http.fromJson (JD.keyValuePairs JD.string) task
  in
      Task.perform
        (fetchProfileError database) (profileReceived database) decoded

-- Got an access token from the login code
-- Need to look up the Profile
dynamoAccessToken : Properties -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoAccessToken properties database model =
  let modelProps = database.getProperties model
      err = case getProp "expectedState" modelProps of
              Nothing -> ""
              Just expected ->
                case getProp "state" properties of
                  Nothing -> "No state returned from login"
                  Just state ->
                    if state == expected then
                      ""
                    else
                      "Cross-site Request Forgery attempt."
  in
    if err /= "" then
      ( model
      , makeMsgCmd
          <| database.backendMsg [("error", err)]
      )
    else
      case getProp "access_token" properties of
        Nothing ->
          ( model
          , makeMsgCmd
              <| database.backendMsg
                   [("error", "No access token returned from login.")]
          )
        Just accessToken ->
            (database.setProperties
               (mergeProps properties modelProps) model
            , getAmazonUserProfile accessToken database
            )

dynamoPut : String -> String -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoPut key value database model =
  (model, Cmd.none)

dynamoGet : String -> DynamoDb model msg -> model -> Cmd msg
dynamoGet key database model =
  Cmd.none

dynamoScan : DynamoDb model msg -> model -> Cmd msg
dynamoScan database model =
  Cmd.none

dynamoLogout : DynamoDb model msg -> model -> Cmd msg
dynamoLogout database model =
  let props = [("operation", "logout")]
  in
    Cmd.batch
      [ database.backendPort props
      , makeMsgCmd <| database.backendMsg props
      ]

--
-- User-visible database API
--

installLoginScript : Database model msg -> model -> Cmd msg
installLoginScript database model =
  case database of
    Simulated simDb ->
      simulatedInstallLoginScript simDb model
    Dynamo dynamoDb ->
      dynamoInstallLoginScript dynamoDb model

login : Database model msg -> model -> Cmd msg
login database model =
  case database of
    Simulated simDb ->
      simulatedLogin simDb model
    Dynamo dynamoDb ->
      dynamoLogin dynamoDb model

put : String -> String -> Database model msg -> model -> (model, Cmd msg)
put key value database model =
  case database of
    Simulated simDb ->
      simulatedPut key value simDb model
    Dynamo dynamoDb ->
      dynamoPut key value dynamoDb model

get : String -> Database model msg -> model -> Cmd msg
get key database model =
  case database of
    Simulated simDb ->
      simulatedGet key simDb model
    Dynamo dynamoDb ->
      dynamoGet key dynamoDb model

scan : Database model msg -> model -> Cmd msg
scan database model =
  case database of
    Simulated simDb ->
      simulatedScan simDb model
    Dynamo dynamoDb ->
      dynamoScan dynamoDb model

logout : Database model msg -> model -> Cmd msg
logout database model =
  case database of
    Simulated simDb ->
      simulatedLogout simDb model
    Dynamo dynamoDb ->
      dynamoLogout dynamoDb model

--
-- Call this from the command that comes from the DynamoDb port or the simulator
--

otherError : String -> Error
otherError message =
  { errorType = Other
  , message = message
  }

update : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
update properties database model =
  case getProp "error" properties of
    Just err ->
      -- This needs more fleshing out
      Err <| otherError <| "Backend error: " ++ err
    Nothing ->
      let operation = case getProp "operation" properties of
                        Nothing -> "missing"
                        Just op -> op
      in
        case operation of
          "login" ->
            updateLogin properties database model
          "login-with-state" ->
            updateLoginWithState properties database model
          -- from loginCompleteInternal() in dynamo-backend.js
          "access-token" ->
            updateAccessToken properties database model
          "get" ->
            updateGet properties database model
          "put" ->
            updatePut properties database model
          "scan" ->
            updateScan properties database model
          "logout" ->
            updateLogout properties database model
          "missing" ->
            Err <| otherError "Missing operation in properties."
          _ ->
            Err  <| otherError <| "Unknown operation: " ++ operation
            
getDispatcher : Database model msg -> ResultDispatcher model msg
getDispatcher database =
  case database of
    Simulated simDb -> simDb.dispatcher
    Dynamo dynDb -> dynDb.dispatcher

updateLoginWithState : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateLoginWithState properties database model =
  case database of
    Simulated _ -> Ok (model, Cmd.none)
    Dynamo dynDb ->
      let state = case getProp "random" properties of
                    Nothing -> "foo"
                    Just s -> s
      in
        Ok <| dynamoLoginWithState state dynDb model

updateAccessToken : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateAccessToken properties database model =
  case database of
    Simulated _ -> Ok (model, Cmd.none)
    Dynamo dynDb ->
      Ok <| dynamoAccessToken properties dynDb model

updateLogin : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateLogin properties database model =
  case getProp "email" properties of
    Nothing ->
      Err <| otherError "Missing email in login return."
    Just email ->
      case getProp "name" properties of
        Nothing ->
          Err <| otherError "Missing name in login return."
        Just name ->
          case getProp "user_id" properties of
            Nothing ->
              Err <| otherError "Missing userId in login return."
            Just userId ->
              let profile = { email = email
                            , name = name
                            , userId = userId
                            }
                  dispatcher = getDispatcher database
              in
                Ok <| dispatcher.login profile database model

updateGet : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateGet properties database model =
  case getProp "key" properties of
    Nothing ->
      Err <| otherError "Missing key in get return."
    Just key ->
      case getProp "value" properties of
        Nothing ->
          Err <| otherError "Missing value in get return."
        Just value ->
          let dispatcher = getDispatcher database
          in
            Ok <| dispatcher.get key value database model

updatePut : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updatePut properties database model =
  case getProp "key" properties of
    Nothing ->
      Err <| otherError "Missing key in put return."
    Just key ->
      case getProp "value" properties of
        Nothing ->
          Err <| otherError "Missing value in put return."
        Just value ->
          let dispatcher = getDispatcher database
          in
            Ok <| dispatcher.put key value database model

updateScan : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateScan properties database model =
  case getProp "keys" properties of
    Nothing ->
      Err <| otherError "Missing value in get return."
    Just keystr ->
      let dispatcher = getDispatcher database
          keys = case keystr of
                   "" -> []
                   _ -> String.split "\\" keystr
      in
        Ok <| dispatcher.scan keys database model

updateLogout : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateLogout properties database model =
  let dispatcher = getDispatcher database
  in
    Ok <| dispatcher.logout database model

