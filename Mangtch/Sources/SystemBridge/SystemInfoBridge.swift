import Foundation
import IOKit.ps
import CoreAudio
import AudioToolbox
import CoreGraphics

// MARK: - Battery Info

struct BatteryInfo {
    let level: Int           // 0-100
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeToEmpty: Int?    // minutes
    let timeToFull: Int?     // minutes
    let cycleCount: Int
}

// MARK: - SystemInfoBridge

/// Free function used as CoreAudio property listener callback.
/// Must be a free function (not a closure or method) for C interop reliability.
private func volumePropertyListener(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        let bridge = SystemInfoBridge.shared
        let volume: Float
        if bridge.isMuted() {
            volume = 0
        } else {
            volume = bridge.getSystemVolume()
        }
        EventBus.shared.send(.hudTriggered(.volume, volume))
    }
    return noErr
}

final class SystemInfoBridge: ObservableObject {
    static let shared = SystemInfoBridge()

    @Published private(set) var battery: BatteryInfo?

    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval = 30 // idle: 30s
    private var defaultOutputID: AudioDeviceID = 0
    private var volumeListenerInstalled = false
    private var muteListenerInstalled = false
    private var virtualVolumeListenerInstalled = false
    private var lastBrightness: Float = -1
    private var brightnessTimer: Timer?

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        updateBatteryInfo()
        startPolling(interval: 30)
        installVolumeListener()
        startBrightnessPolling()
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        removeVolumeListener()
    }

    /// Adjust polling rate based on notch state
    func setPollingRate(_ interval: TimeInterval) {
        guard interval != pollingInterval else { return }
        pollingInterval = interval
        startPolling(interval: interval)
    }

    private func startPolling(interval: TimeInterval) {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateBatteryInfo()
        }
    }

    // MARK: - Battery

    func updateBatteryInfo() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any]
        else { return }

        let level = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let powerSource = desc[kIOPSPowerSourceStateKey] as? String
        let isPluggedIn = powerSource == kIOPSACPowerValue

        let rawTimeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
        let rawTimeToFull = desc[kIOPSTimeToFullChargeKey] as? Int

        // IOKit returns -1 for "calculating"
        let timeToEmpty = (rawTimeToEmpty ?? -1) > 0 ? rawTimeToEmpty : nil
        let timeToFull = (rawTimeToFull ?? -1) > 0 ? rawTimeToFull : nil

        // Cycle count from IORegistry
        let cycleCount = getCycleCount()

        battery = BatteryInfo(
            level: level,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            timeToEmpty: timeToEmpty,
            timeToFull: timeToFull,
            cycleCount: cycleCount
        )
    }

    private func getCycleCount() -> Int {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return 0 }
        defer { IOObjectRelease(service) }

        if let prop = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, nil, 0) {
            return prop.takeRetainedValue() as? Int ?? 0
        }
        return 0
    }

    // MARK: - System Volume

    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    func getSystemVolume() -> Float {
        guard let deviceID = getDefaultOutputDeviceID() else {
            NSLog("[SystemInfoBridge] Failed to get default output device")
            return 0
        }

        var volume: Float32 = 0
        var propertySize = UInt32(MemoryLayout<Float32>.size)

        // Strategy 1: VirtualMainVolume — works for ALL devices including AirPods/Bluetooth
        var vmAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &vmAddress) {
            let vmStatus = AudioObjectGetPropertyData(
                deviceID, &vmAddress, 0, nil, &propertySize, &volume
            )
            if vmStatus == noErr {
                return volume
            }
        }

        // Strategy 2: VolumeScalar master element (element 0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &propertySize, &volume
        )
        if volStatus == noErr && volume > 0 {
            return volume
        }

        // Strategy 3: Channel 1 (left)
        address.mElement = 1
        volStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &propertySize, &volume
        )
        if volStatus == noErr {
            return volume
        }

        // Strategy 4: Channel 2 (right)
        address.mElement = 2
        volStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &propertySize, &volume
        )
        return volStatus == noErr ? volume : 0
    }

    func isMuted() -> Bool {
        var defaultOutputID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &propertySize,
            &defaultOutputID
        )

        var muted: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(defaultOutputID, &address, 0, nil, &propertySize, &muted)
        return muted != 0
    }

    /// CoreDisplay private API function type for getting brightness
    private typealias GetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    /// Cached DisplayServices function pointer (preferred on modern macOS)
    private static var _dsGetBrightnessFunc: GetBrightnessFunc? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return nil
        }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else {
            return nil
        }
        return unsafeBitCast(sym, to: GetBrightnessFunc.self)
    }()

    /// Cached CoreDisplay function pointer (fallback)
    private static var _getBrightnessFunc: GetBrightnessFunc? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
            return nil
        }
        guard let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") else {
            dlclose(handle)
            return nil
        }
        return unsafeBitCast(sym, to: GetBrightnessFunc.self)
    }()

    func getScreenBrightness() -> Float {
        let displayID = CGMainDisplayID()

        // Strategy 1: DisplayServices private framework (most reliable on modern macOS)
        if let getBrightness = SystemInfoBridge._dsGetBrightnessFunc {
            var brightness: Float = 0
            let result = getBrightness(displayID, &brightness)
            if result == 0 {
                return brightness
            }
        }

        // Strategy 2: CoreDisplay private API
        if let getBrightness = SystemInfoBridge._getBrightnessFunc {
            var brightness: Float = 0
            let result = getBrightness(displayID, &brightness)
            if result == 0 {
                return brightness
            }
        }

        // Strategy 3: IODisplayGetFloatParameter fallback
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return 0.5 }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            var brightness: Float = 0
            let kr = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            if kr == kIOReturnSuccess {
                return brightness
            }
            service = IOIteratorNext(iterator)
        }

        return 0.5  // Final fallback
    }

    // MARK: - Volume Change Listener (CoreAudio)

    private func installVolumeListener() {
        guard let deviceID = getDefaultOutputDeviceID() else {
            NSLog("[SystemInfoBridge] Failed to get default output device for listener")
            return
        }

        defaultOutputID = deviceID
        NSLog("[SystemInfoBridge] Installing volume listeners on device %d", deviceID)

        // Listen on VirtualMainVolume (works for AirPods/Bluetooth)
        var vmAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let vmResult = AudioObjectAddPropertyListener(
            deviceID, &vmAddress, volumePropertyListener, nil
        )
        if vmResult == noErr {
            virtualVolumeListenerInstalled = true
            NSLog("[SystemInfoBridge] VirtualMainVolume listener installed")
        } else {
            NSLog("[SystemInfoBridge] Failed to install VirtualMainVolume listener: %d", vmResult)
        }

        // Listen on VolumeScalar channel 1 (for built-in speakers etc.)
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        let volResult = AudioObjectAddPropertyListener(
            deviceID, &volAddress, volumePropertyListener, nil
        )
        if volResult == noErr {
            volumeListenerInstalled = true
            NSLog("[SystemInfoBridge] VolumeScalar listener installed (channel 1)")
        } else {
            NSLog("[SystemInfoBridge] VolumeScalar listener not available on this device: %d", volResult)
        }

        // Listen for mute changes
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let muteResult = AudioObjectAddPropertyListener(
            deviceID, &muteAddress, volumePropertyListener, nil
        )
        if muteResult == noErr {
            muteListenerInstalled = true
            NSLog("[SystemInfoBridge] Mute listener installed")
        } else {
            NSLog("[SystemInfoBridge] Failed to install mute listener: %d", muteResult)
        }
    }

    private func removeVolumeListener() {
        guard defaultOutputID != 0 else { return }

        if virtualVolumeListenerInstalled {
            var vmAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(
                defaultOutputID, &vmAddress, volumePropertyListener, nil
            )
            virtualVolumeListenerInstalled = false
        }

        if volumeListenerInstalled {
            var volAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            AudioObjectRemovePropertyListener(
                defaultOutputID, &volAddress, volumePropertyListener, nil
            )
            volumeListenerInstalled = false
        }

        if muteListenerInstalled {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(
                defaultOutputID, &muteAddress, volumePropertyListener, nil
            )
            muteListenerInstalled = false
        }
    }

    // MARK: - Brightness Polling

    private func startBrightnessPolling() {
        brightnessTimer?.invalidate()
        lastBrightness = getScreenBrightness()

        // Poll brightness every 500ms — lightweight, only sends HUD when value changes
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = self.getScreenBrightness()
            if abs(current - self.lastBrightness) > 0.005 {
                self.lastBrightness = current
                NSLog("[SystemInfoBridge] Brightness changed: %f", current)
                EventBus.shared.send(.hudTriggered(.brightness, current))
            }
        }
    }
}
