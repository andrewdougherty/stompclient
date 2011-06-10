{-
   SVM is an implementation of a support vector machine in the Haskell language.
   Copyright (C) 2011  Andrew Dougherty
   
   Send email to: andrewdougherty@me.com
   
   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
-}

module StompClient where
    
    import Data.Map (Map, foldrWithKey, fromList)
    import Network
    import Text.Regex.Posix
    
    {-| All the stomp commands.  They are instances of Read and Show to aid serialization. -}
    data Command = ACK | ABORT | BEGIN | CONNECT | CONNECTED | COMMIT
                 | DISCONNECT | SEND | SUBSCRIBE | UNSUBSCRIBE
        deriving (Read, Show)
    
    {-| The HeaderMap holds all the headers in the Frame.  The keys and values are strings. -}
    newtype HeaderMap = HeaderMap {headerMap :: Map String String}
    
    {-| The HeaderMap is an instance of Read to aid serialization. -}
    instance Read HeaderMap where
        readsPrec _ s = [(HeaderMap $ fromList $ map getKeyValuePair (lines s),"")]
            where getKeyValuePair s = (k, v)
                      where (k, _, v) = s =~ ": " :: (String, String, String)
    
    {-| The HeaderMap is an instance of Show to aid serialization. -}
    instance Show HeaderMap where
        show = (foldrWithKey concatHeaderToString "") . headerMap
            where concatHeaderToString k v s = k ++ ": " ++ v ++ "\n" ++ s
    
    {-| All stomp messages are frames. -}
    data Frame = StompFrame {command::Command, headers::HeaderMap, body::String}
    
    {-| The Frame is an instance of Read to aid serialization. -}
    instance Read Frame where
        readsPrec _ s = [(StompFrame (read command) (read headers) body, "")]
            where (command, _, theRest) = s =~ "\n" :: (String, String, String)
                  (headers, _, body) = theRest =~ "\n\n" :: (String, String, String)
    
    {-| The Frame is an instance of Show to allow for easy serialization. -}
    instance Show Frame where
        show (StompFrame command headers body) = unlines [show command, show headers, show body]
    
    data Server = StompServer
    
    connect :: String -> String -> Server -> IO()
    connect user passcode = send connectFrame
        where connectFrame = StompFrame CONNECT (HeaderMap headers) ""
              headers = fromList [("login", user), ("passcode", passcode)]
    
    send :: Frame -> Server -> IO()
    send frame server = return ()
    
    recv :: IO()
    recv = return ()
    
    type Queue = String
    
    subscribeTo :: Queue -> Server -> IO()
    subscribeTo q = send (StompFrame SUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("queue", q)] 
    
    unsubscribeFrom :: Queue -> Server -> IO()
    unsubscribeFrom q = send (StompFrame UNSUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("queue", q)]
