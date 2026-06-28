import Foundation

func formatRate(_ bytesPerSec: Int64) -> String {
    let bps = Double(bytesPerSec * 8)
    if bps >= 1_000_000 { return String(format: "%.1f Mbit/s", bps / 1_000_000) }
    if bps >= 1_000 { return String(format: "%.0f kbit/s", bps / 1_000) }
    return "0 bit/s"
}

func formatBytes(_ bytes: Int64) -> String {
    let b = Double(bytes)
    if b >= 1024 * 1024 { return String(format: "%.1f МБ", b / (1024 * 1024)) }
    if b >= 1024 { return String(format: "%.0f КБ", b / 1024) }
    return "\(bytes) Б"
}
