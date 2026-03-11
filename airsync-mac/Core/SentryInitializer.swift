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
        }
        print("[SentryInitializer] Sentry initialized successfully.")
    }

    static func triggerTestCrash() {
        let array = [String]()
        _ = array[1]
    }
}
