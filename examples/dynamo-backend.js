//////////////////////////////////////////////////////////////////////
//
// dynamo-backend.js
// JavaScript for DynamoBackend.elm
// Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
// Some rights reserved.
// Distributed under the MIT License
// See LICENSE.txt
//
//////////////////////////////////////////////////////////////////////

// The single global variable defined by this file
var dynamoBackend = {};

(function() {

// External entry points
dynamoBackend.dispatch = dispatch;

// For debugging
dynamoBackend.getLoginCompleteResponse = getLoginCompleteResponse;
dynamoBackend.getDynamoDb = getDynamoDb;

dynamoBackend.login = login;
dynamoBackend.updateItem = updateItem;
dynamoBackend.getItem = getItem;
dynamoBackend.deleteItem = deleteItem;
dynamoBackend.scanKeys = scanKeys;

// Expects the top-level HTML file that loads this to first load
// dynamo-server-info.js, to define dynamoServerInfo for your app.
var clientId = dynamoServerInfo.clientId;
var tableName = dynamoServerInfo.tableName;
var appName = dynamoServerInfo.appName;
var roleArn = dynamoServerInfo.roleArn;
var providerId = dynamoServerInfo.providerId;
var awsRegion = dynamoServerInfo.awsRegion;

// From http://login.amazon.com/website
window.onAmazonLoginReady = function() {
  amazon.Login.setClientId(clientId);
};

// Modified from http://login.amazon.com/website
// Expects to be called with document as arg.
// The DOM must have a div with an id of 'amazon-root'.
function installLoginScript (d) {
  var a = d.createElement('script');
  a.type = 'text/javascript';
  a.async = true;
  a.id = 'amazon-login-sdk';
  a.src = 'https://api-cdn.amazon.com/sdk/login1.js';
  d.getElementById('amazon-root').appendChild(a);
};

function addProperty (name, obj, arr) {
  var val = obj[name];
  if (!(val === undefined)) {
    arr.push([name, String(val)])
  }
  return arr;
}

function addProperties (names, obj, arr) {
  for (idx in names) {
    var name = names[idx];
    arr = addProperty(name, obj, arr);
  }
  return arr;
}

// Debugging
var loginCompleteResponse = null;
function getLoginCompleteResponse() {
  return loginCompleteResponse;
}

function loginCompleteInternal (response) {
  loginCompleteResponse = response; // debugging
  var res = [["operation", "access-token"]]; // NOT "login". See DynamoBackend.elm
  var err = response.error;
  if (err) {
    res = addProperties(["error", "error_description", "error_uri"],
                        response,
                        res);
  } else {
    var accessToken = response.access_token;
    // http://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/loading-browser-credentials-federated-id.html
    AWS.config.credentials.params.WebIdentityToken = accessToken;
    res = addProperties(["state", "access_token",
                         "token_type", "expires_in", "scope"],
                        response,
                        res)
  }
  return res;
}

//  document.getElementById('LoginWithAmazon').onclick = function() {
function login (state, port) {
  options = { scope : 'profile', state : state };
  loginComplete = function(response) {
    port.send(loginCompleteInternal(response));
  };
  amazon.Login.authorize(options, loginComplete);
};

function debugCallback(err, data) {
  if (err) console.log(err, err.stack);
  else console.log(data);
}

// We prefix the keys given to Amazon with the appName,
// so that we can use a single column of a single table
// for multiple applications.
function appkey(key) {
  return appName + ":" + key;
}

function stripAppkey(appkey) {
  var cnt = appName.length + 1;
  return appkey.substring(cnt);
}

// DynamoDB access functions
function updateItem(user, key, value, callback) {
  if (callback === undefined) {
    callback = debugCallback;
  }
  var params = {
    Key: {
      user: {
        S: user
      },
      appkey: {
        S: appkey(key)
      }
    },
    TableName: tableName,
    AttributeUpdates: {
      value: {
        Action : 'PUT',
        Value: {
          S: value
        }
      }
    }
  }
  dynamodb.updateItem(params, callback);
}

function getItem(user, key, callback) {
  if (callback === undefined) {
    callback = debugCallback;
  }
  var params = {
    Key: {
      user: {
        S: user
      },
      appkey: {
        S: appkey(key)
      }
    },
    TableName: tableName,
    AttributesToGet: [
      'value'
      ]
  }
  dynamodb.getItem(params, callback);
}

function deleteItem(user, key, callback) {
  if (callback === undefined) {
    callback = debugCallback;
  }
  var params = {
    Key: {
      user: {
        S: user
      },
      appkey: {
        S: appkey(key)
      }
    },
    TableName: tableName,
  }
  dynamodb.deleteItem(params, callback);
}

function scanKeys(callback) {
  if (callback === undefined) {
    callback = debugCallback;
  }
  var params = {
    TableName: tableName,
    AttributesToGet: [
      'appkey'
      ],
    ScanFilter: {
      appkey: {
        ComparisonOperator: 'BEGINS_WITH',
        AttributeValueList: [
          {
            S: appkey('')
          }
        ]
      }
    }
  }
  dynamodb.scan(params, callback);
}

// Roles created here:
// https://console.aws.amazon.com/iam/home?#roles
AWS.config.credentials = new AWS.WebIdentityCredentials({
  RoleArn: roleArn,
  ProviderId: providerId
});

AWS.config.update({region: awsRegion});

// Create a service object
// Used by the database functions above
var dynamodb = new AWS.DynamoDB();

// For debugging
function getDynamoDb() {
  return dynamodb;
}

function propertiesToObject(properties) {
  var res = {};
  for (var idx in properties) {
    var prop = properties[idx];
    res[prop[0]] = prop[1];
  }
  return res;
}

function errorProperties(operation, err) {
  return [ ["operation", operation],
           ["code", err.code],
           ["error", err.message]
         ];
}


// The top-level entry-point. Called from the users's HTML file.
// Properties is an array of two-element arrays: [[key, value],...]
// In Elm, that's [(key, value), ...]
// key and value are strings.
// Port is a response port to which to send() the responses.
// It takes a single argument, a properties array.
function dispatch(properties, port) {
  var props = propertiesToObject(properties);
  var operation = props.operation;
  switch (operation) {
    case "installLoginScript":
      // Properties expected: <none>
      // No return expected
      installLoginScript(document);
      break;
    case "login":
      // Properties expected: state
      // Properties sent: state, access_token, token_type, expires_in, scope
      login(props.state, port);
      break;
    case "logout":
      // Properties expected: none
      // Properties sent: Nothing sent
      amazon.Login.logout();
      break;
    case "put":
      // Properties expected: user, key, value
      // Properties sent: user, key, value
      updateItem(props.user, props.key, props.value, function(err, data) {
        var res;
        if (err) {
          res = errorProperties("put", err);
        } else {
          res = properties;
        }
        port.send(res);
      });
      break;
    case "get":
      // Properties expected: user, key
      // Properties sent: user, key
      getItem(props.user, props.key, function(err, data) {
        var res;
        if (err) {
          res = errorProperties("get", err);
        } else {
          var value = data.Item.value.S;
          res = properties;
          if (value) {
            res.push(["value", value]);
          } else {
            res.push(["error", "Missing value"]);
          }
        }
        port.send(res);
      });
      break;
    case "delete":
      // Properties expected: user, key
      // Properties sent: user, key
      deleteItem(props.user, props.key, function(err, data) {
        var res;
        if (err) {
          res = errorProperties("delete", err);
        } else {
          res = properties;
        }
        port.send(res);
      });
      break;
    case "scan":
      // Properties expected: none
      // Properties sent: ["", key] for each key
      scanKeys(function (err, data) {
        var res;
        if (err) {
          res = errorProperties("scan", err);
        } else {
          res = properties;
          var items = data.Items;
          for (var idx in items) {
            var item = items[idx];
            var value = item.appkey.S;
            if (value) {
              res.push(["", stripAppkey(value)])
            }
          }
        }
        port.send(res);
      });
      break;
    default:
      var res = [["operation", operation],
                 ["error", "unknown operation: " + operation]
                ]
      port.send(res);
  }
}

})();   // Execute the enclosing function()
