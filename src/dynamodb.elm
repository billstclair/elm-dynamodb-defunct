----------------------------------------------------------------------
--
-- dynamodb.elm
-- Example application for talking to Amazon's DynamoDB
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

port module DynamoDB exposing (..)

import UrlParser

import Html exposing (Html, div, h1, text, input, button, a, img)
import Html.Attributes exposing (href, id, alt, src, width, height, style)
import Html.Events exposing (onClick)
import Navigation as App exposing (Location)
import String
import List
import List.Extra as LE
import Time exposing (Time, minute)
import Debug exposing (log)

type alias Properties =
  List (String, String)

-- Bool argument ignored.
-- Must have a div with an id of "amazon-root" before calling.
port installLoginScript : Bool -> Cmd msg

-- (login state) includes the state in the returned Properties to loginResponse
port login : String -> Cmd msg

-- Arrives in response to a login command
port loginResponse : (Properties -> msg) -> Sub msg

-- Writing and reading properties.
port saveProperties : (String, Properties) -> Cmd msg
port requestProperties : String -> Cmd msg
port receiveProperties : (Maybe Properties -> msg) -> Sub msg

main =
  App.programWithFlags
    (App.makeParser locationParser)
    { init = init
    , view = view
    , update = update
    , urlUpdate = urlUpdate
    , subscriptions = subscriptions
    }

-- MODEL

--The browser query string as (key, value) pairs
type alias URLQuery =
  List (String, String)

type alias Model =
  { href : String
  , query : URLQuery
  , location : Location
  , dynamoDbProperties: Properties
  , loginProperties : Properties
  , loginLoaded : Bool
  , nextRenew : Maybe Time
  }

init : Properties -> Location -> (Model, Cmd Msg)
init properties location =
  let (href, query) = UrlParser.parseUrl location.href
  in
      ( { href = href
        , query = query
        , location = location
        , dynamoDbProperties = properties
        , loginProperties = []
        , loginLoaded = False
        , nextRenew = Nothing
        }
      , installLoginScript True
      )

-- UPDATE

type Msg
  = Login
  | LoginResponse Properties
  | PeriodicTask Time

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
      Login ->
        --need to generate, remember, & compare random state
        (model, login "Elm State")
      LoginResponse properties ->
        ( { model | loginProperties = properties }
        , Cmd.none
        )
      PeriodicTask time ->
        periodicTask time model

getProp : String -> Properties -> Maybe String
getProp key properties =
  case LE.find (\a -> key == (fst a)) properties of
    Nothing -> Nothing
    Just (k, v) -> Just v

periodicTask : Time -> Model -> (Model, Cmd msg)
periodicTask time model =
  (model, Cmd.none)

-- URLUPDATE

locationParser : Location -> Location
locationParser a =
  a

urlUpdate : Location -> Model -> (Model, Cmd Msg)
urlUpdate location model =
  ({ model | location = location }, Cmd.none)

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch [ Time.every minute PeriodicTask
            , loginResponse LoginResponse
            ]

-- VIEW

br : Html msg
br = Html.br [][]

view : Model -> Html Msg
view model =
  div []
    [ h1 [] [ text "DynamoDB Example" ]
    , div [ id "amazon-root" ] [] --this id is required by the Amazon JavaScript
    , text "DynamoDB Properties: "
    , text <| toString model.dynamoDbProperties
    , br
    , text "Login Properties: "
    , text <| toString model.loginProperties
    , br
    , text "href: "
    , text <| toString model.href
    , br
    , text "Query: "
    , text <| toString model.query
    , br
    , a [ href "#"
        , id "LoginWithAmazon"
        ]
        [ img
            [ onClick Login
            , style [ ("border", "0") ]
            , alt "Login with Amazon"
            , src "https://images-na.ssl-images-amazon.com/images/G/01/lwa/btnLWA_gold_156x32.png"
            , width 156
            , height 32
            ]
            []
        ]
    ]

{-
<!-- Amazon boilerplate for login page -->
<div id="amazon-root"></div>
<script type="text/javascript">
  window.onAmazonLoginReady = function() {
    amazon.Login.setClientId('amzn1.application-oa2-client.51c688dac8f845818a4003f432d4d520');
  };
  (function(d) {
    var a = d.createElement('script'); a.type = 'text/javascript';
    a.async = true; a.id = 'amazon-login-sdk';
    a.src = 'https://api-cdn.amazon.com/sdk/login1.js';
    d.getElementById('amazon-root').appendChild(a);
  })(document);
</script>

<h2>Test Login Page</h2>

<p>
<a href="#" id="LoginWithAmazon">
  <img border="0" alt="Login with Amazon"
    src="https://images-na.ssl-images-amazon.com/images/G/01/lwa/btnLWA_gold_156x32.png"
    width="156" height="32" />
</a>
</p>

<!-- Amazon boilerplate -->
<script type="text/javascript">
  document.getElementById('LoginWithAmazon').onclick = function() {
    options = { scope : 'profile' };
    amazon.Login.authorize(options, 'https://kakuro-dojo.com/handle_login.php');
    return false;
  };
</script>

<p>
<a href="#" id="Logout">Logout</a>
</p>

<!-- Amazon boilerplate -->
<script type="text/javascript">
  document.getElementById('Logout').onclick = function() {
    amazon.Login.logout();
};
</script>
-}

{-
// handle_login.php
// verify that the access token belongs to us
$c = curl_init('https://api.amazon.com/auth/o2/tokeninfo?access_token=' . urlencode($_REQUEST['access_token']));
curl_setopt($c, CURLOPT_RETURNTRANSFER, true);

$r = curl_exec($c);
curl_close($c);
$d = json_decode($r);

if ($d->aud != 'amzn1.application-oa2-client.51c688dac8f845818a4003f432d4d520') {
  // the access token does not belong to us
  header('HTTP/1.1 404 Not Found');
  echo 'Page not found';
  exit;
}

// exchange the access token for user profile
$c = curl_init('https://api.amazon.com/user/profile');
curl_setopt($c, CURLOPT_HTTPHEADER, array('Authorization: bearer ' . $_REQUEST['access_token']));
curl_setopt($c, CURLOPT_RETURNTRANSFER, true);

$r = curl_exec($c);
curl_close($c);
$d = json_decode($r);

echo sprintf('%s %s %s', $d->name, $d->email, $d->user_id);

-}
