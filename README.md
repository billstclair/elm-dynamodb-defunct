# billstclair/elm-dynamodb

Elm Interface to [Amazon DynamoDB](https://aws.amazon.com/dynamodb/).

You can run your code against a pure Elm simulator during development, and then change the initial value of the "database" parameter to switch to the real Amazon backend.

[examples/simulated.elm](examples/simulated.elm) is an example application that uses the simulator. It works in `elm-reactor`.

[examples/real.elm](examples/real.elm) is an example application that uses the real backend. It is live at [kakuro-dojo.com/dynamo-example.html](https://kakuro-dojo.com/dynamo-example.html).

Both are tiny wrappers around [examples/SharedUI.elm](examples/SharedUI.elm).

The library itself is in [src/DynamoBackend.elm](src/DynamoBackend.elm).

It takes a little configuration to make the real backend ports work on your own site with your own DynamoDB table. I haven't documented that yet.

Bill St. Clair &lt;billstclair@gmail.com&gt;<br/>
6 November 2016
