import AppKit

// Private SkyLight (CoreGraphics Services) calls. Windows that join all Spaces still slide
// out and back in during a Space switch; putting the window in its own Space above
// everything keeps it on screen the whole time. Same trick used by other notch apps.
// shortcut: private API, may break in a future macOS; if it fails the island just flickers like before.
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSpaceCreate") private func CGSSpaceCreate(_ cid: Int32, _ flag: Int32, _ opts: CFDictionary?) -> UInt64
@_silgen_name("CGSSpaceSetAbsoluteLevel") private func CGSSpaceSetAbsoluteLevel(_ cid: Int32, _ space: UInt64, _ level: Int32)
@_silgen_name("CGSAddWindowsToSpaces") private func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSShowSpaces") private func CGSShowSpaces(_ cid: Int32, _ spaces: CFArray)

enum TopSpace {
    private static let conn = _CGSDefaultConnection()
    private static let space: UInt64 = {
        let s = CGSSpaceCreate(conn, 0x1, nil)
        CGSSpaceSetAbsoluteLevel(conn, s, Int32.max)
        CGSShowSpaces(conn, [s] as CFArray)
        return s
    }()

    static func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(conn, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
