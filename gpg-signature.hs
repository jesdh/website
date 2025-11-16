{-# LANGUAGE OverloadedStrings #-}

import           Control.Monad  ((>=>))

import           Data.Bifunctor (first)
import qualified Data.Text      as T
import qualified Data.Text.IO   as TIO


import           System.Exit    (ExitCode(..))
import           System.Process (readProcessWithExitCode)

main :: IO ()
main = TIO.readFile "index.html" >>= process . splitHtml
  where process (p, b, s) = gpgSign b >>= TIO.writeFile "index.html" . (p <>) . (<> s)

breakOnInclude :: T.Text -> T.Text -> (T.Text, T.Text)
breakOnInclude needle haystack =
  let (before, match) = T.breakOn needle haystack
  in  first (before <>) . T.splitAt (T.length needle) $ match

splitHtml :: T.Text -> (T.Text, T.Text, T.Text)
splitHtml content = (prefix <> tag1, body <> tag2, suffix)
  where (prefix, rest1) = breakOnInclude "<pre" content

        (tag1, rest2)   = breakOnInclude ">\n" rest1

        (_, rest3)      = T.breakOn "</pre>" rest2

        (body, rest4)   = T.breakOnEnd "<pre" rest3

        (tag2, rest5)   = breakOnInclude ">" rest4

        (_, suffix)     = T.breakOn "</pre>" rest5

gpgSign :: T.Text -> IO T.Text
gpgSign =
  (readProcessWithExitCode "gpg" ["--clearsign", "-"] . T.unpack) >=> handle
  where handle (ExitSuccess, stdout, _) = pure . T.pack $ stdout
        handle (_, _, stderr)           = error stderr
