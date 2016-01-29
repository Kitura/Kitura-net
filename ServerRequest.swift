//
//  ServerRequest.swift
//  net
//
//  Created by Samuel Kallner on 11/22/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import Foundation

import ETSocket

public class ServerRequest: IncomingMessage {
    private let socket: ETSocket
    
    init (socket: ETSocket) {
        self.socket = socket
        super.init(isRequest: true)
        
        setup(self)
    }
}

extension ServerRequest: IncomingMessageHelper {
    func readDataHelper(data: NSMutableData) throws -> Int {
        return try socket.readData(data)
    }
}
