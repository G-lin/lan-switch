import AppKit

// MARK: - 常量配置
private let kAdapterName = "以太网"      // 要控制的网卡名称，可根据需要修改
private let kStatusUpdateInterval: TimeInterval = 3.0  // 状态同步间隔（秒）

// MARK: - 应用状态
private var statusItem: NSStatusItem!
private var statusTimer: Timer?
private var isEnabled = false

// MARK: - 程序入口
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 设置应用为 UI Element（后台运行，不出现在 Dock）
app.hide(nil)

// 创建状态栏项
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

// 配置菜单
let menu = NSMenu()

// 切换以太网
let toggleItem = NSMenuItem(title: "切换以太网", action: #selector(toggleEthernet), keyEquivalent: "")
toggleItem.target = self
menu.addItem(toggleItem)

// 分隔线
menu.addItem(NSMenuItem.separator())

// 当前状态（不可点击，只读）
let statusItem2 = NSMenuItem(title: "当前状态: 加载中...", action: nil, keyEquivalent: "")
statusItem2.isEnabled = false
statusItem2.tag = 100
menu.addItem(statusItem2)

// 分隔线
menu.addItem(NSMenuItem.separator())

// 开机自启
let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
loginItem.target = self
loginItem.tag = 101
menu.addItem(loginItem)

// 退出
let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "")
quitItem.target = self
menu.addItem(quitItem)

statusItem.menu = menu

// 初始化：获取当前状态并更新图标
updateStatus()
updateLoginItemState()

// 启动定时器，每 kStatusUpdateInterval 秒同步一次状态
statusTimer = Timer.scheduledTimer(withTimeInterval: kStatusUpdateInterval, repeats: true) { [weak self] _ in
    self?.updateStatus()
}

// 保持应用运行
app.run()

// MARK: - 功能实现

/// 获取以太网状态
private func getEthernetStatus() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    task.arguments = ["-getnetworkserviceenabled", kAdapterName]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "Enabled"
    } catch {
        print("获取网络状态失败: \(error)")
        return false
    }
}

/// 切换以太网状态
@objc private func toggleEthernet() {
    let targetState = !isEnabled
    let action = targetState ? "enable" : "disable"
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    task.arguments = ["-\(action)networkservice", kAdapterName]
    
    // networksetup 需要管理员权限，会弹出认证对话框
    // 使用 /usr/bin/osascript 显示认证对话框
    let script = """
    do shell script "/usr/sbin/networksetup -\(action)networkservice '\(kAdapterName)'" with administrator privileges
    """
    
    let osascript = Process()
    osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osascript.arguments = ["-e", script]
    
    do {
        try osascript.run()
        osascript.waitUntilExit()
        
        // 更新状态
        DispatchQueue.main.async { [weak self] in
            self?.updateStatus()
            self?.showNotification(enabled: targetState)
        }
    } catch {
        // 用户可能取消了认证
        print("切换失败或已取消: \(error)")
    }
}

/// 更新状态栏图标和菜单文字
private func updateStatus() {
    isEnabled = getEthernetStatus()
    
    // 更新图标
    if let button = statusItem.button {
        button.image = createStatusIcon(enabled: isEnabled)
    }
    
    // 更新菜单中的状态文字
    if let menu = statusItem.menu, let statusMenuItem = menu.item(withTag: 100) {
        let statusText = isEnabled ? "当前状态: 已启用" : "当前状态: 已禁用"
        statusMenuItem.title = statusText
    }
}

/// 创建状态图标
private func createStatusIcon(enabled: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let circleSize: CGFloat = 14
        let circleRect = NSRect(
            x: (rect.width - circleSize) / 2,
            y: (rect.height - circleSize) / 2,
            width: circleSize,
            height: circleSize
        )
        
        // 填充颜色
        if enabled {
            NSColor.systemGreen.setFill()
        } else {
            NSColor.systemGray.setFill()
        }
        
        // 画圆
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.fill()
        
        // 如果是禁用状态，画红色斜杠
        if !enabled {
            NSColor.systemRed.setStroke()
            let linePath = NSBezierPath()
            linePath.lineWidth = 2
            linePath.move(to: NSPoint(x: circleRect.minX + 2, y: circleRect.minY + 2))
            linePath.line(to: NSPoint(x: circleRect.maxX - 2, y: circleRect.maxY - 2))
            linePath.move(to: NSPoint(x: circleRect.maxX - 2, y: circleRect.minY + 2))
            linePath.line(to: NSPoint(x: circleRect.minX + 2, y: circleRect.maxY - 2))
            linePath.stroke()
        }
        
        return true
    }
    
    image.isTemplate = false
    return image
}

/// 显示通知气泡
private func showNotification(enabled: Bool) {
    let notification = NSUserNotification()
    notification.title = "以太网托盘开关"
    notification.informativeText = enabled ? "以太网已启用" : "以太网已禁用"
    notification.soundName = NSUserNotificationDefaultSoundName
    NSUserNotificationCenter.default.deliver(notification)
}

/// 检查开机自启是否开启
private func isLoginItemEnabled() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = [
        "-e",
        "tell application \"System Events\" to get the name of every login item"
    ]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.contains("以太网托盘开关")
    } catch {
        return false
    }
}

/// 更新开机自启菜单的勾选状态
private func updateLoginItemState() {
    let enabled = isLoginItemEnabled()
    
    if let menu = statusItem.menu, let loginMenuItem = menu.item(withTag: 101) {
        loginMenuItem.state = enabled ? .on : .off
    }
}

/// 切换开机自启
@objc private func toggleLoginItem() {
    let currentlyEnabled = isLoginItemEnabled()
    let action = currentlyEnabled ? "remove" : "add"
    
    // 获取应用路径
    let bundlePath = Bundle.main.bundlePath
    
    let script = """
    tell application "System Events"
        if "\(action)" is "add" then
            make login item at end with properties {path:"\(bundlePath)", hidden:false}
        else
            delete (every login item whose path is "\(bundlePath)")
        end if
    end tell
    """
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    
    do {
        try task.run()
        task.waitUntilExit()
        
        // 更新菜单状态
        DispatchQueue.main.async { [weak self] in
            self?.updateLoginItemState()
        }
    } catch {
        print("设置开机自启失败: \(error)")
    }
}

/// 退出应用
@objc private func quitApp() {
    statusTimer?.invalidate()
    NSStatusBar.system.removeStatusItem(statusItem)
    app.terminate(nil)
}
