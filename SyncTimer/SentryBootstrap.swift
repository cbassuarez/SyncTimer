import Foundation
import Sentry

enum SentryBootstrap {
    private static var didStart = false

    static func startIfConfigured() {
        guard !didStart else { return }
        let dsnValue = (Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = dsnValue.hasPrefix("$(") && dsnValue.hasSuffix(")")
        guard !dsnValue.isEmpty, !isPlaceholder else { return }

        didStart = true
        SentrySDK.start { options in
            options.dsn = dsnValue

            #if DEBUG
            options.debug = true
            options.environment = "debug"
            #else
            options.debug = false
            options.environment = "release"
            #endif

            options.sendDefaultPii = false
            options.tracesSampleRate = 0
            options.enableAutoSessionTracking = true

            options.attachScreenshot = false
            options.attachViewHierarchy = false
        }
    }
}
