//
//  ViewController.swift
//  CodeReady Containers
//
//  Created by Anjan Nath on 12/11/19.
//  Copyright © 2019 Red Hat. All rights reserved.
//

import Cocoa

class DetailedStatusViewController: NSViewController {

    @IBOutlet weak var vmStatus: NSTextField!
    @IBOutlet weak var ocpStatus: NSTextField!
    @IBOutlet weak var diskUsage: NSTextField!
    @IBOutlet weak var cacheSize: NSTextField!
    @IBOutlet weak var cacheDirectory: NSTextField!
    @IBOutlet weak var logs: NSTextView!
    
    var timer: Timer? = nil
    
    let cacheDirPath: URL = userHomePath.appendingPathComponent(".crc").appendingPathComponent("cache")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateViewWithLogs()
        
        self.timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(updateViewWithLogs), userInfo: nil, repeats: true)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateViewWithClusterStatus(_:)), name: NSNotification.Name(rawValue: "status"), object: nil)
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    var font: NSFont?    = .systemFont(ofSize: 14, weight: .regular)
    
    override func viewDidAppear() {
        self.logs.font = font
        
        self.logs.string = "Hello world"
        
        view.window?.level = .floating
        view.window?.center()
    }
    
    override func viewDidDisappear() {
        self.timer?.invalidate()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "status"), object: nil)
    }
    
    @objc func updateViewWithLogs() {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try SendCommandToDaemon(command: Request(command: "logs", args: nil))
                DispatchQueue.main.async {
                    let lines = String(decoding: data, as: UTF8.self)
                    if lines != self.logs.string {
                        self.logs.string = lines
                        self.logs.scrollToEndOfDocument(nil)
                    }
                }
            } catch let error {
                DispatchQueue.main.async {
                    self.logs.string =  "Failed to get logs. Error: \(error)"
                }
            }
        }
    }
    
    @objc private func updateViewWithClusterStatus(_ notification: Notification) {
        print(notification)
        guard let status = notification.object as? ClusterStatus else {
            return
        }
        DispatchQueue.main.async {
            self.vmStatus.stringValue = status.CrcStatus
            self.ocpStatus.stringValue = status.OpenshiftStatus
            self.diskUsage.stringValue = "\(Units(bytes: status.DiskUse).getReadableUnit()) of \(Units(bytes: status.DiskSize).getReadableUnit()) (Inside the VM)"
            self.cacheSize.stringValue = Units(bytes: folderSize(folderPath: self.cacheDirPath)).getReadableUnit()
            self.cacheDirectory.stringValue = self.cacheDirPath.path
        }
    }
}

