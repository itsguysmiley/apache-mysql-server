import AppKit
import Foundation

// MARK: - Server Manager
class ServerManager {
    let brewPath = "/Users/THOMGEOF0981/Applications/homebrew/bin/brew"

    func runBrew(_ args: [String], completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = self.brewPath
            task.arguments = args
            task.standardOutput = nil; task.standardError = nil
            task.launch()
            task.waitUntilExit()
            DispatchQueue.main.async { completion?() }
        }
    }
    
    func runBrewSync(_ args: [String]) {
        let task = Process()
        task.launchPath = brewPath
        task.arguments = args
        task.launch()
        task.waitUntilExit()
    }
    
    func getServiceStatus(completion: @escaping ([String: Bool]) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let pipe = Pipe()
            let task = Process()
            task.launchPath = self.brewPath
            task.arguments = ["services", "list"]
            task.standardOutput = pipe
            task.launch()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            var status: [String: Bool] = ["nginx": false, "mariadb": false]
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.lowercased().contains("nginx") && line.lowercased().contains("started") { status["nginx"] = true }
                if line.lowercased().contains("mariadb") && line.lowercased().contains("started") { status["mariadb"] = true }
            }
            DispatchQueue.main.async { completion(status) }
        }
    }
}

// MARK: - View Controller for the Popover
class ServerViewController: NSViewController {
    let manager = ServerManager()
    var serviceStatus: [String: Bool] = ["nginx": false, "mariadb": false]
    var isBusy = false
    
    var allActionableButtons: [NSButton] = []
    let spinner = NSProgressIndicator()
    let stackView = NSStackView()

    override func loadView() {
        view = NSView()

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 5
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        view.addSubview(spinner)
        
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let buttonConfigs = [
            ("Nginx", #selector(toggleNginx), self),
            ("MariaDB", #selector(toggleMariaDB), self),
            ("---", nil, nil),
            ("🚀 Start All Services", #selector(startAllAction), self),
            ("🛑 Stop All Services", #selector(stopAllAction), self),
            ("---", nil, nil),
            ("🔗 Open phpMyAdmin", #selector(openPMA), self),
            ("📁 Open Webroot", #selector(openWebroot), self),
            ("---", nil, nil),
            ("Quit", #selector(quitApp), self) // Changed target to self
        ] as [(String, Selector?, Any?)]

        for (title, action, target) in buttonConfigs {
            if title == "---" {
                let separator = NSBox()
                separator.boxType = .separator
                stackView.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -30).isActive = true
                stackView.setCustomSpacing(16.0, after: stackView.arrangedSubviews.last ?? view)
            } else {
                let button = NSButton(title: title, target: target, action: action)
                button.bezelStyle = .recessed
                button.isBordered = false
                button.alignment = .left
                button.contentTintColor = .white
                stackView.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -30).isActive = true
                
                if action != nil {
                    allActionableButtons.append(button)
                }
            }
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        refreshStatus()
    }
    
    func updateUI(isQuitting: Bool = false) {
        allActionableButtons.forEach {
            if $0.title.contains("Quit") {
                if isQuitting {
                    $0.title = "Quitting..."
                }
            } else {
                $0.isEnabled = !isBusy && !isQuitting
            }
        }
        spinner.isHidden = !isBusy
        if isBusy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

        let nginxOn = serviceStatus["nginx"] ?? false
        allActionableButtons.first(where: { $0.title.contains("Nginx") })?.title = "\(nginxOn ? "🟢" : "🔴") Nginx"
        
        let dbOn = serviceStatus["mariadb"] ?? false
        allActionableButtons.first(where: { $0.title.contains("MariaDB") })?.title = "\(dbOn ? "🟢" : "🔴") MariaDB"
    }
    
    func refreshStatus(completion: (() -> Void)? = nil) {
        manager.getServiceStatus { [weak self] status in
            self?.serviceStatus = status
            self?.updateUI()
            completion?()
        }
    }
    
    func performServiceOperation(operations: [(String, String)]) {
        isBusy = true
        updateUI()
        let group = DispatchGroup()
        for (cmd, service) in operations {
            group.enter()
            manager.runBrew(["services", cmd, service]) { group.leave() }
        }
        group.notify(queue: .main) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refreshStatus { [weak self] in
                    self?.isBusy = false
                    self?.updateUI()
                }
            }
        }
    }

    @objc func toggleNginx() { performServiceOperation(operations: [(serviceStatus["nginx"] ?? false ? "stop" : "start", "nginx"), (serviceStatus["nginx"] ?? false ? "stop" : "start", "php@8.3")]) }
    @objc func toggleMariaDB() { performServiceOperation(operations: [(serviceStatus["mariadb"] ?? false ? "stop" : "start", "mariadb")]) }
    @objc func startAllAction() { performServiceOperation(operations: [("start", "mariadb"), ("start", "nginx"), ("start", "php@8.3")]) }
    @objc func stopAllAction() { performServiceOperation(operations: [("stop", "mariadb"), ("stop", "nginx"), ("stop", "php@8.3")]) }
    @objc func openPMA() { if let url = URL(string: "http://localhost:8080/phpmyadmin") { NSWorkspace.shared.open(url) } }
    @objc func openWebroot() { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Users/THOMGEOF0981/Applications/homebrew/var/www") }

    @objc func quitApp() {
        updateUI(isQuitting: true)
        // Run stops in background and then terminate
        DispatchQueue.global(qos: .userInitiated).async {
            self.manager.runBrewSync(["services", "stop", "mariadb"])
            self.manager.runBrewSync(["services", "stop", "nginx"])
            self.manager.runBrewSync(["services", "stop", "php@8.3"])
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Server Control")
        statusItem.button?.action = #selector(togglePopover)
        
        popover.contentViewController = ServerViewController()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .vibrantDark) 
        popover.contentViewController?.view.wantsLayer = true
        popover.contentViewController?.view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                if let vc = popover.contentViewController as? ServerViewController {
                    vc.refreshStatus()
                }
            }
        }
    }
}

// MARK: - Main App
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
