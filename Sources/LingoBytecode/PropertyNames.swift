/// Director's numeric property-ID tables. Referenced by two different
/// opcode families that both address a property by number rather than by
/// name: the Director 4 `Get`/`Set` opcodes' `property_type`-scoped IDs
/// (`movie`/`animation`/`animation2`/`member`), and the newer, dedicated
/// `MenuProp`/`MenuItemProp`/`SoundProp`/`SpriteProp` opcodes' IDs.
///
/// This is shared surface: both the bytecode decompiler (renders these as
/// property names in decompiled source) and anything that executes bytecode
/// directly need the same name for the same numeric ID.
public enum PropertyNames {
    public static func movieProperty(_ id: Int32) -> String {
        switch id {
        case 0x01: return "floatPrecision"
        case 0x02: return "mouseDownScript"
        case 0x03: return "mouseUpScript"
        case 0x04: return "keyDownScript"
        case 0x05: return "keyUpScript"
        case 0x06: return "timeoutScript"
        case 0x07: return "short time"
        case 0x08: return "abbr time"
        case 0x09: return "long time"
        case 0x0a: return "short date"
        case 0x0b: return "abbr date"
        default: return "movieProp_\(id)"
        }
    }

    public static func animationProperty(_ id: Int32) -> String {
        switch id {
        case 0x01: return "beepOn"
        case 0x02: return "buttonStyle"
        case 0x03: return "centerStage"
        case 0x04: return "checkBoxAccess"
        case 0x05: return "checkBoxType"
        case 0x06: return "colorDepth"
        case 0x07: return "colorQD"
        case 0x08: return "exitLock"
        case 0x09: return "fixStageSize"
        case 0x0a: return "fullColorPermit"
        case 0x0b: return "imageDirect"
        case 0x0c: return "doubleClick"
        default: return "animProp_\(id)"
        }
    }

    public static func animation2Property(_ id: Int32) -> String {
        switch id {
        case 0x01, 0x02: return "the number of castMembers"
        case 0x03: return "the number of menus"
        default: return "anim2Prop_\(id)"
        }
    }

    public static func memberProperty(_ id: Int32) -> String {
        switch id {
        case 0x01: return "name"
        case 0x02: return "text"
        case 0x03: return "textStyle"
        case 0x04: return "textFont"
        case 0x05: return "textHeight"
        case 0x06: return "textAlign"
        case 0x07: return "textSize"
        case 0x08: return "picture"
        case 0x09: return "hilite"
        case 0x0a: return "number"
        case 0x0b: return "size"
        case 0x0c: return "loop"
        case 0x0d: return "duration"
        case 0x0e: return "controller"
        case 0x0f: return "directToStage"
        case 0x10: return "sound"
        case 0x11: return "foreColor"
        case 0x12: return "backColor"
        default: return "memberProp_\(id)"
        }
    }

    public static func menuProperty(_ id: UInt32) -> String {
        switch id {
        case 0x01: return "name"
        case 0x02: return "number"
        default: return "menuProp_\(id)"
        }
    }

    public static func menuItemProperty(_ id: UInt32) -> String {
        switch id {
        case 0x01: return "name"
        case 0x02: return "checkMark"
        case 0x03: return "enabled"
        case 0x04: return "script"
        default: return "menuItemProp_\(id)"
        }
    }

    public static func soundProperty(_ id: UInt32) -> String {
        switch id {
        case 0x01: return "volume"
        default: return "soundProp_\(id)"
        }
    }

    public static func spriteProperty(_ id: UInt32) -> String {
        switch id {
        case 0x01: return "type"
        case 0x02: return "backColor"
        case 0x03: return "bottom"
        case 0x04: return "castNum"
        case 0x05: return "constraint"
        case 0x06: return "cursor"
        case 0x07: return "foreColor"
        case 0x08: return "height"
        case 0x09: return "immediate"
        case 0x0a: return "ink"
        case 0x0b: return "left"
        case 0x0c: return "lineSize"
        case 0x0d: return "locH"
        case 0x0e: return "locV"
        case 0x0f: return "moveableSprite"
        case 0x10: return "pattern"
        case 0x11: return "puppet"
        case 0x12: return "right"
        case 0x13: return "scriptNum"
        case 0x14: return "stretch"
        case 0x15: return "top"
        case 0x16: return "trails"
        case 0x17: return "visible"
        case 0x18: return "width"
        case 0x19: return "blend"
        case 0x1a: return "scriptInstanceList"
        case 0x1b: return "loc"
        case 0x1c: return "rect"
        case 0x1d: return "member"
        default: return "spriteProp_\(id)"
        }
    }
}
