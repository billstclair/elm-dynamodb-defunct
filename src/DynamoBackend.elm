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
                              , Database, SimDb, DynamoDb, ResultDispatcher
                              , ErrorType(..), Error, formatError
                              , getProp, setProp, removeProp, mergeProps
                              , DynamoServerInfo , makeDynamoDb, isRealDatabase
                              , makeSimulatedDb, makeMsgCmd
                              , installLoginScript, login
                              , put, remove, get, scan, logout
                              , update
                              )

{-| This module provides an Elm backend to Amazon's DynamoDB.

By itself, in pure Elm, you can only access a simulation of the Dynamo
database, with key/value pairs that persist only for the current
session. The README for the GitHub archive tells how to hook up the
JavaScript via ports to your application, and how to configure
DynamoDB via Amazon's Web Services console for use with
`DynamoBackend`.

There is a simple example that clearly illustrates the difference
between the pure-Elm simulator and the real Amazon backend.

`DynamoBackend` targets a single DynamoDB table with three
attributes. It enables use of that table by multiple Amazon accounts,
with each account's data insulated from the others. It also allows
multiple different applications to store their data in that one
backend table, without interference.

The data store is a simple key/value store, mapping a string key to
string data. I expect that one common use will be to JSON encode
state, and store it by key. I built it to do that for my application.

The one drawback of Amazon's authentication mechanism that I was not
able to work around is that a login session lasts only one hour. Each
hour, your users will have to click on the "OK" button in the login
dialog, to renew the session. I consider this to be a bug on Amazon's
part.

# Classes
@docs Profile, Properties, StringDict, DynamoServerInfo, ResultDispatcher
@docs Database, SimDb, DynamoDb
@docs ErrorType, Error

# Functions
@docs formatError, getProp, setProp, removeProp, mergeProps
@docs makeDynamoDb, makeSimulatedDb, isRealDatabase, makeMsgCmd
@docs installLoginScript, login, put, remove, get, scan, logout, update

-}

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

{-| The application-level result of a successful login -}
type alias Profile =
  { email : String
  , name : String
  , userId : String
  }

{-| Errors that can be returned in the errorType property of an Error
record.

`AccessExpired` - Happens when your Amazon login session expires. Your
application needs to call `DynamoBackend.login` again to establish a new
session.

`FetchProfileError` - denotes a problem in turning an access token into a
profile.

`AccessTokenError` - Either Amazon didn't return the state arg when
logging in, or a cross-site forgery made the state sent not match the
state received.

`InternalError` - denotes a bug in the `DynamoBackend` code. Shouldn't
happen.

`ReturnedProfileError` - Means that Amazon's return for profile lookup
was missing the email, name, or userId.

`AwsError` - An error was returned by the Amazon AWS JavaScript
library. Usually denotes a network problem.

`Other` - Shouldn't happen. Means that that the backend code neglected
to tag an error with a "type".

-}

type ErrorType
  = FetchProfileError
  | AccessTokenError
  | InternalError
  | ReturnedProfileError
  | AccessExpired
  | AwsError String String Bool -- operation, code, retryable
  | Other

errorTypeToString : ErrorType -> String
errorTypeToString errorType =
  case errorType of
    FetchProfileError -> "Fetch profile error"
    AccessTokenError -> "Access token error"
    InternalError -> "Internal error"
    ReturnedProfileError -> "Returned profile error"
    AccessExpired -> "Access expired"
    AwsError _ _ _ -> "AWS error"
    Other -> "Error"

stringToErrorType : String -> ErrorType
stringToErrorType string =
  case string of
    "Fetch profile error" -> FetchProfileError
    "Access token error" -> AccessTokenError
    "Internal error" -> InternalError
    "Returned profile error" -> ReturnedProfileError
    "Access expired" -> AccessExpired
    "AWS error" -> AwsError "" "" False
    _ -> Other

{-| DynamoBackend.update returns errors in an `Error` record. -}
type alias Error =
  { errorType: ErrorType
  , message : String
  }

{-| Format an `Error` record as a string -}
formatError : Error -> String
formatError error =
  case error.errorType of
    AwsError operation code retryable ->
      "AWS error, operation: " ++ operation ++ ", code: " ++ code ++
        ", retryable: " ++ (if retryable then "true" else "false") ++
        ", message: " ++ error.message
    errorType ->
      (errorTypeToString errorType) ++ ": " ++ error.message

{-| When results return from the backend, they are passed to one of
these functions that you provide.

`DynamoBackend.login` gives results to the `ResultDispatcher.login`
function.

`DynamoBackend.get` gives results to the `ResultDispatcher.get`
function.

`DynamoBackend.put` and `DynamoBackend.remove` give results to the
`ResultDispatcher.put` function.

`DynamoBackend.scan` gives results to the `ResultDispatcher.scan`
function.

`DynamoBackend.logout` results to the `ResultDispatcher.logout`
function.
-}

