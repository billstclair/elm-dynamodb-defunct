Scripts for use during development. All expect to be run from the "examples" directory. For example:

```
cd .../elm-dynamodb/examples
bin/m real
```

`bin/m foo` compiles `src/foo.elm` into `/dev/null`. Useful for fixing syntax and types.

`bin/update-real` compiles `src/real.elm` into `site/Main.js`, copies the rest of the files necessary to run the application into `site/`, and uses `bin/rsyncit` to upload them to my live server.

`bin/update-simulated` compiles `src/simulated.elm` into `site/simulated.html` and uses `bin/rsyncit` to upload it to my live server.

`bin/rsyncit` is a script that greatly simplifies managing uploads to disparate internet servers. It is documented [here](https://steemit.com/hacking/@billstclair/rsyncit).
