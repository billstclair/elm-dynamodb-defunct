----------------------------------------------------------------------
--
-- simulated.elm
-- Example appication using simulated Amazon DynamoDB backend.
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

import SharedUI exposing ( Model, Msg(BackendMsg), Database
                         , sharedInit, sharedView, update
                         , backendCmd
                         , getDbDict, setDbDict, dispatcher
                         )
import DynamoBackend as DB

import Html exposing (Html)
import Html.App as App

main =
  App.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

-- MODEL

profile : DB.Profile
profile =
  DB.Profile "someone@somewhere.net" "John Doe" "random-sequence-1234"

database : Database
database =
  DB.makeSimulatedDb
      profile getDbDict setDbDict backendCmd dispatcher

init : (Model, Cmd msg)
init =
  sharedInit database

-- UPDATE
-- All in SharedUI.elm

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none

-- VIEW

view : Model -> Html Msg
view model =
  sharedView "Simulated Backend" model