type alias ResultDispatcher model msg =
  { login : (Profile -> Database model msg -> model -> (model, Cmd msg))
  , get : (String -> Maybe String -> Database model msg -> model -> (model, Cmd msg))
  , put : (String -> Maybe String -> Database model msg -> model -> (model, Cmd msg))
  , scan : (List String -> List String -> Database model msg -> model -> (model, Cmd msg))
  , logout : (Database model msg -> model -> (model, Cmd msg))
  }

{-| The communication through the ports to the backend JavaScript
happens with `Properties` lists, lists of string pairs.
-}
type alias Properties =
  List (String, String)

{-| Lookup a key in a `Properties` list. Return `Nothing` if its not
there, or `Just value` if it is.
-}
getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

{-| Set the value for a key to a value in a `Properties` list.

`setProp key value properties`
-}
setProp : String -> String -> Properties -> Properties
setProp key value properties =
  (key, value) :: (List.filter (\(k, _) -> k /= key) properties)

{-| Remove the property for a key from a `Properties` list. -}
removeProp : String -> Properties -> Properties
removeProp key properties =
  List.filter (\(k, _) -> k /= key) properties

{-| Merge two `Properties` lists.

If both contain a value for the same key, use the value from the first
list (`from`).

`mergeProps from to`
-}
mergeProps : Properties -> Properties -> Properties
mergeProps from to =
  List.foldr
    (\pair props -> setProp (fst pair) (snd pair) props)
    to from

{-| This record is sent to Elm as the "flags" argument from the
startup code. It is stored internally by the JavaScript backend code,
and isn't used by any of the Elm code, except that you store it in
your Dynamo database. Can be useful for debugging (though I'm tempted
to leave it solely in the JavaScript code).

The properties are setup in Amazon's AWS Console for DynamoDB, and are
stored in a JavaScript file that you create.

This is not secret information. It simply identifies your application
and the table you use to store your key/value pairs.
-}
type alias DynamoServerInfo =
  { clientId : String
  , tableName : String
  , appName : String
  , roleArn : String
  , providerId: String
  , awsRegion : String
  }

{-| Properties for a real `Dynamo` backend `Database`.

`serverInfo` - The ServerInfo record sent in as the startup "flags" from
the JavaScript.

`getProperties` - Your Model must contain a `Properties` list that the
`DynamoBackend` code can use to store state. This function extracts that
list from your `Model`.

`setProperties` - Set the `Properties` list in your `Model`.

`backendPort` - your outgoing backend `port` to the JavaScript code.

`backendMsg` - Create a message as if it came from the incoming backend
port to the JavaScript code.

`dispatcher` - The record of functions to call for return data from the
backend JavaScript.
-}
type alias DynamoDb model msg =
  { serverInfo : DynamoServerInfo
  , getProperties : (model -> Properties)
  , setProperties : (Properties -> model -> model)
  , backendPort : Properties -> Cmd msg
  , backendMsg : Properties -> msg
  , dispatcher : ResultDispatcher model msg
  }

{-| An Elm `Dict` mapping `String` keys to `String` values.

You need to provide one of these in your Model for the simulated
backend.
-}
type alias StringDict =
  Dict String String

