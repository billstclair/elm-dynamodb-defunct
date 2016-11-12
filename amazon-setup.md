# Configuring Amazon DynamoDB for DynamoBackend

This page is a guide to configuring [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) for use by the DynamoBackend library. You'll also need to read [Using the DynamoBackend JavaScript](port-setup.md).

First you need to create an Amazon application. You'll need its "Application ID" when  you create the security role that allows people to access your DynamoDB table with their Amazon account credentials.

In order to register an application, you need to create a "Privacy Notice" page on your application's web site. There are no requirements I've seen for the contents of that page. I created [kakuro-dojo.com/privacy.html](kakuro-dojo.com/privacy.html) for my Kakuro game.

Now go to the [Amazon App Console](http://login.amazon.com/manageApps), and click "Sign in to the App Console":

![App Console Login](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/a01-app-console.png)

Sign in with an existing Amazon ID, or create a new one. Click "Register new application" on the Seller Central page:

![Register new application](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/a02-register-new-application.png)

Enter a "Name", "Description", "Privacy Notice URL", and, if you have one, choose a file for the application's "Logo Image". Click "Save".

Remember that application name. You'll need it to configure the JavaScript for your Elm code (appName).

![Register Your Application](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/a03-register-application.png)

Note the "App ID", a long string beginning with "amzn1.application." You'll need it below.

Click on the "Web Settings" header to expand that section. Click the "Edit" button, enter your application's web site URL in "Allowed JavaScript Origins", and click "Save":

![Set JavaScript Origins](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/a04-javascript-origins.png)

Save the "Client ID", beginning with "amzn1.application-oa2-client." You'll need it to configure the JavaScript that goes with your Elm code (clientId).

You will want to return here to enter "Android Settings" and "IOS Settings", if you decide to wrap your application as a smart phone app and distribute it on one of those app stores.

There doesn't appear to be any way to delete an application once you've created it, though you could change all its properties to repurpose it for something else. So I'm stuck with my "DynamoBackend Example" application.

Go to the [Amazon DynamoDB home page](https://aws.amazon.com/dynamodb/). Click on "Sign In to the Console":

![DynamoDB Home Page](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/01-home-page.png)

Log in with the same account you used to create your application.

![Amazon Login Page](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/02-login.png)

Choose "DynamoDB" from the "Amazon Web Services" console:

![Amazon Web Services Console](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/03-choose.png)

Click "Create Table" on the DynamoDB "Dashboard":

![DynamoDB Dashboard](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/04-dashboard.png)

Fillin whichever "Table name" you want, "user" as a "String" field for the "Primary key", check "Add sort key", and enter "appkey" as the sort key. Leave "Use default settings" checked, and click "Create":

![Create Table](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/05-create-table.png)

Remember that "Table name". You'll need it to configure the JavaScript for your Elm code (tableName).

Wait while AWS does whatever it does to create your new table.

You'll probably want to decrease your provisioned read and write capacity units from the default of 5 to 1, unless you know that you want your users to use lots of bandwidth from the get go. You can do that on the "Capacity" tab:

![Capacity](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/06-capacity.png)

Go to the "Overview" tab, and note down the region name from the "Amazon Resource Name (ARN)". In the image below, it's "us-east-1" in "arn:aws:dynamodb:us-east-1:575107064159:table/table". You'll need it to configure the JavaScript for your Elm code (awsRegion).

![Table Overview](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/07-table-overview.png)

Now go to the "Access control" tab, set the "Identity provider" to "Login with Amazon", select "DeleteItem, GetItem, "Query", and "UpdateItem", leave "Allowed attribute" as "All attributes", and click "Create Policy":

![Access Control](https://raw.githubusercontent.com/billstclair/elm-dynamodb-images/master/08-access-control.png)

Save the JSON in the box to the right of the "Create policy" button, you'll need it below.

The "Attach policy instructions" on that page are close, but not quite accurate. First, leave this browser tab as is, and in a new tab, create a new policy:

1. Go to the [IAM console](https://console.aws.amazon.com/iam/home?#roles)
2. Click on "Policies"
3. Click "Create Policy"
4. Click "Select" for "Create Your Own Policy"
5. Give your new policy a "Policy Name" and "Description", and paste in the JSON you saved above.
6. Click the "Create Policy" button.
7. You can filter your policy from the long list of "AWS Managed" policies by selecting "Customer Managed" instead of "All Types" for "Filter".

Now go back to the DynamoDB "Tables" tab, and mostly follow the "Attach policy instructions" (my comments in square brackets):

1. Go to the [IAM console](https://console.aws.amazon.com/iam/home?#roles) to attach this policy. [correct]
2. In the IAM console, click Roles, and then click Create New Role. [Roles is already selected when you get to the IAM console]
3. Enter a name for the role and click Continue. [click "Next Step"]
4. In the Select Role Type pane, choose Role for Web Identity Provider Access and click Select. [You first have to click the radio button labelled "Role for Identity Provider Access", then you can click "Select" for "Grant access to web identity providers"]
5. Enter your Identity Provider and Application ID, and click Continue. [Choose "Login with Amazon" as the "Identity Provider", use the Application ID you remembered above, and click "Next Step"]
6. Verify that the trust policy document is correct, and click Continue. [it is correct, click "Next Step"]

At this point, the instructions are wrong. Do this instead:

7. Check the box to the left of the policy that you created above.
8. Click "Next Step".
9. Remember the "Role ARN", a string beginning with "arn:aws:iam::". You'll need it to configure the JavaScript for your Elm code (roleArn)
10. Click "Create Role"

Whew! Have a coffee, or some water, or a beer, and continue with [Using the DynamoBackend JavaScript](port-setup.md). You'll need the clientId, tableName, appName, roleArn, and awsRegion you saved above.
