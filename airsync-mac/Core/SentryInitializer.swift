//
//  SentryInitializer.swift
//  AirSync
//
//  Created by Sameera Wijerathna
//

import Foundation
import Swift
import Sentry

struct SentryInitializer {
    static func start() {
        let isEnabled = UserDefaults.standard.object(forKey: "isCrashReportingEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "isCrashReportingEnabled")
        
        guard isEnabled else {
            print("[SentryInitializer] Sentry crash reporting is disabled by user.")
            return
        }
        
        SentrySDK.start { options in
            options.dsn = "https://fee55efde3aba42be26a1d4365498a16@o4510996760887296.ingest.de.sentry.io/4511020717178960"
            options.debug = true 
            
            options.sendDefaultPii = true
            
            options.beforeSend = { event in
                if let exceptions = event.exceptions,
                   let firstException = exceptions.first,
                   firstException.type == "App Hanging" {
                    
                    let defaults = UserDefaults.standard
                    let count = defaults.integer(forKey: "sentry_app_hang_count") + 1
                    defaults.set(count, forKey: "sentry_app_hang_count")
                    
                    if count < 20 {
                        return nil
                    } else {
                        defaults.set(0, forKey: "sentry_app_hang_count")
                        return event
                    }
                }
                return event
            }
        }
        print("[SentryInitializer] Sentry initialized successfully.")
    }
}
