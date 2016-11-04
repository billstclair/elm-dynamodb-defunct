----------------------------------------------------------------------
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
                              , DynamoServerInfo , makeDynamoDb
                              , makeSimulatedDb
                              , login, put, get, scan, logout
                              , update
                              )

import String
import Dict exposing (Dict)
import Result exposing (Result(..))
import List.Extra as LE

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
  , logout : ( Database model msg -> model -> (model, Cmd msg))
  }

type alias Properties =
  List (String, String)

getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

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
  , backendPort : Properties -> Cmd msg
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

makeDynamoDb serverInfo backendPort dispatcher =
  Dynamo <| DynamoDb serverInfo backendPort dispatcher

makeSimulatedDb profile getDict setDict simulatedPort dispatcher =
  Simulated
    (SimDb profile getDict setDict simulatedPort dispatcher)

---
--- Simulated database API
---

simulatedLogin : SimDb model msg -> model -> Cmd msg
simulatedLogin database model =
  let profile = database.profile
  in
    database.simulatedPort
      [ ("operation", "login")
      , ("email", profile.email)
      , ("name", profile.name)
      , ("userId", profile.userId)
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

dynamoLogin : DynamoDb model msg -> model -> Cmd msg
dynamoLogin database model =
  Cmd.none

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
  Cmd.none

--
-- User-visible database API
--

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
          case getProp "userId" properties of
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
