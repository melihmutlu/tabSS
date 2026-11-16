import ApplicationServices
import Darwin
import TabssCore

/// Undocumented system functions, the same ones AltTab relies on. Resolved at runtime so a symbol missing
/// in some macOS version disables one feature (with a public fallback) instead of preventing launch.
enum PrivateAPI {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateWithRemoteTokenFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let getWindow: GetWindowFunction? = symbol("_AXUIElementGetWindow")
    private static let createWithRemoteToken: CreateWithRemoteTokenFunction? = symbol("_AXUIElementCreateWithRemoteToken")
    // Public but deprecated; looked up like the rest to keep the build warning-free.
    private static let getProcessForPID: GetProcessForPIDFunction? = symbol("GetProcessForPID")
    private static let setFrontProcess: SetFrontProcessFunction? = symbol("_SLPSSetFrontProcessWithOptions", in: skyLightPath)
    private static let postEventRecord: PostEventRecordFunction? = symbol("SLPSPostEventRecordTo", in: skyLightPath)
    private static let mainConnection: MainConnectionFunction? = symbol("SLSMainConnectionID", in: skyLightPath)
    private static let copySpacesForWindows: CopySpacesForWindowsFunction? = symbol("SLSCopySpacesForWindows", in: skyLightPath)

    /// Maps an Accessibility window to its window server ID; there is no public way to do this.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Accessibility only lists windows on the current Space; this reaches an app's elements by ID on any Space.
    static func element(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        let token = Data(PrivateEncodings.remoteToken(pid: pid, elementID: elementID))
        return createWithRemoteToken(token as CFData)?.takeRetainedValue()
    }

    /// Whether the window belongs to any Space. Background tabs and windows an app merely hid belong to none.
    /// Nil if the answer isn't available.
    static func isOnAnySpace(_ windowID: CGWindowID) -> Bool? {
        guard let mainConnection, let copySpacesForWindows else { return nil }
        let allSpaces: Int32 = 0x7
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let spaces = copySpacesForWindows(mainConnection(), allSpaces, windows)?.takeRetainedValue() else { return nil }
        return CFArrayGetCount(spaces) > 0
    }

    /// Makes `windowID` the key window of its app and brings both to the front, switching Space if needed.
    /// Returns false when the private calls are unavailable or fail.
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var process = ProcessSerialNumber()
        guard getProcessForPID(pid, &process) == noErr else { return false }

        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&process, windowID, userGenerated) == .success else { return false }
        return [UInt8(1), 2].allSatisfy { phase in
            var record = PrivateEncodings.makeKeyWindowRecord(windowID: windowID, phase: phase)
            return postEventRecord(&process, &record) == .success
        }
    }

    /// Looks in `library` (a system path) if given, otherwise in every image already loaded into the process.
    private static func symbol<Function>(_ name: String, in library: String? = nil) -> Function? {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        let handle = library.map { dlopen($0, RTLD_LAZY) } ?? rtldDefault
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: Function.self)
    }
}
