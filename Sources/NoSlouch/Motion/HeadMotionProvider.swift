public protocol HeadMotionProvider: AnyObject {
  var onReading: ((HeadMotionReading) -> Void)? { get set }
  var onConnectionChanged: ((Bool) -> Void)? { get set }

  func start()
  func stop()
}
