//
//  ClientResponse.swift
//  net
//
//  Created by Samuel Kallner on 11/23/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import io

public class ClientResponse: IncomingMessage {
    
    init() {
        super.init(isRequest: false)
        setup(self)
    }
    
    public internal(set) var status = -1 {
        didSet {
            statusCode = HttpStatusCode(rawValue: status)!
        }
    }
    public internal(set) var statusCode: HttpStatusCode = HttpStatusCode.UNKNOWN
    var responseBuffers = BufferList()
    
}

extension ClientResponse: IncomingMessageHelper {
    func readBufferHelper(inout buffer: [UInt8]) -> Int {
        return responseBuffers.fillBuffer(&buffer)
    }
}
