{-
   StompClient is a library for communicating with message servers which
   implement the Stomp protocol.
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
    
    import Data.Map (Map, empty, foldrWithKey, fromList)
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
    
    {-| The Frame is an instance of Show to aid serialization. -}
    instance Show Frame where
        show (StompFrame command headers body) = unlines [show command, show headers, show body]
    
    data Server = StompServer
    
    acknowledgeMessage :: String -> String -> Server -> IO()
    acknowledgeMessage msgID trans = sendFrame (StompFrame ACK (HeaderMap headers) "")
        where headers = fromList [("message-id", msgID), ("transaction", trans)]
    
    connectTo :: String -> String -> Server -> IO()
    connectTo user passcode = sendFrame (StompFrame CONNECT (HeaderMap headers) "")
        where headers = fromList [("login", user), ("passcode", passcode)]
    
    disconnectFrom :: Server -> IO()
    disconnectFrom = sendFrame (StompFrame DISCONNECT (HeaderMap Data.Map.empty) "")
    
    sendFrame :: Frame -> Server -> IO()
    sendFrame frame server = return ()
    
    type Queue = String
    
    sendMessage :: String -> String -> Server -> IO()
    sendMessage msg q = sendFrame (StompFrame SEND (HeaderMap headers) msg)
        where headers = fromList [("destination", q)]
    
    recvMessage :: IO()
    recvMessage = return ()
    
    subscribeTo :: Queue -> Server -> IO()
    subscribeTo q = sendFrame (StompFrame SUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("destination", q), ("ack", "auto")] 
    
    unsubscribeFrom :: Queue -> Server -> IO()
    unsubscribeFrom q = sendFrame (StompFrame UNSUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("destination", q)]
