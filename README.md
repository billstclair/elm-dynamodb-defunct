# billstclair/elm-dynamodb

Elm Interface to [Amazon DynamoDB](https://aws.amazon.com/dynamodb/).

To compile `src/dynamodb.elm` into `site/dynamodb.js`, required by `site/login.html`:

```
.bin/build-site
```

Then aim your browser at `site/login.html`.

Live at https://kakuro-dojo.com/login.html

See the [`examples`](examples/) directory for examples of use, instructions for setting up the ports necessary to communicate with Amazon's servers, and instructions for how to create your DynamoDB backend table and to give your Elm apps permission to use it.

Bill St. Clair &lt;billstclair@gmail.com&gt;<br/>
3 November 2016
