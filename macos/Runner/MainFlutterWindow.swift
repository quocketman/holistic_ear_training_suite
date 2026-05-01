import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Initial size 1920x1080, but resizable. Set a sensible minimum.
    let initialSize = NSSize(width: 1920, height: 1080)
    self.setContentSize(initialSize)
    self.contentMinSize = NSSize(width: 800, height: 600)
    self.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
    self.styleMask.insert(.resizable)

    if let screen = self.screen {
      let screenFrame = screen.visibleFrame
      let x = (screenFrame.width - initialSize.width) / 2 + screenFrame.origin.x
      let y = (screenFrame.height - initialSize.height) / 2 + screenFrame.origin.y
      self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
