import Foundation
import IOKit.ps

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

final class SystemInfoBridge: ObservableObject {
    static let shared = SystemInfoBridge()

    @Published private(set) var battery: BatteryInfo?

    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval = 30 // idle: 30s

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        updateBatteryInfo()
        startPolling(interval: 30)
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
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
}
