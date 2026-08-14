import Foundation

extension Bundle {
    // Bundle.module is scoped to the target that declares it; tests reach the package's
    // catalog through this rather than their own (resource-less) bundle.
    static let hostsKit = Bundle.module
}
