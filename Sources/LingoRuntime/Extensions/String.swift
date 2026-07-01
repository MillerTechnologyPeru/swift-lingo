// String.swift
// LingoRuntime module - Embedded Swift compatible

/// Custom case-insensitive string operations to avoid Foundation dependency and Embedded Swift Unicode Data Tables
private func _asciiLowercased(_ byte: UInt8) -> UInt8 {
    if byte >= 65 && byte <= 90 {  // 'A' ... 'Z'
        return byte + 32
    }
    return byte
}

extension String {
    public func asciiLowercased() -> String {
        let needsLowercasing = self.utf8.contains { $0 >= 65 && $0 <= 90 }
        if !needsLowercasing { return self }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(self.utf8.count)
        for byte in self.utf8 {
            bytes.append(_asciiLowercased(byte))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func caseInsensitiveEquals(_ other: String) -> Bool {
        if self.utf8.count != other.utf8.count { return false }
        return self.withUTF8 { lBuf in
            other.withUTF8 { rBuf in
                if lBuf.count != rBuf.count { return false }
                for i in 0..<lBuf.count {
                    if _asciiLowercased(lBuf[i]) != _asciiLowercased(rBuf[i]) {
                        return false
                    }
                }
                return true
            }
        }
    }

    public func caseInsensitiveLessThan(_ other: String) -> Bool {
        return self.withUTF8 { lBuf in
            other.withUTF8 { rBuf in
                let minCount = Swift.min(lBuf.count, rBuf.count)
                for i in 0..<minCount {
                    let lLower = _asciiLowercased(lBuf[i])
                    let rLower = _asciiLowercased(rBuf[i])
                    if lLower != rLower {
                        return lLower < rLower
                    }
                }
                return lBuf.count < rBuf.count
            }
        }
    }

    public func caseInsensitiveContains(_ substr: String) -> Bool {
        if substr.isEmpty { return true }
        return self.withUTF8 { sBuf in
            substr.withUTF8 { subBuf in
                if subBuf.count > sBuf.count { return false }
                if subBuf.isEmpty { return true }
                for i in 0...(sBuf.count - subBuf.count) {
                    var match = true
                    for j in 0..<subBuf.count {
                        if _asciiLowercased(sBuf[i + j]) != _asciiLowercased(subBuf[j]) {
                            match = false
                            break
                        }
                    }
                    if match { return true }
                }
                return false
            }
        }
    }

    public func caseInsensitiveStartsWith(_ prefix: String) -> Bool {
        return self.withUTF8 { sBuf in
            prefix.withUTF8 { pBuf in
                if pBuf.count > sBuf.count { return false }
                if pBuf.isEmpty { return true }
                for i in 0..<pBuf.count {
                    if _asciiLowercased(sBuf[i]) != _asciiLowercased(pBuf[i]) { return false }
                }
                return true
            }
        }
    }
}
