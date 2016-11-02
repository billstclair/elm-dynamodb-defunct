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

module DynamoBackend exposing (..)

import Dict exposing (Dict)
import Result exposing (Result)
import Task

type alias Profile =
  { email : String
  , name : String
  , userId : String
  }

type ErrorType
  = Timeout
  | LoginExpired
  | Other String

type alias Error =
  { errorType: ErrorType
  , message : String
  }

type alias TaggedValue value =
  (Int, value)

type alias TaggedString =
  (Int, String)

type alias TaggedProfile =
  (Int, Profile)

type alias LoginResult =
  Result Error TaggedProfile

type alias GetResult =
  Result Error TaggedString

type alias ScanResult =
  Result Error (Int, List String)

type alias ResultDispatcher model =
  { login : (TaggedProfile -> model -> model)
  , get : (GetResult -> model -> model)
  , put : (GetResult -> model -> model)
  , scan : (ScanResult -> model -> model)
  }

makeResultDispatcher : (TaggedProfile -> model -> model) -> (GetResult -> model -> model) -> (GetResult -> model -> model) -> (ScanResult -> model -> model) -> ResultDispatcher model
makeResultDispatcher login get put scan =
  { login = login
  , get = get
  , put = put
  , scan = scan
  }

type alias Properties =
  List (String, String)

type alias DynamoDatabase model msg =
  { clientId : String
  , tableName : String
  , appName : String
  , roleArn : String
  , awsRegion : String
  , backendPort : (Int -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model
  }

makeDynamoDatabase : String -> String -> String -> String -> String -> (Int -> Properties -> Cmd msg) -> (ResultDispatcher model) -> DynamoDatabase model msg
makeDynamoDatabase clientId tableName appName roleArn awsRegion backendPort dispatcher =
  { clientId = clientId
  , tableName = tableName
  , appName = appName
  , roleArn = roleArn
  , awsRegion = awsRegion
  , backendPort = backendPort
  , dispatcher = dispatcher
  }

type alias StringDict =
  Dict String String

type alias SimulatedDatabase model msg =
  { getDict : (model -> StringDict)
  , setDict : (StringDict -> model -> model)
  , simulatedPort : (Int -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher model
  }

makeSimulatedDatabase : (model -> StringDict) -> (StringDict -> model -> model) -> (Int -> Properties -> Cmd msg) -> ResultDispatcher model -> SimulatedDatabase model msg
makeSimulatedDatabase getDict setDict simulatedPort dispatcher =
  { getDict = getDict
  , setDict = setDict
  , simulatedPort = simulatedPort
  , dispatcher = dispatcher
  }

type alias Database model msg =
  { dynamoDatabase : Maybe (DynamoDatabase model msg)
  , simulatedDatabase : Maybe (SimulatedDatabase model msg)
  }

makeDatabase : Maybe (DynamoDatabase model msg) -> Maybe (SimulatedDatabase model msg) -> Database model msg
makeDatabase dynamoDatabase simulatedDatabase =
  { dynamoDatabase = dynamoDatabase
  , simulatedDatabase = simulatedDatabase
  }

login : Int -> Database model msg -> Cmd msg
login tag database =
  Cmd.none

put : Int -> String -> String -> Database model msg -> Cmd msg
put tag key value database =
  Cmd.none

get : Int -> String -> Database model msg -> Cmd msg
get tag key database =
  Cmd.none

scan : Int -> Database model msg -> Cmd msg
scan tag database =
  Cmd.none
