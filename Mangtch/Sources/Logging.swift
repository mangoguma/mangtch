import Foundation
import os

/// Chrome-layer overflow signal. Fires when a widget's natural content width
/// exceeds its declared `preferredPanelWidth`, which would have caused panel
/// chrome to extend past the wings before the hard clamp was added.
let chromeLog = Logger(subsystem: "com.mangtch.chrome", category: "width")

/// Trace of `NotchViewModel.updatePanelDimensions` invocations — pairs with
/// `os_signpost` so width-change cadence is visible in Instruments.
let dimensionsLog = Logger(subsystem: "com.mangtch.viewmodel", category: "dimensions")
let dimensionsSignposter = OSSignposter(logger: dimensionsLog)
