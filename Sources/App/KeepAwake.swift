// Keep the Mac awake while you step away, so agents keep running. Like
// `caffeinate`: the buddy holds a power assertion while the choice is on and
// lets go when it is off or the app quits. Closing the lid still sleeps a laptop
// (unless it is plugged in to an external display).
import Foundation
import IOKit.pwr_mgt

enum KeepAwakeMode: String, CaseIterable, Identifiable {
    case off, system, display
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off (normal sleep)"
        case .system: "Mac stays on, screen can turn off"
        case .display: "Mac and screen stay on"
        }
    }
}

enum KeepAwake {
    nonisolated(unsafe) private static var assertion: IOPMAssertionID = 0
    nonisolated(unsafe) private static var held: KeepAwakeMode = .off

    static func apply(_ mode: KeepAwakeMode) {
        guard mode != held else { return }
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        held = .off
        guard mode != .off else { return }
        let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                                    : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                       "Agent Buddy: keep the Mac awake" as CFString, &id) == kIOReturnSuccess {
            assertion = id
            held = mode
        }
    }
}
