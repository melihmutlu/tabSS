/// Byte layouts the undocumented window server and Accessibility calls expect (as used by AltTab).
public enum PrivateEncodings {
    /// An Accessibility remote token: pid, a zero field, the "coco" tag, then the element's ID, little-endian.
    public static func remoteToken(pid: Int32, elementID: UInt64) -> [UInt8] {
        littleEndianBytes(pid) + littleEndianBytes(Int32(0)) + littleEndianBytes(Int32(0x636f_636f)) + littleEndianBytes(elementID)
    }

    /// A synthesized "make key window" event record; it is posted twice, with phase 1 then 2.
    public static func makeKeyWindowRecord(windowID: UInt32, phase: UInt8) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 0xf8)
        record[0x04] = 0xf8
        record[0x08] = phase
        record.replaceSubrange(0x20..<0x30, with: repeatElement(0xff, count: 0x10))
        record[0x3a] = 0x10
        record.replaceSubrange(0x3c..<0x40, with: littleEndianBytes(windowID))
        return record
    }

    private static func littleEndianBytes<Value: FixedWidthInteger>(_ value: Value) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
