// String.swift
// LingoRuntime module - Embedded Swift compatible

/// Custom case-insensitive string operations to avoid Foundation dependency and Embedded Swift Unicode Data Tables
fileprivate func _asciiLowercased(_ byte: UInt8) -> UInt8 {
    if byte >= 65 && byte <= 90 { // 'A' ... 'Z'
        return byte + 32
    }
    return byte
}

extension String {
    internal func caseInsensitiveEquals(_ other: String) -> Bool {
        let lUTF8 = self.utf8
        let rUTF8 = other.utf8
        if lUTF8.count != rUTF8.count { return false }
        var lIter = lUTF8.makeIterator()
        var rIter = rUTF8.makeIterator()
        while let lByte = lIter.next(), let rByte = rIter.next() {
            if _asciiLowercased(lByte) != _asciiLowercased(rByte) {
                return false
            }
        }
        return true
    }

    internal func caseInsensitiveLessThan(_ other: String) -> Bool {
        var lIter = self.utf8.makeIterator()
        var rIter = other.utf8.makeIterator()
        while let lByte = lIter.next() {
            guard let rByte = rIter.next() else { return false } // r is shorter
            let lLower = _asciiLowercased(lByte)
            let rLower = _asciiLowercased(rByte)
            if lLower != rLower {
                return lLower < rLower
            }
        }
        // l is shorter or equal
        return rIter.next() != nil
    }

    internal func caseInsensitiveContains(_ substr: String) -> Bool {
        let sBytes = Array(self.utf8)
        let subBytes = Array(substr.utf8)
        if subBytes.isEmpty { return true }
        if subBytes.count > sBytes.count { return false }
        for i in 0...(sBytes.count - subBytes.count) {
            var match = true
            for j in 0..<subBytes.count {
                if _asciiLowercased(sBytes[i+j]) != _asciiLowercased(subBytes[j]) {
                    match = false
                    break
                }
            }
            if match { return true }
        }
        return false
    }

    internal func caseInsensitiveStartsWith(_ prefix: String) -> Bool {
        let sBytes = Array(self.utf8)
        let pBytes = Array(prefix.utf8)
        if pBytes.count > sBytes.count { return false }
        for i in 0..<pBytes.count {
            if _asciiLowercased(sBytes[i]) != _asciiLowercased(pBytes[i]) { return false }
        }
        return true
    }
}
