//
//  SpiUtils.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 10/20/15.
//  Copyright © 2015 IBM. All rights reserved.
//


#if os(OSX)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

class SpiUtils {
    
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "jul", "Aug", "sep", "Oct", "Nov", "Dec"]
    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    static func httpDate() -> String {
        var theTime = time(nil)
        var timeStruct: tm = tm()
        gmtime_r(&theTime, &timeStruct)
        
        let wday = Int(timeStruct.tm_wday)
        let mday = Int(timeStruct.tm_mday)
        let mon = Int(timeStruct.tm_mon)
        let hour = Int(timeStruct.tm_hour)
        let min = Int(timeStruct.tm_min)
        let sec = Int(timeStruct.tm_sec)
        return "\(days[wday]), \(twoDigit(mday)) \(months[mon]) \(timeStruct.tm_year+1900) \(twoDigit(hour)):\(twoDigit(min)):\(twoDigit(sec)) GMT"
    }
    
    private static func twoDigit(num: Int) -> String {
        return (num < 10 ? "0" : "") + String(num)
    }
}