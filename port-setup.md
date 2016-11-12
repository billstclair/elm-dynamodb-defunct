# Using the DynamoBackend JavaScript

This page is a guide to configuring your Elm application to use the backend JavaScript in this repository's [examples](examples/) directory.

You can develop your application using the DynamoDB simulator, which is part of the DynamoBackend module. First, you'll need to add the module to your application (if you haven't already):

```
cd .../your/application's/directory
elm package install billstclair/elm-dynamodb
```

You can run your simulator-based application in reactor.

```
cd .../your/application's/directory
elm reactor
```

Now you can write your code, and debug it with the simulator. But key/value pairs you save will exist for only one session. As soon as you refresh your browser, or leave the page, they will be gone.

Connecting your application to the persistent Amazon backend is a bit more complicated.

Before doing the rest, you need to follow the instructions in [Configuring Amazon DynamoDB for DynamoBackend](amazon-setup.md). You'll come back with a clientId, tableName, appName, roleArn, and awsRegion from that process.

