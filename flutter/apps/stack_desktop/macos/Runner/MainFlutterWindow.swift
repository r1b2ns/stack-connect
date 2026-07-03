import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app name now lives in the in-app top bar (see HomeShell's title bar),
    // so hide the native window title text to avoid showing "Stack Connect"
    // twice. The title bar chrome and traffic-light buttons stay intact; we
    // deliberately do not switch to fullSizeContentView to avoid layout shifts.
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
