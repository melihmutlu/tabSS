import ApplicationServices

/// Typed access to the Accessibility API.
enum AX {
    /// Upper bound for any single AX call, so a hung app can't stall us for the system default of 6 seconds.
    static func limitMessagingTimeout(to seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyValue(element, attribute) as? Bool
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        copyValue(element, attribute).flatMap(asElement)
    }

    /// Tells "the app didn't answer in time" (`answered` false) apart from "it has none".
    static func elementReply(_ element: AXUIElement, _ attribute: String) -> (answered: Bool, element: AXUIElement?) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (result != .cannotComplete, result == .success ? value.flatMap(asElement) : nil)
    }

    /// Nil when the app didn't answer in time (hung or busy). Entries are type-checked, since the array comes
    /// from another process, and capped so an app reporting absurd numbers of elements can't stall us.
    static func elements(_ element: AXUIElement, _ attribute: String, limit: Int = 1000) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .cannotComplete { return nil }
        guard result == .success, let array = value as? [AnyObject] else { return [] }
        return array.prefix(limit).compactMap(asElement)
    }

    private static func asElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
