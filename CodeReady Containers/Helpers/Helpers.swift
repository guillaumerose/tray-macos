//
//  Helpers.swift
//  CodeReady Containers
//
//  Created by Anjan Nath on 03/12/19.
//  Copyright © 2019 Red Hat. All rights reserved.
//

import UserNotifications
import Cocoa

// Displays an alert and option to check the logs
func showAlertFailedAndCheckLogs(message: String, informativeMsg: String) {
    DispatchQueue.main.async {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let alert: NSAlert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeMsg
        alert.alertStyle = NSAlert.Style.warning
        alert.addButton(withTitle: "Check Logs")
        alert.addButton(withTitle: "Not now")
        if alert.runModal() == .alertFirstButtonReturn {
            // Open logs file
            print("Check Logs button clicked")
            let logFilePath: URL = userHomePath.appendingPathComponent(".crc").appendingPathComponent("crcd").appendingPathExtension("log")
            NSWorkspace.shared.open(logFilePath)
        } else {
            print("Not now button clicked")
        }
    }
}

func promptYesOrNo(message: String, informativeMsg: String) -> Bool {
    NSApplication.shared.activate(ignoringOtherApps: true)
    
    let alert: NSAlert = NSAlert()
    alert.messageText = message
    alert.informativeText = informativeMsg
    alert.alertStyle = NSAlert.Style.critical
    alert.addButton(withTitle: "No")
    alert.addButton(withTitle: "Yes")
    if alert.runModal() == .alertSecondButtonReturn {
        // noop
        print("second button clicked")
        return true
    } else {
        print("first button clicked")
        return false
    }
}

// Displays a success notification
func displayNotification(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    if notificationAllowed {
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: title, arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: body,
                                                                arguments: nil)
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: title, content: content, trigger: trigger)
        center.add(request) { (error) in
            if error != nil {
                print(error?.localizedDescription ?? "No Error")
            }
        }
    }
}

struct ClusterStatus: Decodable {
    let Name: String
    let CrcStatus: String
    let OpenshiftStatus: String
    let DiskUse: Int64
    let DiskSize: Int64
    let Error: String
    let Success: Bool
    let Progressing: Bool
}

// Get the status of the cluster from the daemon
func clusterStatus() -> String {
    do {
        let data = try SendCommandToDaemon(command: Request(command: "status", args: nil))
        let st = try JSONDecoder().decode(ClusterStatus.self, from: data)
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "status"), object: st)
        if st.Progressing {
            return "Progressing"
        }
        if st.Error != "" {
            print(st.Error)
            return "Backend error"
        }
        return st.OpenshiftStatus
    } catch let error {
        print(error)
        return "Broken daemon?"
    }
}

func folderSize(folderPath:URL) -> Int64 {
    let localFileManager = FileManager()
    
    let resourceKeys = [URLResourceKey.fileAllocatedSizeKey]
    let directoryEnumerator = localFileManager.enumerator(at: folderPath, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles], errorHandler: nil)!
    
    var size:Int64 = 0
    for case let fileURL as NSURL in directoryEnumerator {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
            let s = resourceValues[URLResourceKey.fileAllocatedSizeKey] as? Int64
            else {
                continue
        }
        size += s
    }
    return size
}

func showFilePicker(msg: String, txtField: NSTextField, fileTypes: [String]) {
    let dialog = NSOpenPanel()

    dialog.title                   = msg
    dialog.showsResizeIndicator    = false
    dialog.showsHiddenFiles        = false
    dialog.canChooseDirectories    = false
    dialog.canCreateDirectories    = false
    dialog.allowsMultipleSelection = false
    
    if fileTypes.count > 0 {
        dialog.allowedFileTypes = fileTypes
    }

    if (dialog.runModal() == NSApplication.ModalResponse.OK) {
        let filePath = dialog.url // Pathname of the file
        
        if (filePath != nil) {
            txtField.setValue(filePath?.path, forKey: "stringValue")
            return
        }
    }
    // User clicked cancel
    return
}
