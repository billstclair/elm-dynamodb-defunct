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
                              , ErrorType(..), Error, formatError
                              , getProp
                              , DynamoServerInfo , makeDynamoDb, isRealDatabase
                              , makeSimulatedDb
                              , installLoginScript, login
                              , put, remove, get, scan, logout
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
import Json.Encode as JE
import Task

import Debug exposing (log)

type alias Profile =
  { email : String
  , name : String
  , userId : String
  }

type ErrorType
  = FetchProfileError
  | AccessTokenError
  | InternalError
  | ReturnedProfileError
  | Other

errorTypeToString : ErrorType -> String
errorTypeToString errorType =
  case errorType of
    FetchProfileError -> "Fetch profile error"
    AccessTokenError -> "Access token error"
    InternalError -> "Internal error"
    ReturnedProfileError -> "Returned profile error"
    Other -> "Error"

stringToErrorType : String -> ErrorType
stringToErrorType string =
  case string of
    "Fetch profile error" -> FetchProfileError
    "Access token error" -> AccessTokenError
    "Internal error" -> InternalError
    "Returned profile error" -> ReturnedProfileError
    _ -> Other

type alias Error =
  { errorType: ErrorType
  , message : String
  }

formatError : Error -> String
formatError error =
  (errorTypeToString error.errorType) ++ ": " ++ error.message

