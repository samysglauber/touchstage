import Cocoa

class EditorAppDelegate: NSObject, NSApplicationDelegate {
    var editorController: EditorWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let controller = EditorWindowController()
        self.editorController = controller
        controller.showEditor()
        setupAppMenu()
    }

    func setupAppMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "TouchStage Editor")
        appMenu.addItem(withTitle: "About TouchStage Editor", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide TouchStage Editor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit TouchStage Editor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Recent Projects...", action: #selector(EditorWindowController.showLauncherSheet), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "New Project", action: #selector(EditorWindowController.onNewLayoutClicked(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open Layout...", action: #selector(EditorWindowController.onOpenLayoutClicked(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save Layout File...", action: #selector(EditorWindowController.onSaveLayoutClicked(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save as Preset...", action: #selector(EditorWindowController.onSavePresetClicked(_:)), keyEquivalent: "S")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit Menu (Enables native system-level Cmd+Z, Cmd+Shift+Z, Cmd+C, Cmd+V, Cmd+A, Delete)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Delete", action: #selector(EditorCanvasView.deleteSelected(_:)), keyEquivalent: "\u{08}")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = EditorAppDelegate()
app.delegate = delegate
app.run()
