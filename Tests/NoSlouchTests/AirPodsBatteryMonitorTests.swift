import XCTest

@testable import NoSlouch

final class AirPodsBatteryMonitorTests: XCTestCase {
  func testParseBatteryOutputWithAirPodsConnected() {
    let output = """
    {
      "SPBluetoothDataType" : [
        {
          "device_not_connected" : [
            {
              "Navaneeth’s AirPods Pro" : {
                "device_batteryLevelCase" : "100%",
                "device_batteryLevelLeft" : "92%",
                "device_batteryLevelRight" : "91%"
              }
            }
          ]
        }
      ]
    }
    """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output, deviceName: "Navaneeth’s AirPods Pro")

    XCTAssertEqual(info.leftPercentage, 92)
    XCTAssertEqual(info.rightPercentage, 91)
    XCTAssertEqual(info.casePercentage, 100)
    XCTAssertTrue(info.hasData)
  }

  func testParseBatteryOutputWithPartialData() {
    let output = """
    {
      "SPBluetoothDataType" : [
        {
          "device_connected" : [
            {
              "Navaneeth’s AirPods Pro" : {
                "device_batteryLevelLeft" : "45%"
              }
            }
          ]
        }
      ]
    }
    """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output, deviceName: "Navaneeth’s AirPods Pro")

    XCTAssertEqual(info.leftPercentage, 45)
    XCTAssertNil(info.rightPercentage)
    XCTAssertNil(info.casePercentage)
    XCTAssertTrue(info.hasData)
  }

  func testParseBatteryOutputWithNoData() {
    let output = """
    {
      "SPBluetoothDataType" : [
        {
          "device_connected" : [
            {
              "Other Device" : {
                "device_address" : "9C:FC:28:39:0C:B6"
              }
            }
          ]
        }
      ]
    }
    """
    let monitor = AirPodsBatteryMonitor()
    let info = monitor.parseBatteryOutput(output, deviceName: "Navaneeth’s AirPods Pro")

    XCTAssertNil(info.leftPercentage)
    XCTAssertNil(info.rightPercentage)
    XCTAssertNil(info.casePercentage)
    XCTAssertFalse(info.hasData)
  }

  func testShellRunnerInjectionAndPolling() {
    let output = """
    {
      "SPBluetoothDataType" : [
        {
          "device_connected" : [
            {
              "MyPod" : {
                "device_batteryLevelLeft" : "80%"
              }
            }
          ]
        }
      ]
    }
    """
    let expectation = XCTestExpectation(description: "onBatteryUpdate called")
    let monitor = AirPodsBatteryMonitor(shellRunner: { output })
    monitor.onBatteryUpdate = { info in
      XCTAssertEqual(info.leftPercentage, 80)
      expectation.fulfill()
    }
    monitor.start(deviceName: "MyPod")
    wait(for: [expectation], timeout: 2.0)
    monitor.stop()
  }
}

