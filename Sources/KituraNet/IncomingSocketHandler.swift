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
        typealias DispatchSourceWriteType = DispatchSourceWrite
        static let socketReaderWriterQueue = DispatchQueue(label: "Socket ReaderWriter")
        private let writeBufferLock = DispatchSemaphore(value: 1)
    #else
        #if GCD_ASYNCH
            typealias DispatchSourceReadType = dispatch_source_t
            typealias DispatchSourceWriteType = dispatch_source_t
            static let socketReaderWriterQueue = dispatch_queue_create("Socket ReaderWriter", DISPATCH_QUEUE_SERIAL)
        #endif
        private let writeBufferLock: dispatch_semaphore_t
    #endif
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
        // Note: This var is optional to enable it to be constructed in the init function
        var readerSource: DispatchSourceReadType!
        var writerSource: DispatchSourceWriteType!
    #endif

    let socket: Socket
        
    public var processor: IncomingSocketProcessor?
    private var writeBuffer = Data()
    private var preparingToClose = false
    
    /// The file descriptor of the incoming socket
    var fileDescriptor: Int32 { return socket.socketfd }
    
    init(socket: Socket, using: IncomingSocketProcessor) {
        self.socket = socket
        processor = using
        processor?.handler = self
        
        
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                         queue: IncomingSocketHandler.socketReaderWriterQueue)
        
            readerSource.setEventHandler() {
                self.handleRead()
            }
            readerSource.setCancelHandler() {
                self.handleCancel()
            }
            readerSource.resume()
            
            writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                          queue: IncomingSocketHandler.socketReaderWriterQueue)
            
            writerSource.setEventHandler() {
                self.handleWrite()
            }
            writerSource.resume()
        #elseif GCD_ASYNCH
            readerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket.socketfd), 0,
		                                          IncomingSocketHandler.socketReaderWriterQueue)

            dispatch_source_set_event_handler(readerSource) {
                self.handleRead()
            }
            dispatch_source_set_cancel_handler(readerSource) {
                self.handleCancel()
            }
            dispatch_resume(readerSource)
            
            writerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, UInt(socket.socketfd), 0,
                                                  IncomingSocketHandler.socketReaderWriterQueue)
            
            dispatch_source_set_event_handler(writerSource) {
                self.handleRead()
            }
            dispatch_resume(writerSource)
        #endif
        
        #if os(Linux)
            writeBufferLock = dispatch_semaphore_create(1)
        #endif
    }
    
    /// Read in the available data and hand off to common processing code
    func handleRead() {
        var buffer = Data()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: &buffer)
            }
            if  buffer.count > 0  {
                processor?.process(buffer)
            }
            else {
                if  errno != EAGAIN  &&  errno != EWOULDBLOCK  {
                    prepareToClose()
                }
            }
        }
        catch let error as Socket.Error {
            Log.error(error.description)
        } catch {
            Log.error("Unexpected error...")
        }
    }
    
    /// Write out any buffered data now that the sockt can accept more data
    func handleWrite() {
        if  writeBuffer.count != 0 {
            lockWriteBufferLock()
            do {
                let written = try socket.write(from: writeBuffer)
                
                if written != writeBuffer.count {
                    writeBuffer = writeBuffer.subdata(in: written..<writeBuffer.count)
                }
                else {
                    writeBuffer = Data()
                }
            }
            catch {
                Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
            }
            unlockWriteBufferLock()
        }
        
        if preparingToClose {
            close()
        }
    }
    
    /// Write as much data to the socket as possible, buffering the rest
    func write(from data: Data) {
        guard socket.socketfd > -1  else { return }
        
        do {
            let written = try socket.write(from: data)
            
            if written != data.count {
                lockWriteBufferLock()
                writeBuffer.append(data.subdata(in: written..<data.count))
                unlockWriteBufferLock()
            }
        }
        catch {
            Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
        }
    }
    
    /// If there is data waiting to be written, then set a flag,
    /// otherwise actaully close the socket
    func prepareToClose() {
        if  writeBuffer.count == 0  {
            close()
        }
        else {
            preparingToClose = true
        }
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    ///
    /// **Note:** On Linux closing the socket causes it to be dropped by epoll.
    /// **Note:** On OSX the cancel handler will actually close the socket.
    private func close() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            readerSource.cancel()
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
    
    private func lockWriteBufferLock() {
        #if os(Linux)
            dispatch_semaphore_wait(writeBufferLock, DISPATCH_TIME_FOREVER)
        #else
            _ = writeBufferLock.wait(timeout: DispatchTime.distantFuture)
        #endif
    }
    
    private func unlockWriteBufferLock() {
        #if os(Linux)
            dispatch_semaphore_signal(writeBufferLock)
        #else
            writeBufferLock.signal()
        #endif
    }
    
    /// Private method to return a string representation on a value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    func errorString(error: Int32) -> String {
        
        return String(validatingUTF8: strerror(error)) ?? "Error: \(error)"
    }
}
