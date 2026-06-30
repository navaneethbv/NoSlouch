public protocol HeadMotionProvider: AnyObject {
  var isAvailable: Bool { get }
  var onReading: ((HeadMotionReading) -> Void)? { get set }
  var onConnectionChanged: ((Bool) -> Void)? { get set }
  var onError: ((String) -> Void)? { get set }

  func start()
  func stop()
}