type alias ResultDispatcher model msg =
  { login : (Profile -> Database model msg -> model -> (model, Cmd msg))
  , get : (String -> Maybe String -> Database model msg -> model -> (model, Cmd msg))
  , put : (String -> Maybe String -> Database model msg -> model -> (model, Cmd msg))
  , scan : (List String -> List String -> Database model msg -> model -> (model, Cmd msg))
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

removeProp : String -> Properties -> Properties
removeProp key properties =
  List.filter (\(k, _) -> k /= key) properties

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
          database.setDict (Dict.insert key value dict) model
    in
      ( model'
      , database.simulatedPort
          [ ("operation", "put")
          , ("key", key)
          , ("value", value)
          ]
      )

simulatedRemove : String -> SimDb model msg -> model -> (model, Cmd msg)
simulatedRemove key database model =
    let dict = database.getDict model
        model' = database.setDict (Dict.remove key dict) model
    in
      ( model'
      , database.simulatedPort
          [ ("operation", "remove")
          , ("key", key)
          ]
      )

simulatedGet : String -> SimDb model msg -> model -> Cmd msg
simulatedGet key database model =
  let dict = database.getDict model
      res = case Dict.get key dict of
                Nothing ->
                    [ ("operation", "get")
                    , ("key", key)
                    ]
                Just value ->
                    [ ("operation", "get")
                    , ("key", key)
                    , ("value", value)
                    ]
  in
    database.simulatedPort res

simulatedScan : Bool -> SimDb model msg -> model -> Cmd msg
simulatedScan fetchValues database model =
  let dict = database.getDict model
      keys = List.map (\key -> ("", key)) (Dict.keys dict)
      values = if fetchValues then
                 List.map (\key -> ("_", key)) (Dict.values dict)
               else
                 []
  in
    database.simulatedPort
      <| setProp "operation" "scan"
      <| List.append keys values

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
  Cmd.batch
    [ database.backendPort
        [ ("operation", "installLoginScript") ]
    , localGetAccessToken database
    ]

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

fetchProfileError : DynamoDb model msg -> model -> Http.Error -> msg
fetchProfileError database model error =
  let msg = case error of
              Http.Timeout -> "timeout"
              Http.NetworkError -> "network error"
              Http.UnexpectedPayload json ->
                "Unexpected Payload: " ++ json
              Http.BadResponse code err ->
                "Bad Response: " ++ (toString code) ++ err
      modelProps = database.getProperties model
  in
    case getProp "expectedState" modelProps of
      Nothing ->
        -- Ignore errors for attempted use of previously saved access tokens.
        database.backendMsg [("operation", "nop")]
      Just _ ->
        database.backendMsg
          [ ("error" , msg)
          , ("type", errorTypeToString FetchProfileError)
          ]
  
profileReceived : DynamoDb model msg -> Properties -> msg
profileReceived database properties =
  database.backendMsg
    <| setProp "operation" "login" properties

getAmazonUserProfile : String -> DynamoDb model msg -> model -> Cmd msg
getAmazonUserProfile accessToken database model =
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
        (fetchProfileError database model) (profileReceived database) decoded

jePair : (String, String) -> JE.Value
jePair pair =
  let (name, value) = pair
  in
    JE.list [(JE.string name), (JE.string value)]

jeProperties : Properties -> JE.Value
jeProperties properties =
  JE.list <| List.map jePair properties

localPutAccessToken : Properties -> DynamoDb model msg -> Cmd msg
localPutAccessToken properties database =
  let json = JE.encode 0 <| jeProperties properties
      props = [ ("operation", "localPut")
              , ("key", "accessToken")
              , ("value", json)
              ]
  in
    database.backendPort props

localGetAccessToken : DynamoDb model msg -> Cmd msg
localGetAccessToken database =
  database.backendPort
    [ ("operation", "localGet")
    , ("key", "accessToken")
    ]

jdPair : JD.Decoder (String, String)
jdPair = JD.tuple2 (,) JD.string JD.string
  
jdProperties: JD.Decoder (Properties)
jdProperties = JD.list jdPair

-- Here on receiving the saved access token properties from localStorage
accessTokenReceiver : String -> DynamoDb model msg -> model -> (model, Cmd msg)
accessTokenReceiver json database model =
  case JD.decodeString jdProperties json of
    Err msg -> (model, Cmd.none)
    Ok properties ->
      case getProp "access_token" properties of
        Nothing -> (model, Cmd.none)
        Just accessToken ->
          let modelProps = database.getProperties model
          in
            (database.setProperties
               (mergeProps properties modelProps) model
            , Cmd.batch
                [ getAmazonUserProfile accessToken database model
                , database.backendPort
                    [ ("operation", "setAccessToken")
                    , ("accessToken", accessToken)
                    ]
                ]
            )

-- Got an access token from the login code
-- Need to look up the Profile
dynamoAccessToken : Properties -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoAccessToken properties database model =
  let modelProps = database.getProperties model
      errorType = errorTypeToString AccessTokenError
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
          <| database.backendMsg [ ("error", err)
                                 , ("type", errorType)
                                 ]
      )
    else
      case getProp "access_token" properties of
        Nothing ->
          ( model
          , makeMsgCmd
              <| database.backendMsg
                   [ ("error", "No access token returned from login.")
                   , ("type", errorType)
                   ]
          )
        Just accessToken ->
            (database.setProperties
               (mergeProps properties modelProps) model
            , Cmd.batch [ localPutAccessToken properties database
                        , getAmazonUserProfile accessToken database model
                        ]
            )

dynamoPut : String -> String -> String -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoPut userId key value database model =
  ( model
  , database.backendPort
      [ ("operation", "put")
      , ("user", userId)
      , ("key", key)
      , ("value", value)
      ]
  )

dynamoRemove : String -> String -> DynamoDb model msg -> model -> (model, Cmd msg)
dynamoRemove userId key database model =
  ( model
  , database.backendPort
      [ ("operation", "remove")
      , ("user", userId)
      , ("key", key)
      ]
  )

dynamoGet : String -> String -> DynamoDb model msg -> model -> Cmd msg
dynamoGet userId key database model =
  database.backendPort
    [ ("operation", "get")
    , ("user", userId)
    , ("key", key)
    ]

dynamoScan : Bool -> String -> DynamoDb model msg -> model -> Cmd msg
dynamoScan fetchValues userid database model =
  database.backendPort
    [ ("operation", "scan")
    , ("user", userid)
    , ("fetchValues", if fetchValues then "true" else "false")
    ]

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

