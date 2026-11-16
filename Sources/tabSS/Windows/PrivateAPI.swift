import ApplicationServices
import Darwin

/// Undocumented system functions. Resolved at runtime so a symbol missing in some macOS version
/// degrades a feature instead of preventing launch.
enum PrivateAPI {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // There is no public way to map an Accessibility window to its window server ID.
    private static let getWindow: GetWindowFunction? = symbol("_AXUIElementGetWindow")

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private static func symbol<Function>(_ name: String) -> Function? {
        // RTLD_DEFAULT: search every image already loaded into the process.
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: Function.self)
    }
}
