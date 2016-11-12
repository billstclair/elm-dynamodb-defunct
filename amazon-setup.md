# Configuring Amazon DynamoDB for DynamoBackend

This page is a guide to configuring [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) for use by the DynamoBackend library. You'll also need to read [Using the DynamoBackend JavaScript](port-setup.md).

Go to the [Amazon DynamoDB home page](https://aws.amazon.com/dynamodb/). Click on "Sign In to the Console":

![DynamoDB Home Page](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/01-home-page.png)

Either log in with your existing Amazon account, or create a new one:

![Amazon Login Page](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/02-login.png)

Choose "DynamoDB" from the "Amazon Web Services" console:

![Amazon Web Services Console](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/03-choose.png)

Click "Create Table" on the DynamoDB "Dashboard":

![DynamoDB Dashboard](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/04-dashboard.png)

Fillin whichever "Table name" you want, "user" as a "String" field for the "Primary key", check "Add sort key", and enter "appkey" as the sort key. Leave "Use default settings" checked, and click "Create":

![Create Table](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/05-create-table.png)

Wait while AWS does whatever it does to create your new table.

You'll probably want to decrease your provisioned read and write capacity units from the default of 5 to 1, unless you know that you want your users to use lots of bandwidth from the get go. You can do that on the "Capacity" tab:

![Capacity](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/06-capacity.png)

Now go to the "Access control" tab, set the "Identity provider" to "Login with Amazon", select "DeleteItem, GetItem, "Query", and "UpdateItem", leave "Allowed attribute" as "All attribute", and click "Create Policy":

![Access Control](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/07-access-control.png)

The "Attach policy instructions" on that page are close, but not quite accurate.
