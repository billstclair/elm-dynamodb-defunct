# Amazon DynamoDB Backend Example Applications

This directory contains examples of using the `DynamoBackend` module.

The simulated backend is pure Elm. To run it:

```
cd .../elm-dynamodb/examples
elm reactor
```

Then aim your browser at http://localhost:8000/src/simulated.elm.

`simulated.elm` is also live at [kakuro-dojo.com/simulated.html](https://kakuro-dojo.com/simulated.html).

The real backend, using a table in my Amazon AWS account, is live at [kakuro-dojo.com/dynamo-example.html](https://kakuro-dojo.com/dynamo-example.html).

I'll write documentation soon about how to set up your own DynamoDB table and to configure your application to use the ports to [js/dynamo-backend.js](js/dynamo-backend.js).

## <a name="use">How to use the interface</a>

The real and simulated backend examples share most of their code, with the only differences being the `h2` header, the login button appearance, and the database, real or simulated.

First, click the "Login" button. This will just login with simulated credentials in the simulated example. It will pop up an Amazon login window in the real example, and you'll need to log in to your Amazon account.

Your account name and email are displayed, and a Logout button.

Use the "Key" and "Value" fields plus the "Put" button to enter new key/value pairs into the database. Pressing the Return/Enter key while focused on the "Key" or "Value" inputs is the same as pressing the "Put" button.

Entering a blank "Value" will remove that "Key" from the database.

Pressing the "Get" button will look up the "Key", and show its "Value". It will also populate the value in the table.

The table with "Key" and "Value" headings shows the known keys. Initially, it won't show any values, since we only fetch the keys from the database, but if you click on one of the keys in the table, or look it up by typing it into the "Key" input field and pressing the "Get" button, it will display in the "Value" column.

The key/value pairs entered in the real backend example are persistent until you stop paying Amazon, or remove them. For the simulated database, they last for only one session. They do, however, survive "Logout" followed by "Login".

