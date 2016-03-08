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


#if os(OSX)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

import Foundation

// MARK: SpiUtils

public class SpiUtils {
    
    ///
    /// Abbreviations for month names
    ///
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    ///
    /// Abbreviations for days of the week
    ///
    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    ///
    /// Format the current time for use in HTTP
    ///
    /// - Returns: string representation of timestamp
    ///
    public static func httpDate() -> String {
        
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
    
    ///
    /// Format the given date for use in HTTP
    ///
    /// - Parameter date: the date
    ///
    /// - Returns: string representation of timestamp
    ///
    public static func httpDate(date: NSDate) -> String {
        
        let unitFlags: NSCalendarUnit = [.Hour, .Day, .Month, .Year, .Weekday, .Minute, .Second]
        let components = NSCalendar.currentCalendar().components(unitFlags, fromDate: date)
        let wday = Int(components.weekday)
        let mday = Int(components.day)
        let mon = Int(components.month)
        let hour = Int(components.hour)
        let min = Int(components.minute)
        let sec = Int(components.second)
        return "\(days[wday]), \(twoDigit(mday)) \(months[mon]) \(components.year+1900) \(twoDigit(hour)):\(twoDigit(min)):\(twoDigit(sec)) GMT"
        
    }
    
    ///
    /// Prepends a zero to a 2 digit number if necessary
    ///
    /// - Parameter num: the number
    ///
    private static func twoDigit(num: Int) -> String {
        
        return (num < 10 ? "0" : "") + String(num)
        
    }
}