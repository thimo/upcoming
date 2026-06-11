import Foundation

/// A global keyboard shortcut stored as a virtual key code + modifier flags.
/// Codable with named booleans so the JSON stays human-readable.
/// (Pattern copied from Uncommitted.)
public struct GlobalShortcut: Codable, Equatable {
    /// Virtual key code (`kVK_*` from Carbon/Events.h).
    public var keyCode: Int
    /// Display string for the key, e.g. "C", "F5", "Space". Captured at
    /// record time so we don't need a full keyCode-to-string table later.
    public var character: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        keyCode: Int,
        character: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.keyCode = keyCode
        self.character = character
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// macOS standard modifier symbol ordering: ⌃⌥⇧⌘
    public var displayString: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if shift   { s += "⇧" }
        if command { s += "⌘" }
        s += character.uppercased()
        return s
    }

    /// The default shortcut: ⌘⇧C. `kVK_ANSI_C` = 0x08.
    public static let defaultShortcut = GlobalShortcut(
        keyCode: 0x08,
        character: "C",
        command: true,
        shift: true
    )
}
