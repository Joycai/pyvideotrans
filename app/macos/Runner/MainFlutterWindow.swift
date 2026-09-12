import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 设计稿是 1440×900。默认开这么大，并设一个最小尺寸 ——
    // 任务表有七列，窗口再窄列就挤没了。
    let designSize = NSSize(width: 1440, height: 900)
    self.contentMinSize = NSSize(width: 1100, height: 700)

    var frame = self.frame
    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let width = min(designSize.width, visible.width)
      let height = min(designSize.height, visible.height)
      frame = NSRect(
        x: visible.minX + (visible.width - width) / 2,
        y: visible.minY + (visible.height - height) / 2,
        width: width,
        height: height
      )
    }
    self.setFrame(frame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
