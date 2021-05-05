//
//  AppDelegate.swift
//  CodeReady Containers
//
//  Created by Anjan Nath on 12/11/19.
//  Copyright © 2019 Red Hat. All rights reserved.
//

import Cocoa
import UserNotifications
import Sparkle

var notificationAllowed: Bool = false

// MenuStates is used to update the state of the menus
struct MenuStates {
    let startMenuEnabled: Bool
    let stopMenuEnabled: Bool
    let deleteMenuEnabled: Bool
    let webconsoleMenuEnabled: Bool
    let ocLoginForDeveloperEnabled: Bool
    let ocLoginForAdminEnabled: Bool
    let copyOcLoginCommand: Bool
}

let statusNotification = NSNotification.Name(rawValue: "status")

class AutoUpgardeManager: NSObject {
    static let shared = AutoUpgardeManager()

    func setup() {
        SUUpdater.shared()?.delegate = self
    }
}

extension AutoUpgardeManager: SUUpdaterDelegate {
    func feedURLString(for updater: SUUpdater) -> String? {
        return "http://127.0.0.1:8000/appcast.xml"
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet weak var menu: NSMenu!
    @IBOutlet weak var statusMenuItem: NSMenuItem!
    @IBOutlet weak var deleteMenuItem: NSMenuItem!
    @IBOutlet weak var stopMenuItem: NSMenuItem!
    @IBOutlet weak var startMenuItem: NSMenuItem!
    @IBOutlet weak var webConsoleMenuItem: NSMenuItem!
    @IBOutlet weak var ocLoginForKubeadmin: NSMenuItem!
    @IBOutlet weak var ocLoginForDeveloper: NSMenuItem!
    @IBOutlet weak var detailedStatusMenuItem: NSMenuItem!
    @IBOutlet weak var copyOcLoginCommand: NSMenuItem!

    let statusRefreshRate: TimeInterval = 5 // seconds
    var kubeadminPass: String!
    var apiEndpoint: String!

    var status: ClusterStatus = brokenDaemonClusterStatus

    weak var pullSecretWindowController: PullSecretWindowController?

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            let menubarIcon = NSImage(named: NSImage.Name("TrayIcon"))
            menubarIcon?.isTemplate = true
            button.image = menubarIcon
        }
        menu.delegate = self
        statusItem.menu = self.menu
        statusItem.button?.appearsDisabled = true

        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).count > 1 {
            print("more than one running")
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.messageText = "Another instance of \(Bundle.main.bundleIdentifier!) is running."
            alert.informativeText = "This instance will now terminate."
            alert.alertStyle = .critical
            alert.runModal()

            NSApp.terminate(self)
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound], completionHandler: { (granted, error) in
            notificationAllowed = granted
            print(error?.localizedDescription ?? "Notification Request: No Error")
        })

        DispatchQueue.global(qos: .background).async {
            self.startDaemon()
        }

        DispatchQueue.global(qos: .background).async {
            sleep(1) // wait for the daemon to start
            SendTelemetry(Actions.Start)
            self.pollStatus()
        }

        Timer.scheduledTimer(timeInterval: statusRefreshRate, target: self, selector: #selector(pollStatus), userInfo: nil, repeats: true)

        NotificationCenter.default.addObserver(self, selector: #selector(updateViewWithClusterStatus(_:)), name: statusNotification, object: nil)
        
        AutoUpgardeManager.shared.setup()
    }

    func startDaemon() {
        let task = Process()
        let stdin = Pipe()
        #if DEBUG
        task.launchPath = "/Users/guillaumerose/.gvm/pkgsets/go1.14/global/bin/crc"
        #else
        task.launchPath = NSString.path(withComponents: [Bundle.main.bundlePath, "Contents", "Resources", "crc"])
        #endif
        task.arguments = ["daemon", "--watchdog"]
        task.standardInput = stdin
        do {
            try task.run()
        } catch let error {
            fatal(message: "Cannot start the daemon",
                  informativeMsg: "Check the logs and restart the application.\nError: \(error.localizedDescription)")
            return
        }
        task.waitUntilExit()
        if task.terminationStatus == 2 {
            fatal(message: "Setup incomplete",
                  informativeMsg: "Open a terminal, run 'crc setup', and start again this application.")
        } else {
            fatal(message: "Daemon crashed",
                  informativeMsg: "Check the logs and restart the application")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        // Maybe kill the daemon too
    }

    @IBAction func startMenuClicked(_ sender: Any) {
        SendTelemetry(Actions.ClickStart)

        // check if pull-secret-file is configured
        // if yes call HadleStart("")
        // otherwise invoke the pullSecretPicker view
        var response: [String: String]
        do {
            response = try GetConfigFromDaemon(properties: ["pull-secret-file"])
        } catch let error {
            showAlertFailedAndCheckLogs(message: "Failed to Check if Pull Secret is configured",
                                        informativeMsg: "Ensure the CRC daemon is running, for more information please check the logs.\nError: \(error)")
            return
        }
        if statusLabel(status) == "Stopped" {
            DispatchQueue.global(qos: .userInteractive).async {
                HandleStart(pullSecretPath: "")
                DispatchQueue.main.sync {
                    self.statusItem.button?.appearsDisabled = false
                }
            }
        } else if response["pull-secret-file"] == "" {
            if pullSecretWindowController == nil {
                pullSecretWindowController = PullSecretWindowController.loadFromStoryBoard()
            }
            pullSecretWindowController?.showWindow(self)
        } else {
            DispatchQueue.global(qos: .userInteractive).async {
                HandleStart(pullSecretPath: "")
                DispatchQueue.main.sync {
                    self.statusItem.button?.appearsDisabled = false
                }
            }
        }
    }

    @IBAction func stopMenuClicked(_ sender: Any) {
        DispatchQueue.global(qos: .userInteractive).async {
            HandleStop()
            DispatchQueue.main.sync {
                self.statusItem.button?.appearsDisabled = true
            }
        }
    }

    @IBAction func deleteMenuClicked(_ sender: Any) {
        DispatchQueue.global(qos: .userInteractive).async {
            HandleDelete()
            DispatchQueue.main.sync {
                self.statusItem.button?.appearsDisabled = true
            }
        }
    }

    @IBAction func webConsoleMenuClicked(_ sender: Any) {
        SendTelemetry(Actions.ClickOpenConsole)
        DispatchQueue.global(qos: .userInteractive).async {
            HandleWebConsoleURL()
        }
    }

    @IBAction func copyOcLoginForKubeadminMenuClicked(_ sender: Any) {
        SendTelemetry(Actions.CopyOCLoginForAdmin)
        DispatchQueue.global(qos: .userInteractive).async {
            HandleLoginCommandForKubeadmin()
        }
    }

    @IBAction func copyOcLoginForDeveloperMenuClicked(_ sender: Any) {
        SendTelemetry(Actions.CopyOCLoginForDeveloper)
        DispatchQueue.global(qos: .userInteractive).async {
            HandleLoginCommandForDeveloper()
        }
    }

    @IBAction func quitTrayMenuClicked(_ sender: Any) {
        SendTelemetry(Actions.Quit)
        NSApplication.shared.terminate(self)
    }
    
    @IBAction func checkForUpdatesClicked(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(self)
    }

    func initializeMenus(status: String) {
        self.statusMenuItem.title = status

        self.startMenuItem.isEnabled = true
        self.stopMenuItem.isEnabled = true
        self.deleteMenuItem.isEnabled = true
        self.webConsoleMenuItem.isEnabled = true
        self.copyOcLoginCommand.isEnabled = true
        self.ocLoginForDeveloper.isEnabled = true
        self.ocLoginForKubeadmin.isEnabled = true

        if status == "Running" {
            self.statusMenuItem.image = NSImage(named: NSImage.statusAvailableName)
            self.statusItem.button?.appearsDisabled = false
        } else if status == "Stopped" {
            self.statusMenuItem.image = NSImage(named: NSImage.statusUnavailableName)
            self.statusItem.button?.appearsDisabled = true
        } else {
            self.statusMenuItem.image = NSImage(named: NSImage.statusNoneName)
            self.statusItem.button?.appearsDisabled = true
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        SendTelemetry(Actions.OpenMenu)
    }

    @objc func pollStatus() {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try SendCommandToDaemon(command: Request(command: "status", args: nil))
                let status = try JSONDecoder().decode(ClusterStatus.self, from: data)
                NotificationCenter.default.post(name: statusNotification, object: status)
            } catch let error {
                print(error.localizedDescription)
                NotificationCenter.default.post(name: statusNotification, object: brokenDaemonClusterStatus)
            }
        }
    }

    @objc private func updateViewWithClusterStatus(_ notification: Notification) {
        guard let status = notification.object as? ClusterStatus else {
            return
        }
        self.status = status
        DispatchQueue.main.async {
            self.initializeMenus(status: stoppedIfDoesNotExist(status: statusLabel(status)))
        }
    }
}
