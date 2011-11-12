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
    
    import Control.Monad.State
    import Data.Map (Map, empty, foldrWithKey, fromList, member, (!))
    import Data.Maybe
    import Network.Socket
    import Network.URI
    import Text.Regex.Posix
    
    protocols = "1.0" -- ^STOMP protocol versions supported by this client.
    
    {-| All the STOMP commands.  They are instances of Read and Show to aid serialization. -}
    data Command = ACK | ABORT | BEGIN | CONNECT | CONNECTED | COMMIT | DISCONNECT
                 | ERROR | MESSGAGE | RECEIPT | SEND | STOMP | SUBSCRIBE | UNSUBSCRIBE
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
    
    data Server = StompServer {uri::URI}
        deriving Show
    
    data ServerConnection = StompConnection {server::Server,    -- ^The STOMP server for this connection.
                                             sock::Socket,      -- ^The socket used for communication.
                                             maxFrameSize::Int} -- ^A size in bytes for the socket buffer.
    
    type MessageID = String
    type SessionID = String
    type TransactionID = String
    
    type Session = State SessionID
    type Transaction = State TransactionID 
    
    acknowledgeMessage :: Transaction -> IO(Int)
    acknowledgeMessage = do id <- get
                            sendFrame (StompFrame ACK (HeaderMap headers) "") conn
        where headers = fromList [("message-id", id), ("transaction", id)]
              conn = StompConnection "http://127.0.0.1" 4 5
    
    connectTo :: String -> String -> Server -> IO(Maybe ServerConnection)
    connectTo user passcode server = do 
        sock <- socket AF_INET Stream defaultProtocol
        hostaddr <- inet_addr "127.0.0.1"
        connect sock (SockAddrInet 6613 hostaddr)
        let connection = (StompConnection server sock 4096)
            headers = fromList [("login", user), ("passcode", passcode), ("accept-version", protocols)]
            frame = StompFrame CONNECT (HeaderMap headers)
        response <- exchangeFrame frame connection
        let isConnected = (member CONNECTED) . headerMap
        return $ maybe Nothing (\f -> if isConnected f then Just connection else Nothing) response
    
    disconnectFrom :: ServerConnection -> IO(Int)
    disconnectFrom = sendFrame frame
        where frame = StompFrame DISCONNECT (HeaderMap Data.Map.empty) ""
    
    exchangeFrame :: Frame -> ServerConnection -> IO(Maybe Frame)
    exchangeFrame frame connection = do sendFrame
                                        return (recvFrame connection)
    
    sendFrame :: Frame -> ServerConnection -> IO()
    sendFrame frame server = send (sock server) (show frame)
    
    type Queue = String
    
    sendMessage :: String -> Queue -> MessageID -> TransactionID -> ServerConnection -> IO(Int)
    sendMessage msg q mid tid conn = do
               sendFrame (StompFrame BEGIN (fromList [("transaction", id)]) "") conn
               sendFrame (StompFrame SEND (HeaderMap headers) msg) conn
        where headers = fromList [("destination", q), ("transaction", id)]
    
    recvFrame :: ServerConnection -> IO(Maybe Frame)
    recvFrame server = do let frameSize = maxFrameSize server
                          (str, len) <- recvLen (sock server) frameSize
                          if len <= frameSize then
                              return $ Just (read str)
                            else
                              return Nothing
    
    recvMessage :: ServerConnection -> IO(Maybe (String, String))
    recvMessage server = do maybeFrame <- recvFrame server
                            let getQueue = (flip (!) "destination") . headerMap
                            maybe Nothing (\f -> Just (getQueue f, body f)) maybeFrame
    
    subscribeTo :: Queue -> Transaction -> IO(Int)
    subscribeTo q = sendFrame (StompFrame SUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("destination", q), ("ack", "client-individual")] 
    
    unsubscribeFrom :: Queue -> Transaction -> IO(Int)
    unsubscribeFrom q = sendFrame (StompFrame UNSUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("destination", q)]
