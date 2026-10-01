import Foundation

struct CleanableItem: Identifiable, Hashable {
    let id = UUID()
    let path: URL
    let category: CleanerCategory
    let description: String
    let size: Int64
    var isSelected: Bool = true
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum CleanerCategory: String, CaseIterable, Hashable {
    case flutter = "Flutter"
    case ios = "iOS"
    case android = "Android"
    case global = "Global"
    
    var icon: String {
        switch self {
        case .flutter: return "paperplane.fill" // SF Symbol for Flutter-ish
        case .ios: return "applelogo"
        case .android: return "android" // Custom or use something generic like "shippingbox" if android not avail in SF Symbols
        case .global: return "globe"
        }
    }
    
    var colorHex: String {
        switch self {
        case .flutter: return "#02569B"
        case .ios: return "#000000"
        case .android: return "#3DDC84"
        case .global: return "#8E8E93"
        }
    }
}
