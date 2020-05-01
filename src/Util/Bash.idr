module Util.Bash
import System
import Core.IpmError
import Data.Vect
import Data.String


-- TODO remove
%access public export


-- TODO taken from idris popen implementation, need to use this directly
my_modStr : Mode -> String
my_modStr Read              = "r"
my_modStr WriteTruncate     = "w"
my_modStr Append            = "a"
my_modStr ReadWrite         = "r+"
my_modStr ReadWriteTruncate = "w+"
my_modStr ReadAppend        = "a+"

my_do_popen : String -> String -> IO Ptr
my_do_popen f m = foreign FFI_C "do_popen" (String -> String -> IO Ptr) f m

my_popen : String -> Mode -> IO (Either FileError File)
my_popen f m = do  ptr <- my_do_popen f (my_modStr m)
                   if !(nullPtr ptr)
                      then do err <- getFileError
                              pure (Left err)
                      else pure (Right (FHandle ptr))

-- TODO taken from https://stackoverflow.com/questions/39812465/how-can-i-call-a-subprocess-in-idris
-- need to reference / refactor.
-- Read the contents of a file
readFileH : (fileHandle : File) -> IO String
readFileH h = loop ""
  where
    loop acc = do
      if !(fEOF h) then pure acc
      else do
        Right l <- fGetLine h | Left err => pure acc
        loop (acc ++ l)

execAndReadOutput : (cmd : String) -> { default "." inDir : String } -> IO (Either IpmError String)
execAndReadOutput cmd {inDir} = do
  Right fh <- my_popen ("cd " ++ inDir ++ " && " ++ cmd) Read | Left err => pure (Left (BashError (show err)))
  contents <- readFileH fh
  pclose fh
  pure (Right contents)


-- end of above reference

doNothing : IO ()
doNothing = pure ()

errorAndExit : (failMessage : String) -> IO ()
errorAndExit failMessage =
  do  putStrLn failMessage
      exit 1

bashCommand :  (command : String)
            -> { default "." inDir : String }
            -> { default False verbose : Bool }
            -> IO Bool
bashCommand command {inDir} {verbose=True} =
  do  putStrLn $ "In directory " ++ inDir ++ ":"
      putStrLn command
      exitCode <- system ("cd " ++ inDir ++ " && " ++ command)
      pure (exitCode == 0)
bashCommand command {inDir} {verbose=False} =
  do  exitCode <- system ("(cd " ++ inDir ++ " && " ++ command ++ ") >/dev/null 2>&1")
      pure (exitCode == 0)

||| Execute a sequence of bash commands, return true if they all succeed and
||| false as soon as one fails.
bashCommandSeq :  (commands : List String)
               -> { default "." inDir : String }
               -> { default False verbose : Bool }
               -> IO Bool
bashCommandSeq [] {inDir} = pure True
bashCommandSeq (x :: xs) {inDir} {verbose} =
  do  success <- bashCommand {inDir=inDir} {verbose=verbose} x
      if
        success
      then
        bashCommandSeq xs {inDir=inDir} {verbose=verbose}
      else
        pure False

bashCommandErr :  (command : String)
               -> { default "." inDir : String }
               -> { default False verbose : Bool }
               -> (errStr : String)
               -> IO (Either IpmError ())
bashCommandErr command {inDir} {verbose} errStr =
  do  success <- bashCommand command {inDir=inDir} {verbose=verbose}
      if
        success
      then
        pure $ Right ()
      else
        pure $ Left $ BashError errStr

bashCommandSeqErr :  (commands : List String)
                  -> { default "." inDir : String }
                  -> { default False verbose : Bool }
                  -> (errStr : String)
                  -> IO (Either IpmError ())
bashCommandSeqErr commands {inDir} {verbose} errStr =
  do  success <- bashCommandSeq commands {inDir=inDir} {verbose=verbose}
      if
        success
      then
        pure $ Right ()
      else
        pure $ Left $ BashError errStr

bashPrompt : (prompt : String) -> {default "" defaultVal : String} -> IO String
bashPrompt prompt {defaultVal} =
  do  putStr $ prompt ++ (if defaultVal == "" then " : " else "(" ++ defaultVal ++ ") : ")
      res <- getLine
      if
        res == ""
      then
        if
          defaultVal == ""
        then
          bashPrompt prompt
        else
          pure defaultVal
      else
        pure res

evalYesNo : String -> Maybe Bool
evalYesNo "y"   = Just True
evalYesNo "n"   = Just False
evalYesNo "yes" = Just False
evalYesNo "no"  = Just False
evalYesNo _     = Nothing

bashYesNo : (prompt : String) -> IO Bool
bashYesNo prompt =
  do  res <- bashPrompt (prompt ++ "(y/n)")
      case evalYesNo (toLower res) of
        Nothing => bashYesNo prompt
        Just b  => pure b

promptNumberedSelection : (prompt : String) -> (options : Vect n String) -> IO (Fin n)
promptNumberedSelection {n} prompt options =
  do  putStrLn prompt
      printOptions 1 options
      res <- getLine
      case (parsePositive res) of
        Nothing       => reprompt
        (Just resInt) => case (integerToFin (resInt-1) n) of
                            (Just i) => pure i
                            Nothing  => reprompt
  where
    printOptions : Integer -> (options : Vect m String) -> IO ()
    printOptions n [] = pure ()
    printOptions n (x :: xs) = do putStrLn ((show n) ++ ": " ++ x)
                                  printOptions (n+1) xs
    reprompt : IO (Fin n)
    reprompt = do putStrLn "Not a valid option"
                  promptNumberedSelection prompt options
