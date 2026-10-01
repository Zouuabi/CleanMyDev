import Foundation

struct DiskInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    
    var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }
    
    var percentageUsed: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
    
    var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }
}

class DiskService {
    static let shared = DiskService()
    
    func getMountedDisks() -> [DiskInfo] {
        let fileManager = FileManager.default
        // We only want local volumes that are visible (not hidden system mounts)
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        
        guard let mountedVolumeURLs = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        
        var disks: [DiskInfo] = []
        
        for url in mountedVolumeURLs {
            // Filter out network drives or weird mounts if needed
            // For now, accept anything that reports capacity
            
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity,
                  total > 0 else {
                continue
            }
            
            // Optional: Filter common read-only helper volumes if needed
            // "Preboot", "Recovery", "VM" often appear but are hidden by options typically.
            
            disks.append(DiskInfo(name: name, totalCapacity: Int64(total), availableCapacity: Int64(available)))
        }
        
        return disks
    }
}
