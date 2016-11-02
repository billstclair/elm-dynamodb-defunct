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

type alias TaggedValue tag value =
  (tag, value)

type alias TaggedString tag =
  (tag, String)

type alias TaggedProfile tag =
  (tag, Profile)

type alias LoginResult tag =
  Result Error (TaggedProfile tag)

type alias GetResult tag =
  Result Error (TaggedString tag)

type alias TagResult tag =
  Result Error tag

type alias ScanResult tag =
  Result Error (tag, List String)

type alias ResultDispatcher tag model =
  { login : (TaggedProfile tag -> model -> model)
  , get : (GetResult tag -> model -> model)
  , put : (GetResult tag -> model -> model)
  , scan : (ScanResult tag -> model -> model)
  }

makeResultDispatcher : (TaggedProfile tag -> model -> model) -> (GetResult tag -> model -> model) -> (GetResult tag -> model -> model) -> (ScanResult tag -> model -> model) -> ResultDispatcher tag model
makeResultDispatcher login get put scan =
  { login = login
  , get = get
  , put = put
  , scan = scan
  }

type alias Properties =
  List (String, String)

type alias DynamoDatabase tag model msg =
  { clientId : String
  , tableName : String
  , appName : String
  , roleArn : String
  , awsRegion : String
  , backendPort : (tag -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher tag model
  }

makeDynamoDatabase : String -> String -> String -> String -> String -> (tag -> Properties -> Cmd msg) -> (ResultDispatcher tag model) -> DynamoDatabase tag model msg
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

type alias SimulatedDatabase tag model msg =
  { getDict : (model -> StringDict)
  , setDict : (StringDict -> model -> model)
  , simulatedPort : (tag -> Properties -> Cmd msg)
  , dispatcher : ResultDispatcher tag model
  }

makeSimulatedDatabase : (model -> StringDict) -> (StringDict -> model -> model) -> (tag -> Properties -> Cmd msg) -> ResultDispatcher tag model -> SimulatedDatabase tag model msg
makeSimulatedDatabase getDict setDict simulatedPort dispatcher =
  { getDict = getDict
  , setDict = setDict
  , simulatedPort = simulatedPort
  , dispatcher = dispatcher
  }

type alias Database tag model msg =
  { dynamoDatabase : Maybe (DynamoDatabase tag model msg)
  , simulatedDatabase : Maybe (SimulatedDatabase tag model msg)
  }

makeDatabase : Maybe (DynamoDatabase tag model msg) -> Maybe (SimulatedDatabase tag model msg) -> Database tag model msg
makeDatabase dynamoDatabase simulatedDatabase =
  { dynamoDatabase = dynamoDatabase
  , simulatedDatabase = simulatedDatabase
  }

login : tag -> Database tag model msg -> Cmd msg
login tag database =
  Cmd.none

put : tag -> key -> value -> Database tag model msg -> Cmd msg
put tag key value database =
  Cmd.none

get : tag -> key -> Database tag model msg -> Cmd msg
get tag key database =
  Cmd.none

scan : tag -> Database tag model msg -> Cmd msg
scan tag database =
  Cmd.none
