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
                              , ErrorType (..), Error
                              , makeProfile, makeResultDispatcher, getProp
                              , makeDynamoDb, makeSimulatedDb
                              , login, put, get, scan
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

makeProfile : String -> String -> String -> Profile
makeProfile email name userId =
  { email = email
  , name = name
  , userId = userId
  }

type ErrorType
  = Timeout
  | LoginExpired
  | TagMismatch Int Int
  | Other

type alias Error =
  { errorType: ErrorType
  , message : String
  }

type alias ResultDispatcher model msg =
  { login : (Profile -> model -> (model, Cmd msg))
  , get : (String -> String -> model -> (model, Cmd msg))
  , put : (String -> String -> model -> (model, Cmd msg))
  , scan : (List String -> model -> (model, Cmd msg))
  }

makeResultDispatcher : (Profile -> model -> (model, Cmd msg)) -> (String -> String -> model -> (model, Cmd msg)) -> (String -> String -> model -> (model, Cmd msg)) -> (List String -> model -> (model, Cmd msg)) -> ResultDispatcher model msg
makeResultDispatcher login get put scan =
  { login = login
  , get = get
  , put = put
  , scan = scan
  }

type alias Properties =
  List (String, String)

getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

type alias DynamoDb model msg =
  { clientId : String
  , tableName : String
  , appName : String
  , roleArn : String
  , awsRegion : String
  , backendPort : (Int -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model msg
  }

type alias StringDict =
  Dict String String

type alias SimDb model msg =
  { profile: Profile
  , getDict : (model -> StringDict)
  , setDict : (StringDict -> model -> model)
  , simulatedPort : (Int -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model msg
  }

type Database model msg
  = Simulated (SimDb model msg)
  | Dynamo (DynamoDb model msg)

makeDynamoDb : String -> String -> String -> String -> String -> (Int -> Properties -> Cmd msg) -> ResultDispatcher model msg -> Database model msg
makeDynamoDb clientId tableName appName roleArn awsRegion backendPort dispatcher =
  Dynamo { clientId = clientId
         , tableName = tableName
         , appName = appName
         , roleArn = roleArn
         , awsRegion = awsRegion
         , backendPort = backendPort
         , dispatcher = dispatcher
         }

makeSimulatedDb : Profile -> (model -> StringDict) -> (StringDict -> model -> model) -> (Int -> Properties -> Cmd msg) -> ResultDispatcher model msg -> Database model msg
makeSimulatedDb profile getDict setDict simulatedPort dispatcher =
  Simulated { profile = profile
            , getDict = getDict
            , setDict = setDict
            , simulatedPort = simulatedPort
            , dispatcher = dispatcher
            }

---
--- Simulated database API
---

simulatedLogin : Int -> SimDb model msg -> model -> Cmd msg
simulatedLogin tag database model =
  let profile = database.profile
  in
    database.simulatedPort
      tag
      [ ("tag", toString tag)
      , ("operation", "login")
      , ("email", profile.email)
      , ("name", profile.name)
      , ("userId", profile.userId)
      ]

simulatedPut : Int -> String -> String -> SimDb model msg -> model -> (model, Cmd msg)
simulatedPut tag key value database model =
  let dict = database.getDict model
      model' = database.setDict (Dict.insert key value dict) model
  in
    ( model'
    , database.simulatedPort
        tag
        [ ("tag", toString tag)
        , ("operation", "put")
        , ("key", key)
        ]
    )

simulatedGet : Int -> String -> SimDb model msg -> model -> Cmd msg
simulatedGet tag key database model =
  let dict = database.getDict model
      value = case Dict.get key dict of
                Nothing -> ""
                Just v -> v
  in
    database.simulatedPort
      tag
      [ ("tag", toString tag)
      , ("operation", "get")
      , ("key", key)
      , ("value", value)
      ]

simulatedScan : Int -> SimDb model msg -> model -> Cmd msg
simulatedScan tag database model =
  let dict = database.getDict model
      keys = String.join "\\" (Dict.keys dict)
  in
    database.simulatedPort
      tag
      [ ("tag", toString tag)
      , ("operation", "scan")
      , ("keys", keys)
      ]

--
-- Real database API. Not done yet.
--

dynamoLogin : Int -> DynamoDb model msg -> model -> Cmd msg
dynamoLogin tag database model =
  Cmd.none

dynamoPut : Int -> String -> String -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoPut tag key value database model =
  (model, Cmd.none)

dynamoGet : Int -> String -> DynamoDb model msg -> model -> Cmd msg
dynamoGet tag key database model =
  Cmd.none

dynamoScan : Int -> DynamoDb model msg -> model -> Cmd msg
dynamoScan tag database model =
  Cmd.none

--
-- User-visible database API
--

login : Int -> Database model msg -> model -> Cmd msg
login tag database model =
  case database of
    Simulated simDb ->
      simulatedLogin tag simDb model
    Dynamo dynamoDb ->
      dynamoLogin tag dynamoDb model

put : Int -> String -> String -> Database model msg -> model -> (model, Cmd msg)
put tag key value database model =
  case database of
    Simulated simDb ->
      simulatedPut tag key value simDb model
    Dynamo dynamoDb ->
      dynamoPut tag key value dynamoDb model

get : Int -> String -> Database model msg -> model -> Cmd msg
get tag key database model =
  case database of
    Simulated simDb ->
      simulatedGet tag key simDb model
    Dynamo dynamoDb ->
      dynamoGet tag key dynamoDb model

scan : Int -> Database model msg -> model -> Cmd msg
scan tag database model =
  case database of
    Simulated simDb ->
      simulatedScan tag simDb model
    Dynamo dynamoDb ->
      dynamoScan tag dynamoDb model

--
-- Call this from the command that comes from the DynamoDb port or the simulator
--

otherError : String -> Error
otherError message =
  { errorType = Other
  , message = message
  }

update : Int -> Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
update tag properties database model =
  let wasTag = case getProp "tag" properties of
                 Nothing -> 0
                 Just et -> case String.toInt et of
                              Err s -> 0
                              Ok i -> i
  in
    if tag /= 0 && tag /= wasTag then
      Err { errorType = TagMismatch tag wasTag
          , message = "Tag mismatch, expected: " ++ (toString tag) ++ ", was: " ++ (toString wasTag)
          }
    else
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
                Ok <| dispatcher.login profile model

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
            Ok <| dispatcher.get key value model

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
            Ok <| dispatcher.put key value model

updateScan : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateScan properties database model =
  case getProp "keys" properties of
    Nothing ->
      Err <| otherError "Missing value in get return."
    Just keys ->
      let dispatcher = getDispatcher database
      in
        Ok <| dispatcher.scan (String.split "\\" keys) model
