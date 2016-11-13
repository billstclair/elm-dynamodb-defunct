# Using the DynamoBackend JavaScript

This page is a guide to configuring your Elm application to use the backend JavaScript in this repository's [examples](examples/) directory.

## Using the simulator

You can develop your application using the DynamoDB simulator, which is part of the DynamoBackend module. First, you'll need to add the module to your application (if you haven't already):

```
cd .../your/application/directory
elm package install billstclair/elm-dynamodb
```

You can run your simulator-based application in reactor.

```
cd .../your/application/directory
elm reactor
```

Now you can write your code, and debug it with the simulator. Key/value pairs you save will exist for only one session. As soon as you refresh your browser, or leave the page, they will be gone.

You'll actually need to implement a lot of what I document below for your simulator-based application, but you won't need the JavaScript code or the ports.

Specific to the simulated backend are an Elm `Dict`, in which to store the key/value pairs, and the creation of the simulated `Database`. From [examples/src/simulated.elm](examples/src/simulated.elm):

```
import Html.App as App

main =
  App.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

profile : DB.Profile
profile =
  DB.Profile "someone@somewhere.net" "John Doe" "random-sequence-1234"

database : Database
database =
  DB.makeSimulatedDb
      profile getDbDict setDbDict backendCmd dispatcher

init : (Model, Cmd Msg)
init =
  sharedInit database
```

`dispatcher` is documented below. `getDbDict` and `setDbDict` are simple accesors for that property of your Model. From `examples/src/SharedUI.elm`:

```
type alias Model =
  { dbDict : DB.StringDict      -- used by the backend simulator
  ...
  }
  
getDbDict = .dbDict

setDbDict : Dict String String -> Model -> Model
setDbDict dict model =
  { model | dbDict = dict }
```

`backendCmd` simply wraps a `Cmd` around a `BackendMsg`:

```
makeMsgCmd = DB.makeMsgCmd

backendCmd : DB.Properties -> Cmd Msg
backendCmd properties =
  makeMsgCmd <| BackendMsg properties

type Msg
  ...
  | BackendMsg DB.Properties
```

The way that wrapper works is simple, but pretty interesting. It's a slightly unusual use of the Elm `Task` (from [src/DynamoBackend.elm](src/DynamoBackend.elm)):

```
makeMsgCmd : msg -> Cmd msg
makeMsgCmd msg =
  Task.perform identity identity (Task.succeed msg)
```

## Using the real DynamoDB backend

Connecting your application to the persistent Amazon backend is a bit more complicated.

Before doing the rest, you need to follow the instructions in [Configuring Amazon DynamoDB for DynamoBackend](amazon-setup.md). You'll come back with a `clientId`, `tableName`, `appName`, `roleArn`, and `awsRegion` from that process. You'll need them below.

## Ports

In order to have ports in your Elm app, to talk to JavaScript code, you need to start your app with `Html.App.programWithFlags`, not `Html.App.program` or `Html.App.beginnerProgram`. The big difference is that your `init` function takes an additional `flags` argument, which is passed in from the JavaScript in your `index.html` file (whatever it is named).

The file [`examples/site/dynamo-example.html`](examples/site/dynamo-example.html) is the top-level HTML file for my examples application, implemented by [`examples/src/real.elm`](examples/src/real.elm) and [`examples/src/SharedUI.elm`](examples/src/SharedUI.elm). Your top-level application will need to include at least what it does, with more if you have your own ports.

The easiest way to start is to copy the [examples/site](examples/site/) directory, and rename `dynamo-example.html` (likely to `index.html`), and probably remove my pretty table CSS file (`css/tables.css`), and `.sshdir`. You'll need the files in the `js` directory. Here's the `<head>` section of `dynamo-example.html`:

```
<head>
<title>DynamoDB via Amazon SDK in the Browser</title>
<link rel='stylesheet' type='text/css' href='css/tables.css' />
<!--<script type='text/javascript' src='https://sdk.amazonaws.com/js/aws-sdk-2.6.12.min.js'></script>-->
<script type='text/javascript' src='js/aws-sdk-2.6.15.min.js'></script>
<!-- dynamo-server-info.js contains information about your Dynamo app.
  -- It must be loaded before dynamodb-backend.js
  -->
<script type='text/javascript' src='js/dynamo-server-info.js'></script>
<script type='text/javascript' src='js/dynamo-backend.js'></script>
<!-- Change Main.js to the file name into which you compile your Elm code. -->
<script type='text/javascript' src='js/Main.js'></script>
</head>
```

You'll probably remove the `<link>` line for `css/tables.css` (unless your app has tables, and you like that look), and you can remove the commented out `<script>` line for `'https://sdk.amazonaws.com/js/aws-sdk-2.6.12.min.js`, which I kept there as a reminder of where the full AWS JavaScript library lives (`js/aws-sdk-2.6.15.min.js` is a subset library, containing only the DynamoDB API, created at [sdk.amazonaws.com/builder/js](https://sdk.amazonaws.com/builder/js/)).

`js/dynamo-server-info.js` doesn't exist yet. You need to rename `js/dynamo-server-info.js.template` to `js/dynamo-server-info.js` and replace the values for `clientId`, `tableName`, `appName`, `roleArn`, and `awsRegion` with the values for your application and table.

`js/Main.js` is the name I gave the "binary" of my Elm code. If you use something else, you'll need to change that to match.

There are a lot of comments, which you can remove, but not a lot more to `dynamo-example.html`:

```
var app = Elm.Main.fullscreen(dynamoServerInfo);

var responsePort = app.ports.dynamoResponse;

// Elm Ports
app.ports.dynamoRequest.subscribe(function(properties) {
  dynamoBackend.dispatch(properties, responsePort);
});

```

