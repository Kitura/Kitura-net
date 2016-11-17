/*
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
 */

import Dispatch

import Foundation

import LoggerAPI
import Socket

/// This class handles incoming sockets to the HTTPServer. The data sent by the client
/// is read and passed to the current `IncomingDataProcessor`.
///
/// - Note: The IncomingDataProcessor can change due to an Upgrade request.
///
/// - Note: This class uses different underlying technologies depending on:
///
///     1. On Linux, if no special compile time options are specified, epoll is used
///     2. On OSX, DispatchSource is used
///     3. On Linux, if the compile time option -Xswiftc -DGCD_ASYNCH is specified,
///        DispatchSource is used, as it is used on OSX.
public class IncomingSocketHandler {
    
    static let socketWriterQueue = DispatchQueue(label: "Socket Writer")
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
        static let socketReaderQueues = [DispatchQueue(label: "Socket Reader A"), DispatchQueue(label: "Socket Reader B")]
    
        // Note: This var is optional to enable it to be constructed in the init function
        var readerSource: DispatchSourceRead!
        var writerSource: DispatchSourceWrite?
    
        private let numberOfSocketReaderQueues = IncomingSocketHandler.socketReaderQueues.count
    
        private func socketReaderQueue(fd: Int32) -> DispatchQueue {
            return IncomingSocketHandler.socketReaderQueues[Int(fd) % numberOfSocketReaderQueues];
        }
    #endif

    let socket: Socket
    
    /// The `IncomingSocketProcessor` instance that processes data read from the underlying socket.
    public var processor: IncomingSocketProcessor?
    
    private weak var manager: IncomingSocketManager?
    
    private let readBuffer = NSMutableData()
    private let writeBuffer = NSMutableData()
    private var writeBufferPosition = 0
    private var preparingToClose = false
    
    /// The file descriptor of the incoming socket
    var fileDescriptor: Int32 { return socket.socketfd }
    
    init(socket: Socket, using: IncomingSocketProcessor, managedBy: IncomingSocketManager) {
        self.socket = socket
        processor = using
        manager = managedBy
        
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                         queue: socketReaderQueue(fd: socket.socketfd))
        
            readerSource.setEventHandler() {
                _ = self.handleRead()
            }
            readerSource.setCancelHandler(handler: self.handleCancel)
            readerSource.resume()
        #endif
        
        processor?.handler = self
    }
    
    /// Read in the available data and hand off to common processing code
    ///
    /// - Returns: true if the data read in was processed
    func handleRead() -> Bool {
        var result = true
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: readBuffer)
            }
            if  readBuffer.length > 0  {
                result = handleReadHelper()
            }
            else {
                if  socket.remoteConnectionClosed  {
                    processor?.socketClosed()
                    prepareToClose()
                }
            }
        }
        catch let error as Socket.Error {
            Log.error("Read from socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
            prepareToClose()
        } catch {
            Log.error("Unexpected error...")
            prepareToClose()
        }
        return result
    }
    
    private func handleReadHelper() -> Bool {
        guard let processor = processor else { return true }
        
        let processed = processor.process(readBuffer)
        if  processed {
            readBuffer.length = 0
        }
        return processed
    }
    
    /// Helper function for handling data read in while the processor couldn't
    /// process it, if there is any
    func handleBufferedReadDataHelper() -> Bool {
        let result : Bool
        
        if  readBuffer.length > 0  {
            result = handleReadHelper()
        }
        else {
            result = true
        }
        return result
    }
    
    /// Handle data read in while the processor couldn't process it, if there is any
    ///
    /// - Note: On Linux, the `IncomingSocketManager` should call `handleBufferedReadDataHelper`
    ///        directly.
    public func handleBufferedReadData() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            if socket.socketfd != Socket.SOCKET_INVALID_DESCRIPTOR {
                socketReaderQueue(fd: socket.socketfd).sync() { [unowned self] in
                    _ = self.handleBufferedReadDataHelper()
                }
            }
        #endif
    }
    
    /// Write out any buffered data now that the socket can accept more data
    func handleWrite() {
        #if !GCD_ASYNCH  &&  os(Linux)
            IncomingSocketHandler.socketWriterQueue.sync() { [unowned self] in
                self.handleWriteHelper()
            }
        #endif
    }
    
    /// Inner function to write out any buffered data now that the socket can accept more data,
    /// invoked in serial queue.
    private func handleWriteHelper() {
        if  writeBuffer.length != 0 {
            do {
                let amountToWrite = writeBuffer.length - writeBufferPosition
                
                let written: Int
                    
                if amountToWrite > 0 {
                    written = try socket.write(from: writeBuffer.bytes + writeBufferPosition,
                                               bufSize: amountToWrite)
                }
                else {
                    if amountToWrite < 0 {
                        Log.error("Amount of bytes to write to file descriptor \(socket.socketfd) was negative \(amountToWrite)")
                    }
                    
                    written = amountToWrite
                }
                
                if written != amountToWrite {
                    writeBufferPosition += written
                }
                else {
                    writeBuffer.length = 0
                    writeBufferPosition = 0
                }
            }
            catch let error {
                Log.error("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
            }
            
            #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                if writeBuffer.length == 0, let writerSource = writerSource {
                    writerSource.cancel()
                }
            #endif
        }
        
        if preparingToClose {
            close()
        }
    }
    
    /// Create the writer source
    private func createWriterSource() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                          queue: IncomingSocketHandler.socketWriterQueue)
            
            writerSource!.setEventHandler(handler: self.handleWriteHelper)
            writerSource!.setCancelHandler() {
                self.writerSource = nil
            }
            writerSource!.resume()
        #endif
    }
    
    /// Write as much data to the socket as possible, buffering the rest
    ///
    /// - Parameter data: The NSData object containing the bytes to write to the socket.
    public func write(from data: NSData) {
        write(from: data.bytes, length: data.length)
    }
    
    /// Write a sequence of bytes in an array to the socket
    ///
    /// - Parameter from: An UnsafeRawPointer to the sequence of bytes to be written to the socket.
    /// - Parameter length: The number of bytes to write to the socket.
    public func write(from bytes: UnsafeRawPointer, length: Int) {
        guard socket.socketfd > -1  else { return }
        
        do {
            let written: Int
            
            if  writeBuffer.length == 0 {
                written = try socket.write(from: bytes, bufSize: length)
            }
            else {
                written = 0
            }
            
            if written != length {
                IncomingSocketHandler.socketWriterQueue.sync() { [unowned self] in
                    self.writeBuffer.append(bytes + written, length: length - written)
                }
                
                #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                    if writerSource == nil {
                        createWriterSource()
                    }
                #endif
            }
        }
        catch let error {
            Log.error("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
        }
    }
    
    /// If there is data waiting to be written, set a flag and the socket will
    /// be closed when all the buffered data has been written.
    /// Otherwise, immediately close the socket.
    public func prepareToClose() {
        if  writeBuffer.length == writeBufferPosition  {
            close()
        }
        else {
            preparingToClose = true
        }
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    ///
    /// - Note: On Linux closing the socket causes it to be dropped by epoll.
    /// - Note: On OSX the cancel handler will actually close the socket.
    private func close() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            readerSource.cancel()
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
}
