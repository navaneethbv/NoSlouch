public protocol HeadMotionProvider: AnyObject {
  /// Whether motion-capable headphones (AirPods Pro/3/Max, Beats Fit Pro) are
  /// present so a session can actually receive readings. Used to avoid a silent
  /// "monitoring" state with a dead sensor (BUG-2).
  var isDeviceMotionAvailable: Bool { get }
  var onReading: ((HeadMotionReading) -> Void)? { get set }
  var onConnectionChanged: ((Bool) -> Void)? { get set }
  var onError: ((String) -> Void)? { get set }

  func start()
  func stop()
}