put : String -> String -> String -> Database model msg -> model -> (model, Cmd msg)
put userId key value database model =
  case database of
    Simulated simDb ->
      simulatedPut key value simDb model
    Dynamo dynamoDb ->
      dynamoPut userId key value dynamoDb model

remove : String -> String -> Database model msg -> model -> (model, Cmd msg)
remove userId key database model =
  case database of
    Simulated simDb ->
      simulatedRemove key simDb model
    Dynamo dynamoDb ->
      dynamoRemove userId key dynamoDb model

get : String -> String -> Database model msg -> model -> Cmd msg
get userId key database model =
  case database of
    Simulated simDb ->
      simulatedGet key simDb model
    Dynamo dynamoDb ->
      dynamoGet userId key dynamoDb model

scan : Bool -> String -> Database model msg -> model -> Cmd msg
scan fetchValues userid database model =
  case database of
    Simulated simDb ->
      simulatedScan fetchValues simDb model
    Dynamo dynamoDb ->
      dynamoScan fetchValues userid dynamoDb model

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

errorFromProperties : String -> Properties -> Error
errorFromProperties message properties =
  let errorType = case getProp "type" properties of
                    Nothing -> Other
                    Just string -> stringToErrorType string
  in
    Error errorType message

update : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
update properties database model =
  case getProp "error" properties of
    Just err ->
      -- This needs more fleshing out
      Err <| errorFromProperties err properties
    Nothing ->
      let operation = case getProp "operation" properties of
                        Nothing -> "missing"
                        Just op -> op
      in
        case operation of
          "nop" ->
            Ok (model, Cmd.none)
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
          "remove" ->
            updatePut (removeProp "value" properties) database model
          "scan" ->
            updateScan properties database model
          "logout" ->
            updateLogout properties database model
          "localGet" ->
            updateLocalGet properties database model
          "missing" ->
            Err <| Error InternalError "Missing operation in properties."
          _ ->
            Err  <| Error InternalError ("Unknown operation: " ++ operation)
            
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
      Err <| Error ReturnedProfileError "Missing email in login return."
    Just email ->
      case getProp "name" properties of
        Nothing ->
          Err <| Error ReturnedProfileError "Missing name in login return."
        Just name ->
          case getProp "user_id" properties of
            Nothing ->
              Err <| Error ReturnedProfileError "Missing userId in login return."
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
      Err <| Error InternalError "Missing key in get return."
    Just key ->
      let value = getProp "value" properties
          dispatcher = getDispatcher database
      in
          Ok <| dispatcher.get key value database model

updatePut : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updatePut properties database model =
  case getProp "key" properties of
    Nothing ->
      Err <| Error InternalError "Missing key in put return."
    Just key ->
      let dispatcher = getDispatcher database
          maybeValue = getProp "value" properties
      in
          Ok <| dispatcher.put key maybeValue database model

updateScan : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateScan properties database model =
  let keys = List.map snd (List.filter (\prop -> (fst prop) == "") properties)
      values = List.map snd (List.filter (\prop -> (fst prop) == "_") properties)
      dispatcher = getDispatcher database
  in
    Ok <| dispatcher.scan keys values database model

updateLogout : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateLogout properties database model =
  let dispatcher = getDispatcher database
  in
    Ok <| dispatcher.logout database model

updateLocalGet : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
updateLocalGet properties database model =
  case getProp "key" properties of
    Nothing ->
      Err <| Error InternalError "Missing key in localGet return."
    Just key ->
      if key == "accessToken" then
        case getProp "value" properties of
          Nothing ->
            Ok (model, Cmd.none)
          Just value ->
            case database of
              Simulated _ ->
                Ok (model, Cmd.none)
              Dynamo dynamoDb ->
                Ok <| accessTokenReceiver value dynamoDb model
      else
        -- Eventually support user localStore lookups here
        Ok (model, Cmd.none)