There are three names in that code that are important. `Main` is the name of your top-level port module. `dynamoResponse` is the name of your input port, to which your code needs to `subscribe`. `dynamoRequest` is the name of your output port.

These names appear in [examples/src/real.elm](examples/src/real.elm). If you need them to be different for your application, you'll need to change them in the top-level HTML file as well. But they have to appear just as they do in `real.elm`:

```
port module Main exposing (..)

...

port dynamoRequest : DB.Properties -> Cmd msg
port dynamoResponse : (DB.Properties -> msg) -> Sub msg
```

## The Elm Code

As I said earlier, your application needs to start with `Html.App.programWithFlags`:

```
import Html.App as App

main =
  App.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }
```

And the backend will give you a DynamoServerInfo record at startup. You may need to modify this, if you have other ports and need to return other information.

```
import DynamoBackend as DB

...

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

...

subscriptions : Model -> Sub Msg
subscriptions model =
  dynamoResponse BackendMsg

```

That call of `DB.makeDynamoDb` requires a bunch of definitions. `serverInfo` is a parameter to `init`. `dynamoRequest` is defined as a `port`.

`getProperties`, `setProperties`, `BackendMsg`, `dispatcher`, and `sharedInit` are defined in [examples/src/SharedUI.elm](examples/src/SharedUI.elm). Your versions of them will be application-specific, but you need to include the database in your Model. I've removed the application-specific parts of the `SharedUI.elm` Model definition below:

```
type alias Model =
  { database : DbType
  , properties : DB.Properties  -- For DynamoBackend private state
  , profile : Maybe DB.Profile  -- Nothing until logged in
  , error : String
  , loggedInOnce : Bool
  }

mdb : Model -> Database
mdb model =
  case model.database of
    Db res -> res
    
type alias Database =
  DB.Database Model Msg

type DbType
  = Db Database

```

Note that I had to wrap the `DB.Database` with a `type`, to avoid recursive definitions of Model including Database including Model including...


`getProperties` and `setProperties` are simple getter and setter for the `properties` property of your Model record:

```
getProperties = .properties

setProperties : DB.Properties -> Model -> Model
setProperties properties model =
  { model | properties = properties }
```

`BackendMsg` is created in response to input port sends from the JavaScript code. It is also used by the `DynamoBackend` module to send messages to itself.

```
type Msg
  = ...
  | Login
  | Logout
  ...
  | BackendMsg DB.Properties
  ...

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ...
    Login ->
      case model.profile of
        Nothing -> (model, DB.login (mdb model) model)
        Just _ -> (model, Cmd.none)
    Logout ->
      case model.profile of
        Nothing -> (model, Cmd.none)
        Just _ -> (model, DB.logout (mdb model) model)
    ...
    BackendMsg properties ->
      case DB.update properties (mdb model) model of
        Err error ->
          case error.errorType of
            DB.AccessExpired ->
              ( { model | error = "" }
              , makeMsgCmd Login
              )
            _ ->
              ( { model | error = DB.formatError error }
              , Cmd.none
              )
        Ok (model', cmd) ->
          ( { model' | error = "" }
          , cmd
          )
```

Your error handling code will be application-specific, but the call of `DB.update` is key. Invocation of the login code is also important, if you get a `DB.AccessExpired` error. My example just turns other errors into a string that is displayed by the `update` code.

All that's left from the call to `DB.makeDynamoDb` above is the `dispatcher`:

```
dispatcher : DB.ResultDispatcher Model Msg
dispatcher =
  DB.ResultDispatcher
    loginReceiver getReceiver putReceiver scanReceiver logoutReceiver
```

Your code for the individual dispatcher functions will be application-specific, but your `loginReceiver` and `logoutReceiver` will likely be similar to mine:

```
loginReceiver : DB.Profile -> Database -> Model -> (Model, Cmd Msg)
loginReceiver profile database model =
  ( { model |
      profile = Just profile
    , loggedInOnce = True
    }
  , if model.loggedInOnce then
      -- This should retry the command that got the AccessExpired error.
      -- Go ahead. Call me lazy.
      Cmd.none
    else
      DB.scan False profile.userId database model
  )

logoutReceiver : Database -> Model -> (Model, Cmd Msg)
logoutReceiver database model =
  ( { model |
      profile = Nothing
    , key = ""
    , value = ""
    , keys = []
    , valueDict = Dict.empty
    , loggedInOnce = False
    }
  , Cmd.none
  )
```

An Amazon login session lasts for only an hour. There is currently no way to extend that period except to present the user with another login dialog. DynamoBackend helps you to do that, and to retry the last operation after the user logs in again. Here's the code that uses that from [examples/src/SharedUI.elm](examples/src/SharedUI.elm), with the relevant lines marked with asterisk comments:

```
type alias Model =
  { ...
  , retryProperties : Maybe DB.Properties     -- *****
  }
  
loginReceiver profile database model =
  ( { model |
      profile = Just profile
    , loggedInOnce = True
    , retryProperties = Nothing               -- *****
    }
  , if model.loggedInOnce then
      case model.retryProperties of
        Nothing -> Cmd.none
        Just retryProperties ->               -- *****
          DB.retry database retryProperties   -- *****
    else
      DB.scan False profile.userId database model
  )

update msg model =
  case msg of
    ...
    BackendMsg properties ->
      case DB.update properties (mdb model) model of
        Err error ->
          case error.errorType of
            DB.AccessExpired retryProperties ->            -- *****
              ( { model |
                  error = ""
                , profile = Nothing
                , retryProperties = Just retryProperties   -- *****
                }
              , makeMsgCmd Login
              )
        ...
```

## Whew!

Happy hacking!

Now that I've finished the DynamoDB backend, I can add it to MY application, [Kakuro Dojo](https://kakuro-dojo.com/), and more to come.
