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

{-# LANGUAGE FlexibleContexts #-}

module StompClient where

    import Control.Monad.State
    import Data.Map (Map, empty, foldrWithKey, fromList, insert, member, (!))
    import Data.Maybe
    import Data.Text
    import Data.Text.Encoding
    import Network.Socket
    import Network.Socket.ByteString as BSock
    import Network.URI
    import Text.Regex.Base
    import Text.Regex.TDFA

    protocols = "1.2" -- ^STOMP protocol versions supported by this client.

    {-| All the STOMP commands.  They are instances of Read and Show to aid
        serialization. -}
    data Command = ACK | ABORT | BEGIN | CONNECT | CONNECTED | COMMIT
                 | DISCONNECT | ERROR | MESSGAGE | RECEIPT | SEND | STOMP
                 | SUBSCRIBE | UNSUBSCRIBE
        deriving (Read, Show)

    {-| The HeaderMap holds all the headers in the Frame.  The keys and values
        are strings. -}
    newtype HeaderMap = HeaderMap {headerMap::Map String String}

    {-| The HeaderMap is an instance of Read to aid serialization. -}
    instance Read HeaderMap where
        readsPrec _ s = [(HeaderMap headerMap, "")]
            where headerMap = fromList $ map getKeyValuePair (lines s)
                  getKeyValuePair s = (k, v)
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
           where (command, _, rest) = s =~ "\n" :: (String, String, String)
                 (headers, _, body) = rest =~ "\n\n" :: (String, String, String)

    {-| The Frame is an instance of Show to aid serialization. -}
    instance Show Frame where
        show (StompFrame command headers body) =
                unlines [show command, show headers, show body]

    {-| The StopServer is identified by its uri. -}
    data Server = StompServer {uri::URI}
        deriving Show

    data ServerConnection = StompConnection {
            server::Server,    -- ^The server for this connection.
            sock::Socket,      -- ^The socket used for communication.
            maxFrameSize::Int  -- ^Size in bytes for the socket buffer.
        }

    ---------------  Sessions  -----------------
    data Session = StompSession {
              sessionID::String,
              sessionConnection::ServerConnection
         }

    startSession :: String -> String -> Server -> Int -> IO(Maybe Session)
    startSession = ((((return . mkSession =<<) .) .) .) . connectTo
        where mkSession (Just frame, conn) = Just (StompSession id conn)
                  where id = (headerMap $ headers frame) ! "session"
              mkSession _ = Nothing

    endSession :: Session -> IO(Bool)
    endSession (StompSession id conn) = disconnectFrom conn >> return True

    ---------------  Transactions  -----------------
    data Transaction = StompTransaction String
                     | TransactionStarted String
                     | TransactionFinished String

    startTransaction :: Session -> String -> IO(Maybe Transaction)
    startTransaction (StompSession _ conn) transID = do
                let headerMap = HeaderMap $ fromList [("transaction", transID)]
                response <- exchangeFrame conn (StompFrame BEGIN headerMap "")
                case response of
                    Just frame -> return $ Just (TransactionStarted transID)
                    otherwise -> return Nothing

    continueTransaction :: Session -> Transaction -> Frame -> IO(Maybe Frame, Transaction)
    continueTransaction (StompSession _ conn) trans frame = do
                f <- exchangeFrame conn frame
                return (f, trans)

    endTransaction :: Session -> Transaction -> IO(Maybe Transaction)
    endTransaction (StompSession _ conn) (StompTransaction transID) = do
            let headers = HeaderMap(fromList [("transaction", transID)])
                frame = StompFrame COMMIT headers ""
            response <- exchangeFrame conn frame
            case response of
                Just frame -> return $ Just (TransactionFinished transID)
                otherwise -> return Nothing

    ---------------  Other Stuff  -----------------
    acknowledgeMessage :: ServerConnection -> String -> String -> IO(Int)
    acknowledgeMessage conn msgID tID = sendFrame conn frame
        where headers = HeaderMap (fromList [("message-id", msgID), ("transaction", tID)])
              frame = StompFrame ACK headers ""

    connectTo :: String -> String -> Server -> Int -> IO(Maybe Frame, ServerConnection)
    connectTo user passcode server frameSize = withSocketsDo $ do
        sock <- socket AF_INET Stream defaultProtocol
        case uriAuthority (uri server) of
            Just (URIAuth user serverName serverPort) -> do
                hostaddr <- inet_addr serverName
                let portNumber = read serverPort :: PortNumber
                connect sock (SockAddrInet portNumber hostaddr)
                let conn = (StompConnection server sock frameSize)
                    headers = fromList [("login", user), ("passcode", passcode),
                                        ("accept-version", protocols)]
                    frame = StompFrame CONNECT (HeaderMap headers) ""
                response <- exchangeFrame conn frame
                return (response, conn)
            otherwise -> return (Nothing, undefined)

    disconnectFrom :: ServerConnection -> IO(Int)
    disconnectFrom conn = sendFrame conn frame
        where frame = StompFrame DISCONNECT (HeaderMap Data.Map.empty) ""

    exchangeFrame :: ServerConnection -> Frame -> IO(Maybe Frame)
    exchangeFrame conn frame = do
          res <- sendFrame conn frame
          recvFrame conn

    sendFrame :: ServerConnection -> Frame -> IO(Int)
    sendFrame server frame = BSock.send (sock server) (encodeUtf8 $ pack $ show frame)

    type Queue = String
    sendMessage :: String -> Queue -> String -> String -> ServerConnection -> IO(Int)
    sendMessage msg q mid tid conn = do
          let frame = StompFrame BEGIN (HeaderMap $ fromList [("transaction", tid)]) ""
          sendFrame conn frame
          let headers = fromList [("destination", q), ("transaction", tid)]
          sendFrame conn (StompFrame SEND (HeaderMap headers) msg)

    recvFrame :: ServerConnection -> IO(Maybe Frame)
    recvFrame server = do let frameSize = maxFrameSize server
                          (str, len) <- recvLen (sock server) frameSize
                          if len <= frameSize then
                              return $ Just (read str)
                            else
                              return Nothing

    recvMessage :: ServerConnection -> IO(Maybe (String, String))
    recvMessage server = do
        maybeFrame <- recvFrame server
        case maybeFrame of
             Just (StompFrame cmd heads msg) -> return $ Just (queue, msg)
                where queue = (headerMap heads) ! "destination"
             Nothing -> return Nothing

    subscribeTo :: ServerConnection -> Queue -> IO(Int)
    subscribeTo server q = sendFrame server (StompFrame SUBSCRIBE (HeaderMap headers) "")
        where headers = fromList [("destination", q), ("ack", "client-individual")]

    unsubscribeFrom :: ServerConnection -> Queue -> IO(Int)
    unsubscribeFrom server q = sendFrame server (unsubscribeFrame "")
        where unsubscribeFrame = StompFrame UNSUBSCRIBE (HeaderMap headers)
              headers = fromList [("destination", q)]
