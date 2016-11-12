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

## Using the real DynamoDB backend

Connecting your application to the persistent Amazon backend is a bit more complicated.

Before doing the rest, you need to follow the instructions in [Configuring Amazon DynamoDB for DynamoBackend](amazon-setup.md). You'll come back with a clientId, tableName, appName, roleArn, and awsRegion from that process.

In order to have ports in your Elm app, to talk to JavaScript code, you need to start your app with `Html.App.programWithFlags`, not `Html.App.program` or `Html.App.beginningProgram`. The big difference is that your `init` function takes an additional `flags` argument, which is passed in from the JavaScript in your `index.html` file (whatever it is named).

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

You'll remove the `<link>` line for `css/tables.css`, and you can remove the commented out `<script>` line for `'https://sdk.amazonaws.com/js/aws-sdk-2.6.12.min.js`, which I kept there as a reminder of where the full AWS JavaScript library lives (`js/aws-sdk-2.6.15.min.js` is a subset library, containing only the DynamoDB API, created at [sdk.amazonaws.com/builder/js](https://sdk.amazonaws.com/builder/js/)).
