import Foundation

/// Pure decision: given a project, the user's overrides, and thresholds,
/// produce a status and a one-line reason. No filesystem access.
public enum ProjectClassifier {
    public static func decide(
        _ project: Project,
        registry: ProjectRegistry,
        settings: CleanSettings,
        now: Date = Date()
    ) -> ProjectDecision {
        if let o = registry.override(for: project, now: now) {
            switch o.status {
            case .pinned:
                let until = o.until.map { " until \(Self.short($0))" } ?? ""
                return ProjectDecision(status: .pinned, reason: "Pinned by you\(until)", isOverride: true, pinnedUntil: o.until)
            case .cleanable:
                return ProjectDecision(status: .cleanable, reason: "Marked cleanable by you", isOverride: true)
            default:
                break
            }
        }

        if project.signals.runningContainers > 0 {
            let n = project.signals.runningContainers
            return ProjectDecision(status: .active, reason: "\(n) Docker container\(n == 1 ? "" : "s") running")
        }
        if project.signals.devServerRunning {
            return ProjectDecision(status: .active, reason: "A dev server is running from this folder")
        }
        if project.signals.openInEditor {
            return ProjectDecision(status: .active, reason: "A terminal or editor is open in this folder")
        }

        guard let days = project.daysSinceActivity(now: now) else {
            return ProjectDecision(status: .idle, reason: "No activity date could be read")
        }
        let source = project.activitySource
        if days < settings.activeDays {
            return ProjectDecision(status: .active, reason: "\(source) \(Self.daysPhrase(days))")
        }
        if days < settings.dormantDays {
            return ProjectDecision(status: .idle, reason: "\(source) \(Self.daysPhrase(days))")
        }
        return ProjectDecision(status: .dormant, reason: "Untouched for \(days) days")
    }

    static func daysPhrase(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "yesterday"
        default: "\(days) days ago"
        }
    }

    static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
