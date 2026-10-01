import Foundation

/// The module roster, in the order Smart Care runs them.
public enum AllModules {
    public static func make() -> [ScanModule] {
        [
            SystemJunkModule(),
            DevJunkModule(),
            DockerModule(),
            SimulatorModule(),
            PrivacyModule(),
            MalwareModule(),
            TrashModule(),
            LargeFilesModule(),
        ]
    }

    public static func virtualCleaners() -> [VirtualCleaner] {
        [DockerService.shared, SimulatorService.shared]
    }
}
