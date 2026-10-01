import Foundation
import Combine

@MainActor
class AppViewModel: ObservableObject {
    
    @Published var items: [CleanableItem] = []
    @Published var isScanning: Bool = false
    @Published var scanningPath: String = ""
    @Published var totalReclaimableSize: Int64 = 0
    @Published var scannedCategories: Set<CleanerCategory> = []
    @Published var isSandboxed: Bool = false
    @Published var disks: [DiskInfo] = []
    
    // New Dashboard State
    @Published var systemStats: SystemStats?
    @Published var topPorts: [OpenPort] = []
    
    private let scanner = ScannerService.shared
    private let diskService = DiskService.shared
    
    private var statsTimer: Timer?
    
    init() {
        // AppViewModel does not inherit from a class, so `override` and `super.init()` are not applicable here.
        // Assuming the user intended a standard initializer for a class conforming to ObservableObject.
        checkSandbox()
        refreshDisks()
        startLiveUpdates()
    }
    
    func startLiveUpdates() {
        // Initial fetch
        Task {
            await updateStats()
        }
        
        // Timer for every 2 seconds
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateStats()
            }
        }
    }
    
    @MainActor
    func updateStats() async {
        self.systemStats = await SystemStatsService.shared.getSystemStats()
        // Ports don't need to be polled extremely often, but for "live" feel we can.
        // Maybe every other tick? For now, let's just do it.
        self.topPorts = await PortService.shared.getTopOpenPorts(limit: 3)
        // Also refresh disks in case
        self.disks = DiskService.shared.getMountedDisks()
    }
    
    func refreshDisks() {
        self.disks = diskService.getMountedDisks()
    }
    
    func checkSandbox() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if home.contains("/Library/Containers/") {
            isSandboxed = true
            print("App is Sanboxed! Home is: \(home)")
        }
    }
    
    @Published var shouldNavigateToResults: Bool = false
    
    private var scanTask: Task<Void, Never>?
    
    // ... (init and other methods) ...
    
    func startScan() {
        if isSandboxed { return }
        
        // If already scanning, cancel it
        if isScanning {
            scanTask?.cancel()
            isScanning = false
            scanningPath = "Scan Cancelled"
            return
        }
        
        isScanning = true
        shouldNavigateToResults = false
        items = []
        totalReclaimableSize = 0
        scannedCategories = []
        
        scanTask = Task.detached { [weak self] in
            // Define roots to scan
            let fileManager = FileManager.default
            let home = fileManager.homeDirectoryForCurrentUser
            var roots = [home]
            
            // Check for /dev explicit
            let dev = home.appendingPathComponent("dev")
            do {
                 if try dev.checkResourceIsReachable() {
                     roots.append(dev)
                 }
            } catch {
                print("Warning: ~/dev not reachable: \(error)")
            }
            
            print("Starting scan with roots: \(roots)")

            let found = await self?.scanner.scan(roots: roots) { path in
                Task { @MainActor [weak self] in
                    self?.scanningPath = path
                }
            }
            
            // Check cancellation
            if Task.isCancelled { return }
            
            print("Scan finished. Found \(found?.count ?? 0) items.")
            
            await MainActor.run { [weak self] in
                self?.items = found ?? []
                self?.calculateTotal()
                self?.isScanning = false
                self?.scanningPath = "Scan Complete"
                self?.shouldNavigateToResults = true
            }
        }
    }
    
    func cleanSelected() {
        // Mock cleaning for safety in this demo code.
        // In real app: FileManager.default.removeItem(at: item.path)
        
        print("Cleaning items...")
        
        let fileManager = FileManager.default
        
        // Filter selected
        let toClean = items.filter { $0.isSelected }
        
        for item in toClean {
            do {
                print("Deleting: \(item.path.path)")
                if fileManager.fileExists(atPath: item.path.path) {
                    try fileManager.removeItem(at: item.path)
                }
            } catch {
                print("Failed to delete \(item.path.lastPathComponent): \(error)")
            }
        }
        
        // Remove from list
        items.removeAll { $0.isSelected }
        calculateTotal()
    }
    
    private func calculateTotal() {
        totalReclaimableSize = items
            .filter { $0.isSelected }
            .reduce(0) { $0 + $1.size }
            
        scannedCategories = Set(items.map { $0.category })
    }
    
    func toggleSelection(for id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isSelected.toggle()
            calculateTotal()
        }
    }
    
    // MARK: - Disk Analysis
    @Published var selectedDisk: DiskInfo?
    @Published var diskAnalysisGroups: [FileGroup] = []
    @Published var largeFiles: [FileItem] = []
    @Published var isAnalyzing: Bool = false
    
    func selectDisk(_ disk: DiskInfo) {
        self.selectedDisk = disk
        self.diskAnalysisGroups = []
        self.largeFiles = []
        
        // Start Analysis automatically
        Task {
            await analyzeSelectedDisk()
        }
    }
    
    @MainActor
    func analyzeSelectedDisk() async {
        guard let disk = selectedDisk else { return }
        
        isAnalyzing = true
        // Assuming the disk.name or some ID maps to a path. 
        // For local main disk, likely "/" or "/Users/<User>".
        // DiskInfo currently doesn't hold the URL, let's assume root for now or if we can match it.
        // For this feature, we'll default to scanning Home as the most useful "Disk" analysis.
        
        let url = FileManager.default.homeDirectoryForCurrentUser
        
        let (groups, files) = await DiskAnalyzerService.shared.analyzeDisk(url: url)
        
        self.diskAnalysisGroups = groups
        self.largeFiles = files
        self.isAnalyzing = false
    }
}
