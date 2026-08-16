// Transpiled from Fixtures/differential.ls
import LingoRuntime

public class Differential: LingoObject {
    /// Property keys for type-safe property access.
    public enum CodingKeys: String, Sendable, CaseIterable {
        case `total` = "total"

        /// Case-insensitive lookup without Unicode data tables.
        public static func find(_ name: String) -> CodingKeys? {
            for key in allCases {
                if name.caseInsensitiveEquals(key.rawValue) {
                    return key
                }
            }
            return nil
        }
    }

    public var `total`: LingoValue = .void

    public override func getProperty(_ name: String) -> LingoValue {
        guard let key = CodingKeys.find(name) else {
            return super.getProperty(name)
        }
        switch key {
        case .`total`: return self.`total`
        }
    }

    public override func setProperty(_ name: String, value: LingoValue) {
        guard let key = CodingKeys.find(name) else {
            super.setProperty(name, value: value)
            return
        }
        switch key {
        case .`total`: self.`total` = value
        }
    }

    private enum MethodName: String {
        case `accumulate` = "accumulate"
        case `classify` = "classify"
        case `sumto` = "sumto"
        case `describe` = "describe"
        case `firstoffset` = "firstoffset"
    }

    public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        guard let methodName = MethodName(rawValue: name.asciiLowercased()) else {
            return super.callMethod(name, args: args)
        }
        switch methodName {
        case .`accumulate`:
            return self.`accumulate`(args.count > 0 ? args[0] : .void)
        case .`classify`:
            return self.`classify`(args.count > 0 ? args[0] : .void)
        case .`sumto`:
            return self.`sumTo`(args.count > 0 ? args[0] : .void)
        case .`describe`:
            return self.`describe`(args.count > 0 ? args[0] : .void, args.count > 1 ? args[1] : .void)
        case .`firstoffset`:
            return self.`firstOffset`(args.count > 0 ? args[0] : .void, args.count > 1 ? args[1] : .void)
        }
    }

    public override init(environment: LingoEnvironment) {
        super.init(environment: environment)
        // total = 0
        self.`total` = LingoValue.integer(0)
        // return me
    }

    public func `accumulate`(_ `n`: LingoValue = LingoValue.void) -> LingoValue {
        let `n`: LingoValue = `n`
        _ = `n`

        // total = (total + n)
        self.`total` = (self.`total` + `n`)
        // return total
        return self.`total`
    }

    public func `classify`(_ `n`: LingoValue = LingoValue.void) -> LingoValue {
        let `n`: LingoValue = `n`
        _ = `n`

        // if (n > 10) then
        //   return "big"
        // else
        //   return "small"
        // end if
        if ((`n` > LingoValue.integer(10)) as LingoValue).asBool() {
            // return "big"
            return LingoValue.string("big")
        } else {
            // return "small"
            return LingoValue.string("small")
        }
    }

    public func `sumTo`(_ `n`: LingoValue = LingoValue.void) -> LingoValue {
        var `i`: LingoValue = .void
        _ = `i`
        var `s`: LingoValue = .void
        _ = `s`
        let `n`: LingoValue = `n`
        _ = `n`

        // s = 0
        `s` = LingoValue.integer(0)
        // repeat with i = 1 to n
        //   s = (s + i)
        // end repeat
        `i` = LingoValue.integer(1)
        while ((`i` <= `n`) as LingoValue).asBool() {
            // s = (s + i)
            `s` = (`s` + `i`)
            `i` = `i` + .integer(1)
        }
        // return s
        return `s`
    }

    public func `describe`(_ `who`: LingoValue = LingoValue.void, _ `score`: LingoValue = LingoValue.void) -> LingoValue {
        let `who`: LingoValue = `who`
        _ = `who`
        let `score`: LingoValue = `score`
        _ = `score`

        // return (who && ("scored" && string(score)))
        return `who`.concatSpace(LingoValue.string("scored").concatSpace(self.`string`(`score`)))
    }

    public func `firstOffset`(_ `needle`: LingoValue = LingoValue.void, _ `hay`: LingoValue = LingoValue.void) -> LingoValue {
        let `needle`: LingoValue = `needle`
        _ = `needle`
        let `hay`: LingoValue = `hay`
        _ = `hay`

        // return offset(needle, hay)
        return self.`offset`(`needle`, `hay`)
    }

}
