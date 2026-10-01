import XCTest
@testable import CleanCore

final class HardwareSmokeTests: XCTestCase {
    func testSensorsSnapshotReadsSomething() {
        let s = Sensors.snapshot()
        print("SENSORS cpuAvg=\(s.cpuAverage ?? -1) cpuMax=\(s.cpuMax ?? -1) gpuMax=\(s.gpuMax ?? -1) mem=\(s.memory ?? -1) fans=\(s.fans.map { "\(Int($0.actual))rpm manual=\($0.isManual)" }) extra=\(s.readings)")
        XCTAssertTrue(SMC.shared.isOpen)
    }
}
