----------------------------------------------------------------------
--
-- URLParser.elm
-- Some URL parsing functions I can't find anywhere else.
-- Copyright (c) 2016 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module UrlParser exposing (parseUrl)

import Html exposing (Html, div, h1, text, input, button)
import Http
import String
import List

splitQueryAssignment : String -> (String, String)
splitQueryAssignment query =
  let pieces = String.split "=" query
  in
      case List.head pieces of
          Nothing -> ("", "")
          Just v ->
            let var = Http.uriDecode v
            in
                case List.head <| List.drop 1 pieces of
                    Nothing -> (var, "")
                    Just val ->
                      (var, Http.uriDecode val)

-- The opposite of Http.url
parseUrl : String -> (String, List (String, String))
parseUrl url =
  let pieces = String.split "?" url
  in
      case List.head pieces of
          Nothing -> (url, [])
          Just b ->
            let base = Http.uriDecode b
            in
                case List.head <| List.drop 1 pieces of
                    Nothing -> (base, [])
                    Just query ->
                      let sets = String.split "&" query
                      in
                          (base, List.map splitQueryAssignment sets)
