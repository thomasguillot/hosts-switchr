import Foundation
import HostsKit

extension Error {
    // User-facing message for the error alert; never leaks raw enum/case names.
    var userFacingMessage: String {
        if let e = self as? SourceError {
            switch e {
            case .insecureURL:
                return "That address isn’t secure (https). Sources are added over https only — their contents are written into your system hosts file, and a plain-http link could be tampered with on the way to you. Try the https:// version of the address; most lists offer one."
            case .invalidURL:
                return "That doesn’t look like a complete web address. Include the full URL, like https://example.com/hosts.txt."
            case .notHostsFormat:
                return "That link didn’t return a hosts-format list, so it wasn’t added."
            case .tooLarge:
                return "That list is too large to download safely, so it wasn’t added."
            case .insecureRedirect:
                return "That address redirected to an insecure (http) location, so it was blocked."
            case .notFound:
                return "That source could no longer be found."
            case .builtinNotRemovable:
                return "Built-in sources can’t be removed."
            }
        }
        if let e = self as? ProfileError {
            switch e {
            case .protectedProfile:
                return "That profile is protected and can’t be changed."
            case .notFound:
                return "That item could no longer be found."
            case .duplicateName:
                return "That name is already taken. Please choose a different name."
            }
        }
        return "Something went wrong. Please try again."
    }
}
