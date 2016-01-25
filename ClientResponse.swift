//
//  ClientResponse.swift
//  net
//
//  Created by Samuel Kallner on 11/23/15.
//  Copyright © 2015 IBM. All rights reserved.
//


import Foundation

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
    func readDataHelper(data: NSMutableData) -> Int {
        return responseBuffers.fillData(data)
    }
}
