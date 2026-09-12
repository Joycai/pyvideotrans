import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 任务表有七列，窗口再窄列就挤没了。
    self.contentMinSize = NSSize(width: 1100, height: 700)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // nib 里那个 800×600 的 frame 是在 awakeFromNib 返回之后才落地的，
    // 所以这里必须推迟到下一个 runloop 再设尺寸，否则会被它覆盖掉
    // （然后被 contentMinSize 夹回最小值）。
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      // 设计稿是 1440×900，屏幕放不下就按可用区域收。
      var size = NSSize(width: 1440, height: 900)
      if let visible = (self.screen ?? NSScreen.main ?? NSScreen.screens.first)?
        .visibleFrame
      {
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height - 28)
      }
      self.setContentSize(size)
      self.center()
    }
  }
}
