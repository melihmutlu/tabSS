import Testing
@testable import TabssCore

struct PrivateEncodingsTests {
    @Test func remoteTokenLayout() {
        let token = PrivateEncodings.remoteToken(pid: 0x0102_0304, elementID: 0x1122_3344_5566_7788)
        #expect(token == [
            0x04, 0x03, 0x02, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x6f, 0x63, 0x6f, 0x63,
            0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
        ])
    }

    @Test func makeKeyWindowRecordLayout() {
        let record = PrivateEncodings.makeKeyWindowRecord(windowID: 0xAABB_CCDD, phase: 2)
        #expect(record.count == 0xf8)
        #expect(record[0x04] == 0xf8)
        #expect(record[0x08] == 2)
        #expect(record[0x20..<0x30].allSatisfy { $0 == 0xff })
        #expect(record[0x3a] == 0x10)
        #expect(Array(record[0x3c..<0x40]) == [0xDD, 0xCC, 0xBB, 0xAA])
        let setOffsets: Set<Int> = Set([0x04, 0x08, 0x3a]).union(0x20..<0x30).union(0x3c..<0x40)
        #expect(record.indices.filter { !setOffsets.contains($0) }.allSatisfy { record[$0] == 0 })
    }

    // The window server reads exactly 20 bytes; the element ID must sit at offset 12 for every value scanned.
    @Test(arguments: [UInt64(0), 1, 999, .max])
    func remoteTokenIsTwentyBytesWithElementIDAtOffset12(elementID: UInt64) {
        let token = PrivateEncodings.remoteToken(pid: 42, elementID: elementID)
        #expect(token.count == 20)
        #expect(Array(token[12..<20]) == withUnsafeBytes(of: elementID.littleEndian, Array.init))
        #expect(Array(token[0..<12]) == [42, 0, 0, 0, 0, 0, 0, 0, 0x6f, 0x63, 0x6f, 0x63])
    }

    // Both records are posted back to back; they must differ only in the phase byte.
    @Test func makeKeyWindowPhasesDifferOnlyInPhaseByte() {
        let first = PrivateEncodings.makeKeyWindowRecord(windowID: 0xFFFF_FFFF, phase: 1)
        let second = PrivateEncodings.makeKeyWindowRecord(windowID: 0xFFFF_FFFF, phase: 2)
        #expect(first[0x08] == 1)
        #expect(second[0x08] == 2)
        #expect(first.indices.filter { first[$0] != second[$0] } == [0x08])
        // A maximal window ID stays within its four bytes.
        #expect(Array(first[0x3c..<0x40]) == [0xff, 0xff, 0xff, 0xff])
        #expect(first[0x3b] == 0 && first[0x40] == 0)
    }
}
