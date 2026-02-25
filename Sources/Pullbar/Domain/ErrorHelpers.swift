import Foundation

extension Error {
    /// Returns the localized description if this error conforms to `LocalizedError`
    /// and has a non-empty `errorDescription`, otherwise `nil`.
    var userFacingMessage: String? {
        if let localized = self as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        return nil
    }
}
