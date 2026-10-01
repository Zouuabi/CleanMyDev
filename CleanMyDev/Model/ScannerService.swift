import Foundation

class ScannerService {
    
    static let shared = ScannerService()
    
    // Paths to ignore during recursion
    private let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".idea", ".vscode", "venv",
        "Pictures", "Music", "Movies", "Applications", "Library" 
        // Library is handled explicitly for globals, we skip recursion to avoid loops
    ]
    
    func scan(roots: [URL], progressCallback: @escaping (String) -> Void) async -> [CleanableItem] {
        var foundItems: [CleanableItem] = []
        
        // 1. Scan Global Caches first (Fast)
        foundItems.append(contentsOf: scanGlobals())
        
        // 2. Scan User Directories
        for root in roots {
            let items = await scanDirectory(root, progressCallback: progressCallback)
            foundItems.append(contentsOf: items)
        }
        
        return foundItems
    }
    
    private func scanGlobals() -> [CleanableItem] {
        var items: [CleanableItem] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        // Global Gradle
        let gradleCache = home.appendingPathComponent(".gradle/caches")
        if let size = directorySize(gradleCache) {
            items.append(CleanableItem(path: gradleCache, category: .global, description: "Global Gradle Caches", size: size))
        }
        
        // Pub Cache
        let pubCache = home.appendingPathComponent(".pub-cache")
        if let size = directorySize(pubCache) {
            items.append(CleanableItem(path: pubCache, category: .global, description: "Global Pub Cache", size: size))
        }
        
        // CocoaPods
        let podsCache = home.appendingPathComponent("Library/Caches/CocoaPods")
        if let size = directorySize(podsCache) {
            items.append(CleanableItem(path: podsCache, category: .global, description: "Global CocoaPods Cache", size: size))
        }
        
        // DerivedData
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let size = directorySize(derivedData) {
            items.append(CleanableItem(path: derivedData, category: .global, description: "Xcode DerivedData", size: size))
        }
        
        return items
    }
    
    private func scanDirectory(_ root: URL, progressCallback: @escaping (String) -> Void) async -> [CleanableItem] {
        print("Scanning directory: \(root.path)")
        var items: [CleanableItem] = []
        let fileManager = FileManager.default
        
        // Create enumerator
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            print("ERROR: Failed to create enumerator for \(root.path) - Check Permissions!")
            return []
        }
        
        // Loop synchronously but yield to allow UI updates?
        // Since FileManager.enumerator is sync, we run this in a detached task if needed, but 'async' wrapper implies we might need to yield manually.
        // For strict performance in Swift, we should use GCD or just let it run.
        
        await Task.yield() 
        
        while let fileURL = enumerator.nextObject() as? URL {
            let filename = fileURL.lastPathComponent
            
            // Progress update check (throttle to every 50 files or so to avoid UI spam)
            // progressCallback(fileURL.path) 
            
            // Prune ignored directories
            if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                if ignoredDirectories.contains(filename) {
                    enumerator.skipDescendants()
                    continue
                }
                
                // --- Detection Logic ---
                
                // Flutter
                let pubspec = fileURL.appendingPathComponent("pubspec.yaml")
                if fileManager.fileExists(atPath: pubspec.path) {
                    // It's a Flutter/Dart project
                    // Check for build
                    let build = fileURL.appendingPathComponent("build")
                    if let size = directorySize(build) {
                        items.append(CleanableItem(path: build, category: .flutter, description: "Build Output", size: size))
                    }
                    
                    let dartTool = fileURL.appendingPathComponent(".dart_tool")
                    if let size = directorySize(dartTool) {
                        items.append(CleanableItem(path: dartTool, category: .flutter, description: ".dart_tool Cache", size: size))
                    }
                    
                   // Optimization: if we found a project, maybe skip deep scanning inside it?
                   // Often yes.
                   enumerator.skipDescendants()
                   continue
                }
                
                // iOS (Podfile)
                let podfile = fileURL.appendingPathComponent("Podfile")
                if fileManager.fileExists(atPath: podfile.path) {
                     let pods = fileURL.appendingPathComponent("Pods")
                     if let size = directorySize(pods) {
                        items.append(CleanableItem(path: pods, category: .ios, description: "CocoaPods", size: size))
                     }
                }
                
                // Android
                let gradleBuild = fileURL.appendingPathComponent("build.gradle")
                let gradleKts = fileURL.appendingPathComponent("build.gradle.kts")
                
                if fileManager.fileExists(atPath: gradleBuild.path) || fileManager.fileExists(atPath: gradleKts.path) {
                    
                    let gradleDir = fileURL.appendingPathComponent(".gradle")
                    if let size = directorySize(gradleDir) {
                        items.append(CleanableItem(path: gradleDir, category: .android, description: "Project Gradle Cache", size: size))
                    }
                    
                    let buildDir = fileURL.appendingPathComponent("build")
                    if let size = directorySize(buildDir) {
                        items.append(CleanableItem(path: buildDir, category: .android, description: "Build Output", size: size))
                    }
                    
                    enumerator.skipDescendants()
                    continue
                }
            }
        }
        
        return items
    }
    
    private func directorySize(_ url: URL) -> Int64? {
        // Fast approximation or deep scan?
        // Deep scan is needed for accurate size.
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) { return nil }
        
        // This can be slow.
        // For now, let's use a non-recursive shallow check or a proper deep check
        // "Keys to perform deep enumeration"
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return nil }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
               let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }
}
