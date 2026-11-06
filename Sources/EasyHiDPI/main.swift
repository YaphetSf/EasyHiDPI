import AppKit

if CommandLine.arguments.contains("--list") {
    printDisplayList()
    exit(0)
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
