/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

#if os(Linux)

import Foundation
import Glibc

    
import LoggerAPI
import Socket
    
    
///
/// Add Linux specific functionality to the IncomingHTTPSocketHandler. In particular
/// add the code that handles reading from the socket, writing to the socket, and
/// the closing of the socket
extension IncomingHTTPSocketHandler {
    
    ///
    /// Perform platform specfic setup, invoked by the init function
    ///
    func setup() { }
    
    ///
    /// Read in the available data and hand off to ommon processing code
    ///
    func handleRead() {
        let buffer = NSMutableData()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: buffer)
            }
            if  buffer.length > 0  {
                process(buffer, parsingAsynchronously: true)
            }
            else {
                if  errno != EAGAIN  &&  errno != EWOULDBLOCK  {
                    close()
                }
            }
        }
        catch let error as Socket.Error {
            Log.error(error.description)
        } catch {
            Log.error("Unexpected error...")
        }
    }
    
    ///
    /// Write data to the socket
    ///
    func write(from data: NSData) {
        guard socket.socketfd > -1  else { return }
        
        do {
            try socket.write(from: data)
        }
        catch {
            print("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
            Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
        }
    }
    
    ///
    /// Close the socket and mark this handler as no longer in progress.
    ///
    func close() {
        if  socket.socketfd > -1 {
            socket.close()
        }
        inProgress = false
        keepAliveUntil = 0.0
    }
}

    
#endif
