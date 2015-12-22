//
//  ServerRequest.swift
//  net
//
//  Created by Samuel Kallner on 11/22/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import Foundation

public class ServerRequest: IncomingMessage {
    private var socket: Socket
    
    init (socket: Socket) {
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
