import Cocoa

// MARK: - Shell helper

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// MARK: - Model

enum VolState { case rw(String), ro(String), unmounted }

struct NTFSVol {
    let id: String       // e.g. disk5s1
    let name: String
    let state: VolState
}

func parentDisk(_ id: String) -> String {
    guard id.hasPrefix("disk") else { return id }
    var digits = ""
    for ch in id.dropFirst(4) { if ch.isNumber { digits.append(ch) } else { break } }
    return "disk" + digits
}

// Extract the mountpoint from a `mount` line: "<spec> on <MP> (opts)".
func mountpoint(_ line: Substring) -> String? {
    guard let on = line.range(of: " on ") else { return nil }
    let after = line[on.upperBound...]
    guard let paren = after.range(of: " (") else { return nil }
    return String(after[..<paren.lowerBound])
}

func listNTFS() -> [NTFSVol] {
    let listOut = run("/usr/sbin/diskutil", ["list"]).out
    var ids: [String] = []
    for line in listOut.split(separator: "\n") where line.contains("Windows_NTFS") {
        if let last = line.split(separator: " ").last { ids.append(String(last)) }
    }
    let m = run("/sbin/mount", []).out
    let mlines = m.split(separator: "\n")

    var vols: [NTFSVol] = []
    for id in ids {
        let dev = "/dev/\(id)"
        // Volume name
        var name = id
        for line in run("/usr/sbin/diskutil", ["info", dev]).out.split(separator: "\n")
        where line.contains("Volume Name:") {
            let parts = line.components(separatedBy: ":")
            if parts.count > 1 {
                let n = parts[1].trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { name = n }
            }
        }
        // State
        var state: VolState = .unmounted
        for line in mlines {
            if line.hasPrefix("fuse-t:/\(name) on "), let mp = mountpoint(line) {
                state = .rw(mp); break
            }
            if line.hasPrefix("\(dev) on "), let mp = mountpoint(line) {
                state = .ro(mp) // keep scanning; a fuse-t line would override
            }
        }
        vols.append(NTFSVol(id: id, name: name, state: state))
    }
    return vols
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ note: Notification) {
        if let btn = statusItem.button {
            let img = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill",
                              accessibilityDescription: "NTFStore")
            img?.isTemplate = true
            btn.image = img
            btn.title = "NTFS"
            btn.imagePosition = .imageLeading
            btn.imageHugsTitle = true
            if let f = btn.font { btn.font = NSFont.systemFont(ofSize: f.pointSize, weight: .semibold) }
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Ownership header
        let owner = NSMenuItem(title: "NTFStore — Pritish Maheta", action: nil, keyEquivalent: "")
        owner.isEnabled = false
        menu.addItem(owner)
        menu.addItem(.separator())

        let vols = listNTFS()

        if vols.isEmpty {
            let it = NSMenuItem(title: "No NTFS drives connected", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }

        for v in vols {
            let title: String
            switch v.state {
            case .rw:        title = "🟢  \(v.name) — read-write"
            case .ro:        title = "🔴  \(v.name) — read-only"
            case .unmounted: title = "⚪️  \(v.name) — not mounted"
            }
            let volItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            volItem.isEnabled = true

            let sub = NSMenu()
            func add(_ t: String, _ sel: Selector, mp: String = "") {
                let it = NSMenuItem(title: t, action: sel, keyEquivalent: "")
                it.target = self
                it.representedObject = ["id": v.id, "mp": mp, "parent": parentDisk(v.id)]
                sub.addItem(it)
            }
            switch v.state {
            case .rw(let mp):
                add("Open in Finder", #selector(openFinder(_:)), mp: mp)
                add("Unmount", #selector(unmountVol(_:)), mp: mp)
                add("Eject (safe to unplug)", #selector(ejectVol(_:)), mp: mp)
            case .ro(let mp):
                add("Mount read-write", #selector(mountRW(_:)), mp: mp)
                add("Open in Finder", #selector(openFinder(_:)), mp: mp)
                add("Unmount", #selector(unmountVol(_:)), mp: mp)
                add("Eject (safe to unplug)", #selector(ejectVol(_:)), mp: mp)
            case .unmounted:
                add("Mount read-write", #selector(mountRW(_:)))
                add("Eject (safe to unplug)", #selector(ejectVol(_:)))
            }
            volItem.submenu = sub
            menu.addItem(volItem)
        }

        menu.addItem(.separator())
        let mountAll = NSMenuItem(title: "Mount all read-write", action: #selector(mountAll(_:)), keyEquivalent: "m")
        mountAll.target = self; menu.addItem(mountAll)
        let refresh = NSMenuItem(title: "Refresh", action: #selector(noop(_:)), keyEquivalent: "r")
        refresh.target = self; menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NTFStore", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
    }

    private func info(_ sender: Any?) -> (id: String, mp: String, parent: String) {
        if let it = sender as? NSMenuItem, let d = it.representedObject as? [String: String] {
            return (d["id"] ?? "", d["mp"] ?? "", d["parent"] ?? "")
        }
        return ("", "", "")
    }

    // Mount read-write via the privileged one-shot helper (sudo NOPASSWD). Runs in
    // this app's user session, so the FUSE-T mount persists.
    @objc func mountRW(_ sender: Any?) {
        let i = info(sender)
        DispatchQueue.global().async {
            _ = run("/usr/bin/sudo", ["-n", "/usr/local/sbin/ntfs-mount-rw.sh", i.id])
        }
    }
    @objc func unmountVol(_ sender: Any?) {
        let i = info(sender)
        DispatchQueue.global().async {
            let target = i.mp.isEmpty ? "/dev/\(i.id)" : i.mp
            _ = run("/usr/sbin/diskutil", ["unmount", target])
        }
    }
    @objc func ejectVol(_ sender: Any?) {
        let i = info(sender)
        DispatchQueue.global().async {
            if !i.mp.isEmpty { _ = run("/usr/sbin/diskutil", ["unmount", i.mp]) }
            _ = run("/usr/sbin/diskutil", ["eject", "/dev/\(i.parent)"])
        }
    }
    @objc func openFinder(_ sender: Any?) {
        let i = info(sender)
        if !i.mp.isEmpty { _ = run("/usr/bin/open", [i.mp]) }
    }
    @objc func mountAll(_ sender: Any?) {
        DispatchQueue.global().async {
            for v in listNTFS() {
                _ = run("/usr/bin/sudo", ["-n", "/usr/local/sbin/ntfs-mount-rw.sh", v.id])
            }
        }
    }
    @objc func noop(_ sender: Any?) {}          // menu rebuilds on open; Refresh is a no-op
    @objc func quitApp(_ sender: Any?) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
