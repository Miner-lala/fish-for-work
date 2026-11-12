import AppKit
import ServiceManagement
import WebKit

/// Hosts the page in a window, and owns everything the page cannot do itself:
/// the data file, the menu bar item, reminders and opening at login.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private let store = Store()
    private let notifier = Notifier()
    private var window: NSWindow!
    private var webView: WKWebView!
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private var seconds = 0
    private var status: [String: Any] = [:]
    private var shownWorking: Bool?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.log("launched")
        buildMainMenu()
        buildStatusItem()
        buildWindow()
        notifier.setUp(
            log: { [weak self] line in self?.store.log(line) },
            onAction: { [weak self] action in self?.handleNotification(action) }
        )
        registerLoginItemOnFirstRun()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.everySecond() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window and page

    private func buildWindow() {
        let controller = WKUserContentController()
        controller.add(MessageRelay(self), name: "xyg")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "小鱼干打工记"
        window.minSize = NSSize(width: 460, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("XiaoYuGanMain")
        loadPage()
        showWindow()
    }

    /// (Re)loads the page with the latest saved data injected before any of its scripts run.
    private func loadPage() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let boot = store.bootJSON() ?? "null"
        controller.addUserScript(WKUserScript(source: "window.__XYG_APP__ = true; window.__XYG_BOOT__ = \(boot);",
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html") else {
            store.log("index.html is missing from the app bundle")
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadPage() { loadPage() }

    /// Closing the window only hides it; the app keeps timing in the menu bar.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        store.log("page process ended, reloading")
        loadPage()
    }

    // MARK: Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            if let json = body["payload"] as? String { store.save(json) }
        case "status":
            if let payload = body["payload"] as? [String: Any] { apply(status: payload) }
        case "reminders":
            if let items = body["payload"] as? [[String: Any]] { store.log("reminders scheduled: \(notifier.schedule(items))") }
        case "log":
            if let line = body["payload"] as? String { store.log("page: \(line)") }
        default:
            break
        }
    }

    private func runPage(_ action: String) {
        webView?.evaluateJavaScript("window.xygAction && window.xygAction('\(action)')", completionHandler: nil)
    }

    private func apply(status payload: [String: Any]) {
        status = payload
        let working = (payload["working"] as? Bool) ?? false
        if working != shownWorking {
            shownWorking = working
            rebuildStatusMenu()
            if working, activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "工作计时")
            } else if !working, let token = activity {
                ProcessInfo.processInfo.endActivity(token)
                activity = nil
            }
        }
        refreshStatusTitle()
    }

    private func everySecond() {
        refreshStatusTitle()
        seconds += 1
        if seconds % 15 == 0 {
            reportIdle()
            runPage("tick")
        }
    }

    /// Seconds since the last keyboard or mouse input anywhere on the Mac; the page uses it to notice you have left.
    private func reportIdle() {
        guard let any = CGEventType(rawValue: ~0) else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
        webView?.evaluateJavaScript("window.xygIdle && window.xygIdle(\(Int(idle)))", completionHandler: nil)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "小鱼干打工记") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        rebuildStatusMenu()
        refreshStatusTitle()
    }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        var text = ""
        if (status["working"] as? Bool) == true, let since = (status["since"] as? NSNumber)?.doubleValue {
            let total = max(0, Int(Date().timeIntervalSince1970 - since / 1000))
            text = String(format: " 工作中 %d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
        } else if let next = status["next"] as? [String: Any], let label = next["label"] as? String, !label.isEmpty {
            text = " " + label
        }
        if button.image == nil { text = "🐟" + text }
        if button.title != text { button.title = text }
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("打开小鱼干打工记", #selector(showWindow)))
        menu.addItem(.separator())
        let working = (status["working"] as? Bool) ?? false
        menu.addItem(menuItem(working ? "结束工作" : "开始工作", #selector(toggleWork)))
        menu.addItem(.separator())
        let login = menuItem("开机自动打开", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出小鱼干打工记", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleWork() {
        runPage(((status["working"] as? Bool) ?? false) ? "clockOut" : "clockIn")
    }

    private func handleNotification(_ action: String) {
        switch action {
        case "clockIn", "clockOut": runPage(action)
        default: showWindow()
        }
    }

    // MARK: Open at login

    private func registerLoginItemOnFirstRun() {
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
            store.log("open at login: \(SMAppService.mainApp.status.rawValue)")
        } catch {
            store.log("open at login failed: \(error.localizedDescription)")
        }
        rebuildStatusMenu()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            store.log("open at login toggle failed: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        rebuildStatusMenu()
    }

    // MARK: Main menu

    private func buildMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于小鱼干打工记", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏小鱼干打工记", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出小鱼干打工记", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(holder(appMenu))

        let edit = NSMenu(title: "编辑")
        edit.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(holder(edit))

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem("重新载入页面", #selector(reloadPage), key: "r"))
        main.addItem(holder(windowMenu))
        NSApp.mainMenu = main
    }

    private func holder(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}

/// Keeps the web view's content controller from retaining the app delegate.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
