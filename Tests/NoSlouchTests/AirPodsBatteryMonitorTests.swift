import XCTest

@testable import NoSlouch

final class AirPodsBatteryMonitorTests: XCTestCase {
  private func json(_ string: String) -> Data {
    Data(string.utf8)
  }

  func testParseBatteryJSONWithAirPodsConnected() {
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {
                "Alex's AirPods Pro": {
                  "device_batteryLevelLeft": "92%",
                  "device_batteryLevelRight": "91%",
                  "device_batteryLevelCase": "100%",
                  "device_minorType": "Headphones"
                }
              }
            ]
          }
        ]
      }
      """)
    let info = AirPodsBatteryMonitor.parseBatteryJSON(data)

    XCTAssertEqual(info?.leftPercentage, 92)
    XCTAssertEqual(info?.rightPercentage, 91)
    XCTAssertEqual(info?.casePercentage, 100)
    XCTAssertEqual(info?.hasData, true)
  }

  func testParseBatteryJSONWithPartialData() {
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {"AirPods": {"device_batteryLevelLeft": "45%"}}
            ]
          }
        ]
      }
      """)
    let info = AirPodsBatteryMonitor.parseBatteryJSON(data)

    XCTAssertEqual(info?.leftPercentage, 45)
    XCTAssertNil(info?.rightPercentage)
    XCTAssertNil(info?.casePercentage)
  }

  func testParseBatteryJSONPrefersAirPodsOverOtherBudDevices() {
    // Another battery-reporting headset must not shadow the AirPods (NB-13),
    // regardless of device order.
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {"Some Other Headset": {"device_batteryLevelLeft": "5%", "device_batteryLevelRight": "6%"}},
              {"Beats Fit Pro": {"device_batteryLevelLeft": "92%", "device_batteryLevelRight": "91%"}}
            ]
          }
        ]
      }
      """)
    let info = AirPodsBatteryMonitor.parseBatteryJSON(data)

    XCTAssertEqual(info?.leftPercentage, 92)
    XCTAssertEqual(info?.rightPercentage, 91)
  }

  func testParseBatteryJSONFallsBackToAnyBudLikeDevice() {
    // A renamed bud device (no airpods/beats in the name) still reports L/R
    // levels; better to show it than nothing — but only bud-like devices count.
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {"Nav's Buds": {"device_batteryLevelLeft": "70%", "device_batteryLevelRight": "68%"}}
            ]
          }
        ]
      }
      """)
    let info = AirPodsBatteryMonitor.parseBatteryJSON(data)

    XCTAssertEqual(info?.leftPercentage, 70)
    XCTAssertEqual(info?.rightPercentage, 68)
  }

  func testParseBatteryJSONIgnoresDevicesWithoutBudLevels() {
    // A mouse reporting a single battery level (no left/right) is not AirPods.
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {"Magic Mouse": {"device_batteryLevel": "40%"}}
            ]
          }
        ]
      }
      """)
    XCTAssertNil(AirPodsBatteryMonitor.parseBatteryJSON(data))
  }

  func testParseBatteryJSONWithMalformedInputReturnsNil() {
    XCTAssertNil(AirPodsBatteryMonitor.parseBatteryJSON(json("not json at all")))
    XCTAssertNil(AirPodsBatteryMonitor.parseBatteryJSON(json("{\"unexpected\": true}")))
  }

  func testInjectedFetcherDrivesUpdatesWithoutSpawningProcesses() {
    let data = json(
      """
      {
        "SPBluetoothDataType": [
          {
            "device_connected": [
              {"AirPods Pro": {"device_batteryLevelLeft": "50%", "device_batteryLevelRight": "49%"}}
            ]
          }
        ]
      }
      """)
    let monitor = AirPodsBatteryMonitor(fetchRawOutput: { data })
    let expectation = expectation(description: "battery update delivered")
    monitor.onBatteryUpdate = { info in
      XCTAssertEqual(info.leftPercentage, 50)
      expectation.fulfill()
      monitor.stop()
    }

    monitor.start()
    waitForExpectations(timeout: 2)
  }
}
