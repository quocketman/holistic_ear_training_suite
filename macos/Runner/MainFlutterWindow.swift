import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let fixedSize = NSSize(width: 1920, height: 1080)
    self.setContentSize(fixedSize)
    self.contentMinSize = fixedSize
    self.contentMaxSize = fixedSize
    if let screen = self.screen {
      let screenFrame = screen.visibleFrame
      let x = (screenFrame.width - fixedSize.width) / 2 + screenFrame.origin.x
      let y = (screenFrame.height - fixedSize.height) / 2 + screenFrame.origin.y
      self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
