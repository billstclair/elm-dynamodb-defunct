----------------------------------------------------------------------
--
-- real.elm
-- Example application for DynamoBackend
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

port module Main exposing (..)

import SharedUI exposing ( Model, Msg(BackendMsg)
                         , makeMsgCmd
                         , getProperties, setProperties
                         , sharedInit, sharedView, update
                         , dispatcher
                         )
import DynamoBackend as DB

import Html exposing (Html)
import Html.App as App

main =
  App.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

port dynamoRequest : DB.Properties -> Cmd msg
port dynamoResponse : (DB.Properties -> msg) -> Sub msg

-- MODEL

init : DB.DynamoServerInfo -> (Model, Cmd Msg)
init serverInfo =
  let database = DB.makeDynamoDb
                   serverInfo getProperties setProperties
                   dynamoRequest BackendMsg dispatcher
  in
    let (model, cmd) = sharedInit database
    in
      ( model
      , Cmd.batch [ cmd, DB.installLoginScript database model ]
      )

-- UPDATE
-- All in SharedUI.elm

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  dynamoResponse BackendMsg

-- VIEW

view : Model -> Html Msg
view model =
  sharedView "Real DynamoDb Backend" model
