# Amazon DynamoDB Backend Example Applications

This directory contains examples of using the `DynamoBackend` module.

I'm still working on the real backend. It's prototyped in `src/dynamodb.elm` and `site/login.html`.

The simulated backend is fully functional. To run it:

```
cd .../elm-dynamodb/examples
elm reactor
```

Then aim your browser at http://localhost:8000/simulated.elm.

## How to use the interface

The real and simulated backend examples share most of their code, with the only differences being the `h2` header and the database, real or simulated.

First, click the "Login" button. This will just login with simulated credentials in the simulated example. It will pop up an Amazon login window in the real example, and you'll need to log in to your Amazon account.

Your account name and email are displayed, and a Logout button.

Use the "Key" and "Value" fields plus the "Put" button to enter new key/value pairs into the database. Pressing the Return/Enter key while focused on the "Key" or "Value" inputs is the same as pressing the "Put" button.

Entering a blank "Value" will remove that "Key" from the database.

Pressing the "Get" button will look up the "Key", and show its "Value". It will also populate the value in the table.

The table with "Key" and "Value" headings shows the known keys. Initially, it wont' show any values, since we only fetch the keys from the database, but if you click on one of the keys in the table, or look it up by typing it into the "Key" input field and pressing the "Get" button, it will display in the "Value" column.

The key/value pairs entered in the real backend example are persistent until you stop paying Amazon, or remove them. For the simulated database, they last for only one session. They do, however, survive "Logout" followed by "Login".