{-| Properties for a simulated backend `Database`.

`profile` - A fake login `Profile`.

`getDict` - Return from your `Model` an Elm `Dict` in which the
simulator can store its key/value pairs.

`setDict` - Set the dictionary in your `Model`.

`simulatedPort` - This simulates the return port from the real
backend. `DynamoBackend.makeMsgCmd` is often useful for turning one of
your messages into a `Cmd`.

`dispatcher` - The `ResultDispatcher` that will handle the values returned
through the `simulatedPort`.
-}
type alias SimDb model msg =
  { profile: Profile
  , getDict : (model -> StringDict)
  , setDict : (StringDict -> model -> model)
  , simulatedPort : (Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model msg
  }

{-| The generic type for a `Simulated` or `Dynamo` database -}
type Database model msg
  = Simulated (SimDb model msg)
  | Dynamo (DynamoDb model msg)

{-| Create a real `Dynamo` backend `Database`.

The arguments become the properties of the returned (wrapped) `DynamoDb` record.
-}
makeDynamoDb : DynamoServerInfo -> (model -> Properties) ->
  (Properties -> model -> model) -> (Properties -> Cmd msg) ->
  (Properties -> msg) -> ResultDispatcher model msg -> Database model msg
makeDynamoDb
  serverInfo getProperties setProperties backendPort backendMsg dispatcher =
    Dynamo <|
      DynamoDb
        serverInfo getProperties setProperties backendPort backendMsg dispatcher

{-| Create a simulated backend `Database`.

The arguments become the properties of the returned (wrapped) `SimDb` record.
-}
makeSimulatedDb : Profile -> (model -> StringDict) -> (StringDict ->
  model -> model) -> (Properties -> Cmd msg) -> ResultDispatcher model
  msg -> Database model msg

makeSimulatedDb profile getDict setDict simulatedPort dispatcher =
  Simulated <|
    SimDb profile getDict setDict simulatedPort dispatcher

{-| Return `True` if the argument is a real datbase (the result of
calling `makeDynamoDb`) or `False` if it is simulated (from
`makeSimulatedDb`).
-}
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

{-| Wrap a message as a `Cmd`. -}
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

{-| The Amazon login code attaches a script to the `<div>` with an id of
`"amazon-root"`. Your view code needs to create that `<div>`. Call this
when your application starts to attach the login script. It will
auto-login if a recent session in the same browser has not yet
expired.
-}
installLoginScript : Database model msg -> model -> Cmd msg
installLoginScript database model =
  case database of
    Simulated simDb ->
      simulatedInstallLoginScript simDb model
    Dynamo dynamoDb ->
      dynamoInstallLoginScript dynamoDb model

{-| Call this when the user clicks on your "login" button, or
when you get an `AccessExpired` error.
-}
login : Database model msg -> model -> Cmd msg
login database model =
  case database of
    Simulated simDb ->
      simulatedLogin simDb model
    Dynamo dynamoDb ->
      dynamoLogin dynamoDb model

{-| Call this to store a key/value pair in the database. 
The `userId` comes from the `Profile` record.

`put userId key value database`
-}
put : String -> String -> String -> Database model msg -> model -> (model, Cmd msg)
put userId key value database model =
  case database of
    Simulated simDb ->
      simulatedPut key value simDb model
    Dynamo dynamoDb ->
      dynamoPut userId key value dynamoDb model

{-| Call this to remove a key/value pair from the database.
The `userId` comes from the `Profile` record.

`remove userId key database`
-}
remove : String -> String -> Database model msg -> model -> (model, Cmd msg)
remove userId key database model =
  case database of
    Simulated simDb ->
      simulatedRemove key simDb model
    Dynamo dynamoDb ->
      dynamoRemove userId key dynamoDb model

{-| Call this to get the value for a key from the database.
The `userId` comes from the `Profile` record.

`get userId key database`
-}
get : String -> String -> Database model msg -> model -> Cmd msg
get userId key database model =
  case database of
    Simulated simDb ->
      simulatedGet key simDb model
    Dynamo dynamoDb ->
      dynamoGet userId key dynamoDb model

{-| Call this to scan the database for all keys. If `fetchValues` is
`True`, will also return values.

The `userId` comes from the `Profile` record.

`scan fetchValues userId database`
-}
scan : Bool -> String -> Database model msg -> model -> Cmd msg
scan fetchValues userid database model =
  case database of
    Simulated simDb ->
      simulatedScan fetchValues simDb model
    Dynamo dynamoDb ->
      dynamoScan fetchValues userid dynamoDb model

{-| Call this to logout from Amazon.
Clears all state the could be used to create a session.
-}
logout : Database model msg -> model -> Cmd msg
logout database model =
  case database of
    Simulated simDb ->
      simulatedLogout simDb model
    Dynamo dynamoDb ->
      dynamoLogout dynamoDb model

errorFromProperties : String -> Properties -> Error
errorFromProperties message properties =
  let errorType = case getProp "type" properties of
                    Nothing -> Other
                    Just string -> stringToErrorType string
  in
    case errorType of
      AwsError _ _ _ ->
        let operation = case getProp "operation" properties of
                          Nothing -> ""
                          Just op -> op
            code = case getProp "code" properties of
                     Nothing -> ""
                     Just cd -> cd
            retryable = case getProp "retryable" properties of
                          Just "true" -> True
                          _ -> False
        in
          if code == "CredentialsError" then
            Error AccessExpired message
          else
            Error (AwsError operation code retryable) message
      _ ->
        Error errorType message

{-| This handles the `Properties` that are sent back from the backend
JavaScript (real or simulated). Your application needs to map that
command to a message, and handle that message by calling
`DynamoBackend.update`, and then process the resulting `Err` or `Ok`
value. Before returning, it will usually call one of the functions in
the database's `ResultSetDispatcher`.
-}
update : Properties -> Database model msg -> model -> Result Error (model, Cmd msg)
update properties database model =
  case getProp "error" properties of
    Just err ->
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
