/// The framework that defines a private class, matched against the runtime's own record of where the class came from
/// (`class_getImageName`). A class of the same name from another image is treated as missing: a renamed class and
/// a different framework's class are not the same thing.
public struct Image: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The image's file name, without extension: `QuartzCore`, `UIKitCore`, `BaseBoard`.
    public var name: String

    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }

    public static let quartzCore: Image = "QuartzCore"
    public static let uiKitCore: Image = "UIKitCore"
    public static let appKit: Image = "AppKit"
    public static let foundation: Image = "Foundation"
}
