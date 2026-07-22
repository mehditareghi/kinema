import KinemaCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.pwr_mgt
#endif

enum ScreenWakeLock {
    #if os(macOS)
    private static var displaySleepAssertionID: IOPMAssertionID = 0
    #endif

    static func setPreventSleep(_ enabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = enabled
        #elseif os(macOS)
        if enabled {
            guard displaySleepAssertionID == 0 else { return }
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Kinema playback" as CFString,
                &displaySleepAssertionID
            )
        } else if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        #endif
    }

    static func apply(playerVisible: Bool, state: PlayerState) {
        let shouldPreventSleep = playerVisible && state.isActive && state != .paused
        setPreventSleep(shouldPreventSleep)
    }
}
