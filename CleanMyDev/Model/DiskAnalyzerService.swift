import Foundation

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let path: URL
    let type: FileType
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum FileType: String, CaseIterable {
    case video = "Video"
    case image = "Image"
    case audio = "Audio"
    case archive = "Archive"
    case document = "Document"
    case app = "App"
    case other = "Other"
    
    var colorHex: String {
        switch self {
        case .video: return "FF00CC" // Neon Pink
        case .image: return "00F5FF" // Neon Blue
        case .audio: return "FFFF00" // Yellow
        case .archive: return "FFA500" // Orange
        case .document: return "FFFFFF" // White
        case .app: return "39FF14" // Neon Green
        case .other: return "808080" // Gray
        }
    }
    
    init(extension: String) {
        switch `extension`.lowercased() {
        case "mp4", "mov", "avi", "mkv", "webm": self = .video
        case "jpg", "jpeg", "png", "gif", "heic", "svg": self = .image
        case "mp3", "wav", "aac", "flac", "m4a": self = .audio
        case "zip", "rar", "7z", "tar", "gz": self = .archive
        case "pdf", "doc", "docx", "txt", "md": self = .document
        case "app", "exe", "dmg": self = .app
        default: self = .other
        }
    }
}

struct FileGroup: Identifiable {
    let id = UUID()
    let type: FileType
    var totalSize: Int64
    var count: Int
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

class DiskAnalyzerService {
    static let shared = DiskAnalyzerService()
    
    func analyzeDisk(url: URL) async -> (groups: [FileGroup], largeFiles: [FileItem]) {
        // We will scan the User's Home directory as a proxy for "Disk Analysis" 
        // because scanning the entire root volume happens to include System files 
        // which use a lot of space but are unreadable/unactionable.
        // If the url provided is actually the root volume, we switch to home for relevancy.
        
        let targetURL: URL
        if url.path == "/" {
            targetURL = FileManager.default.homeDirectoryForCurrentUser
        } else {
            targetURL = url
        }
        
        var groups: [FileType: Int64] = [:]
        var fileCounts: [FileType: Int] = [:]
        var topFiles: [FileItem] = []
        
        // Initialize maps
        for type in FileType.allCases {
            groups[type] = 0
            fileCounts[type] = 0
        }
        
        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        // Run on background thread
        await Task.yield()
        
        if let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: options) {
            
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { break }
                
                do {
                    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    
                    if let isFile = values.isRegularFile, isFile, let size = values.fileSize {
                        let size64 = Int64(size)
                        let ext = fileURL.pathExtension
                        let type = FileType(extension: ext)
                        
                        // Update Group Stats
                        groups[type, default: 0] += size64
                        fileCounts[type, default: 0] += 1
                        
                        // Track Top Files (Optimize by only keeping top 50 sorted)
                        // Heuristic: Only consider files > 50MB for the "Top" list to avoid massive sorting overhead
                        if size64 > 50 * 1024 * 1024 {
                            let item = FileItem(name: fileURL.lastPathComponent, size: size64, path: fileURL, type: type)
                            topFiles.append(item)
                        }
                    }
                } catch {
                    // Access denied or other error, skip
                }
            }
        }
        
        // Final sort and reduce
        let sortedFiles = topFiles.sorted { $0.size > $1.size }.prefix(50).map { $0 }
        
        var finalGroups: [FileGroup] = []
        for (type, size) in groups {
            finalGroups.append(FileGroup(type: type, totalSize: size, count: fileCounts[type] ?? 0))
        }
        finalGroups.sort { $0.totalSize > $1.totalSize }
        
        return (finalGroups, sortedFiles)
    }
}
