----------------------------------------------------------------------
--
-- ExampleModel.elm
-- Move Model & Msg to a separate file to work around an Elm compiler bug
-- (the xxxReceiver functions weren't all defined on creating the database,
-- so those are here, and the database creation is in the top-level files).
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module ExampleModel exposing (..)

import DynamoBackend as DB

import Dict exposing (Dict)
import Task
import Debug exposing (log)

type alias Model =
  { dbDict : DB.StringDict      -- used by the backend simulator
  , profile : Maybe DB.Profile  -- Nothing until logged in
  , keys : List String          -- keys returned by DB.scan
  , valueDict : DB.StringDict   -- used by this code to cache key/value pairs
  , key : String                -- displayed key input
  , value : String              -- displayed value input
  , error : String
  }
  
type Msg
  = UpdateKey String
  | UpdateValue String
  | Login
  | Logout
  | Get
  | Put
  | BackendMsg Int DB.Properties
  | Nop

profile : DB.Profile
profile =
  DB.Profile "someone@somewhere.net" "John Doe" "random-sequence-1234"

loginReceiver : DB.Profile -> DB.Database Model Msg -> Model -> (Model, Cmd Msg)
loginReceiver profile database model =
  ( { model | profile = Just profile }
  , DB.scan 0 database model
  )

getReceiver : String -> String -> DB.Database Model Msg -> Model -> (Model, Cmd Msg)
getReceiver key value database model =
  ( { model |
      value = value
    , valueDict = Dict.insert key value model.valueDict
    }
  , Cmd.none
  )

putReceiver : String -> String -> DB.Database Model Msg -> Model -> (Model, Cmd Msg)
putReceiver key value database model =
  ( { model | valueDict = Dict.insert key value model.valueDict }
  , Cmd.none
  )

scanReceiver : List String -> DB.Database Model Msg -> Model -> (Model, Cmd Msg)
scanReceiver keys database model =
  ( { model |
      keys = keys
    , valueDict = Dict.empty
    }
  , Cmd.none
  )

logoutReceiver : DB.Database Model Msg -> Model -> (Model, Cmd Msg)
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

backendCmd : Int -> DB.Properties -> Cmd Msg
backendCmd tag properties =
  Task.perform
    (\x -> Nop)
    (\x -> BackendMsg tag properties)
    (Task.succeed 1)

setDbDict : Dict String String -> Model -> Model
setDbDict dict model =
  { model | dbDict = dict }

