import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
}

/// Physical key positions; modifier storage is independent of AppKit/Carbon bit masks.
public struct GlobalShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers
    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    public static let keyNames: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2",
        20:"3", 21:"4", 22:"6", 23:"5", 25:"9", 26:"7", 28:"8", 29:"0",
        31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"空格"
    ]
    public func validate() throws {
        guard Self.keyNames[keyCode] != nil, modifiers.rawValue & ~UInt32(15) == 0,
              modifiers.rawValue.nonzeroBitCount >= 2,
              !modifiers.intersection([.control, .command]).isEmpty else {
            throw StockCoreError.invalidValue("请用至少两个修饰键（包含 ⌃ 或 ⌘），加字母、数字或空格。")
        }
    }
    public var displayName: String {
        let pairs: [(ShortcutModifiers, String)] = [(.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")]
        return pairs.filter { modifiers.contains($0.0) }.map { $0.1 }.joined() + (Self.keyNames[keyCode] ?? "?")
    }
}
