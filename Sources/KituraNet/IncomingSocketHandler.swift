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
    
    static let socketWriterQueue = DispatchQueue(label: "Socket Writer")
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
        static let socketReaderQueue = DispatchQueue(label: "Socket Reader")
    
        // Note: This var is optional to enable it to be constructed in the init function
        var readerSource: DispatchSourceRead!
        var writerSource: DispatchSourceWrite?
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
        
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                         queue: IncomingSocketHandler.socketReaderQueue)
        
            readerSource.setEventHandler() {
                self.handleRead()
            }
            readerSource.setCancelHandler() {
                self.handleCancel()
            }
            readerSource.resume()
        #endif
        
        processor?.handler = self
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
        if  writeBuffer.count != 0 {
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
            
            #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                if writeBuffer.count == 0, let writerSource = writerSource {
                    writerSource.cancel()
                }
            #endif
        }
        
        if preparingToClose {
            close()
        }
    }
    
    /// create the writer source
    private func createWriterSource() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
            writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                          queue: IncomingSocketHandler.socketWriterQueue)
            
            writerSource!.setEventHandler() {
                self.handleWriteHelper()
            }
            writerSource!.setCancelHandler() {
                self.writerSource = nil
            }
            writerSource!.resume()
        #endif
    }
    
    /// Write as much data to the socket as possible, buffering the rest
    func write(from data: Data) {
        guard socket.socketfd > -1  else { return }
        
        data.withUnsafeBytes() { [unowned self] (bytes: UnsafePointer<UInt8>) in
            do {
                let written: Int
            
                if  self.writeBuffer.count == 0 {
                    written = try self.socket.write(from: bytes, bufSize: data.count)
                }
                else {
                    written = 0
                }
            
                if written != data.count {
                    IncomingSocketHandler.socketWriterQueue.sync() { [unowned self] in
                        self.writeBuffer.append(bytes+written, count:data.count-written)
                    }
                    
                    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                        if self.writerSource == nil {
                            self.createWriterSource()
                        }
                    #endif
                }
            }
            catch {
                Log.error("Write to socket (file descriptor \(self.socket.socketfd) failed. Error number=\(errno). Message=\(self.errorString(error: errno)).")
            }
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
    
    /// Private method to return a string representation on a value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    func errorString(error: Int32) -> String {
        
        return String(validatingUTF8: strerror(error)) ?? "Error: \(error)"
    }
}
