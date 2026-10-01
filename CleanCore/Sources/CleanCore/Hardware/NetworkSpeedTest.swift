import Foundation

/// Download/upload throughput against Cloudflare's speed endpoints. Sends
/// random bytes up and discards bytes down; nothing identifying leaves the Mac.
public actor NetworkSpeedTest {
    public struct Result: Sendable, Equatable {
        public let downloadMbps: Double
        public let uploadMbps: Double
        public let latencyMs: Double
        public let date: Date
    }

    public enum Phase: Sendable, Equatable { case idle, latency, download(Double), upload(Double), done(Result), failed(String) }

    public init() {}

    public func run(onPhase: @Sendable @escaping (Phase) -> Void) async -> Result? {
        let session = URLSession(configuration: .ephemeral)
        do {
            onPhase(.latency)
            let t0 = Date()
            _ = try await session.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!)
            let latency = Date().timeIntervalSince(t0) * 1000

            let downBytes = 50_000_000
            let (stream, _) = try await session.bytes(from: URL(string: "https://speed.cloudflare.com/__down?bytes=\(downBytes)")!)
            var received = 0
            let start = Date()
            var lastReport = start
            for try await _ in stream {
                received += 1
                if received % 262_144 == 0, Date().timeIntervalSince(lastReport) > 0.2 {
                    lastReport = Date()
                    onPhase(.download(Double(received * 8) / Date().timeIntervalSince(start) / 1_000_000))
                }
            }
            let downMbps = Double(received * 8) / Date().timeIntervalSince(start) / 1_000_000

            let upBytes = 20_000_000
            var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
            req.httpMethod = "POST"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let payload = Data((0..<upBytes).map { _ in UInt8.random(in: 0...255) })
            onPhase(.upload(0))
            let upStart = Date()
            _ = try await session.upload(for: req, from: payload)
            let upMbps = Double(upBytes * 8) / Date().timeIntervalSince(upStart) / 1_000_000

            let result = Result(downloadMbps: downMbps, uploadMbps: upMbps, latencyMs: latency, date: Date())
            onPhase(.done(result))
            return result
        } catch {
            onPhase(.failed(error.localizedDescription))
            return nil
        }
    }
}
