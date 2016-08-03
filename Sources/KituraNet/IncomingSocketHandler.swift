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

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
    import Dispatch
#endif

import Foundation

import LoggerAPI
import Socket

/// This class handles incoming sockets to the HTTPServer. The data sent by the client
/// is read and passed to the current IncomingDataProcessor.
///
/// **Note*** The IncomingDataProcessor can change due to an Upgrade request.
///
/// **Note:** This class uses different underlying technologies depending on:
///     1. On Linux if no special compile time options are specified, epoll is used
///     2. On OSX DispatchSource is used
///     3. On Linux if the compile time option -Xswiftc -DGCD_ASYNCH is specified,
///        DispatchSource is used, as it is used on OSX.
public class IncomingSocketHandler {
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
        typealias DispatchSourceReadType = DispatchSourceRead
        static let socketReaderQueue = DispatchQueue(label: "Socket Reader")
    #else
        #if GCD_ASYNCH
            typealias DispatchSourceReadType = dispatch_source_t
            static let socketReaderQueue = dispatch_queue_create("Socket Reader", DISPATCH_QUEUE_SERIAL)
        #endif
    #endif
    
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
        // Note: This var is optional to enable it to be constructed in the init function
        var source: DispatchSourceReadType!
    #endif

    let socket: Socket
        
    public var processor: IncomingSocketProcessor?
    
    /// The file descriptor of the incoming socket
    var fileDescriptor: Int32 { return socket.socketfd }
    
    init(socket: Socket, using: IncomingSocketProcessor) {
        self.socket = socket
        processor = using
        processor?.handler = self
        
        
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            source = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                   queue: IncomingSocketHandler.socketReaderQueue)
        
            source.setEventHandler() {
                self.handleRead()
            }
            source.setCancelHandler() {
                self.handleCancel()
            }
            source.resume()
        #elseif GCD_ASYNCH
            source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket.socketfd), 0, 
		                            IncomingSocketHandler.socketReaderQueue)

            dispatch_source_set_event_handler(source) {
                self.handleRead()
            }
            dispatch_source_set_cancel_handler(source) {
                self.handleCancel()
            }
            dispatch_resume(source)
        #endif
    }
    
    /// Read in the available data and hand off to common processing code
    func handleRead() {
        let buffer = NSMutableData()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: buffer)
            }
            if  buffer.length > 0  {
                processor?.process(buffer)
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
    
    /// Write data to the socket
    func write(from data: NSData) {
        guard socket.socketfd > -1  else { return }
        
        do {
            try socket.write(from: data)
        }
        catch {
            Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
        }
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    ///
    /// **Note:** On Linux closing the socket causes it to be dropped by epoll.
    /// **Note:** On OSX the cancel handler will actually close the socket.
    func close() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            source.cancel()
        #elseif GCD_ASYNCH
	    dispatch_source_cancel(source!)
        #else
            handleCancel()
        #endif
    }
    
    /// DispatchSource cancel handler
    private func handleCancel() {
        if  socket.socketfd > -1 {
            socket.close()
        }
        processor?.inProgress = false
        processor?.keepAliveUntil = 0.0
    }
    
    /// Private method to return a string representation on a value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    func errorString(error: Int32) -> String {
        
        return String(validatingUTF8: strerror(error)) ?? "Error: \(error)"
    }
}
