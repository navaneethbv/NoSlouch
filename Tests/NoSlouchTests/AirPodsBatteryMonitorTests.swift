import XCTest

@testable import NoSlouch

final class AirPodsBatteryMonitorTests: XCTestCase {
  func testParseBatteryOutputWithAirPodsConnected() {
    let output = """
                  Case Battery Level: 100%
                  Left Battery Level: 92%
                  Right Battery Level: 91%
      """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output)

    XCTAssertEqual(info.leftPercentage, 92)
    XCTAssertEqual(info.rightPercentage, 91)
    XCTAssertEqual(info.casePercentage, 100)
    XCTAssertTrue(info.hasData)
  }

  func testParseBatteryOutputWithPartialData() {
    let output = """
                  Left Battery Level: 45%
      """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output)

    XCTAssertEqual(info.leftPercentage, 45)
    XCTAssertNil(info.rightPercentage)
    XCTAssertNil(info.casePercentage)
    XCTAssertTrue(info.hasData)
  }

  func testParseBatteryOutputScopesToAirPodsSection() {
    // A stray battery line under a different device must be ignored; only the
    // AirPods section's levels are read (NB-5).
    let output = """
          Some Other Headset:
              Left Battery Level: 5%
          Navaneeth's AirPods Pro:
              Case Battery Level: 80%
              Left Battery Level: 92%
              Right Battery Level: 91%
      """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output)

    XCTAssertEqual(info.leftPercentage, 92)
    XCTAssertEqual(info.rightPercentage, 91)
    XCTAssertEqual(info.casePercentage, 80)
  }

  func testParseBatteryOutputWithNoData() {
    let output = """
                Address: 9C:FC:28:39:0C:B6
                Vendor ID: 0x004C
                Product ID: 0x200E
                Case Version: 1.4.1
                Firmware Version: 6F21
      """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output)

    XCTAssertNil(info.leftPercentage)
    XCTAssertNil(info.rightPercentage)
    XCTAssertNil(info.casePercentage)
    XCTAssertFalse(info.hasData)
  }
}
