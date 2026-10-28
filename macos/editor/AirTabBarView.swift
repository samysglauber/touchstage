import Cocoa

@objc public protocol AirTabBarDelegate: AnyObject {
    func tabBarDidSelectPageIndex(_ index: Int)
    func tabBarDidRequestAddPage()
    func tabBarDidRequestDeletePageIndex(_ index: Int)
    func tabBarDidRenamePageIndex(_ index: Int, toName newName: String)
}

public class AirTabButton: NSButton {
    public var pageIndex: Int = 0
    public var isActiveTab: Bool = false
    public weak var tabBar: AirTabBarView?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.isBordered = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.isBordered = false
    }

    public override var isFlipped: Bool {
        return true
    }

    public override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        if isActiveTab {
            // Active Tab Capsule Pill
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 2.0, dy: 4.0), xRadius: 6.0, yRadius: 6.0)
            NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.25).setFill()
            pill.fill()
            AirColorAccent().setStroke()
            pill.lineWidth = 1.5
            pill.stroke()
        } else {
            // Inactive Tab subtle hover / transparent
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 2.0, dy: 4.0), xRadius: 6.0, yRadius: 6.0)
            NSColor(calibratedWhite: 0.18, alpha: 0.4).setFill()
            pill.fill()
            NSColor(calibratedWhite: 0.25, alpha: 0.6).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()
        }

        // Icon + Text
        let icon = self.image
        let tabTitle = self.title.isEmpty ? "Screen" : self.title

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isActiveTab ? NSColor.white : AirColorTextSecondary(),
            .font: NSFont.systemFont(ofSize: 11.5, weight: isActiveTab ? .bold : .medium)
        ]
        let textSize = (tabTitle as NSString).size(withAttributes: attrs)

        let iconW: CGFloat = icon?.size.width ?? 0
        let spacing: CGFloat = 6.0
        let totalW = iconW + (icon != nil ? spacing : 0) + textSize.width

        var curX = round((bounds.size.width - totalW) / 2.0)

        if let icon = icon {
            let iconY = round((bounds.size.height - icon.size.height) / 2.0)
            let iconRect = NSRect(x: curX, y: iconY, width: icon.size.width, height: icon.size.height)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isActiveTab ? 1.0 : 0.7, respectFlipped: true, hints: nil)
            curX += iconW + spacing
        }

        let textY = round((bounds.size.height - textSize.height) / 2.0)
        let textRect = NSRect(x: curX, y: textY, width: textSize.width, height: textSize.height)
        (tabTitle as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

public class AirTabBarView: NSView {
    public weak var delegate: AirTabBarDelegate?
    public weak var layout: LayoutModel?

    private var scrollView: NSScrollView!
    private var container: NSView!
    private var btnAdd: NSButton!

    public override var isFlipped: Bool {
        return true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        self.wantsLayer = true

        scrollView = NSScrollView(frame: self.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        container = NSView(frame: NSRect(x: 0, y: 0, width: self.bounds.size.width, height: self.bounds.size.height))
        scrollView.documentView = container
        self.addSubview(scrollView)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Bar background
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0).setFill()
        self.bounds.fill()

        // Bottom hairline divider
        AirColorBorder().setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: self.bounds.size.height - 0.5))
        line.line(to: NSPoint(x: self.bounds.size.width, y: self.bounds.size.height - 0.5))
        line.lineWidth = 1.0
        line.stroke()
    }

    public func reloadTabs() {
        for v in container.subviews {
            v.removeFromSuperview()
        }

        guard let layout = self.layout else { return }

        var curX: CGFloat = 16.0
        let tabH: CGFloat = 28.0
        let tabY = (self.bounds.size.height - tabH) / 2.0

        // Label: "SCREENS:"
        let tagLabel = NSTextField(frame: NSRect(x: curX, y: tabY + 6.0, width: 64, height: 16))
        tagLabel.stringValue = "SCREENS:"
        tagLabel.font = NSFont.systemFont(ofSize: 10.0, weight: .bold)
        tagLabel.textColor = AirColorTextMuted()
        tagLabel.isEditable = false
        tagLabel.isSelectable = false
        tagLabel.isBezeled = false
        tagLabel.drawsBackground = false
        container.addSubview(tagLabel)
        curX += 70.0

        for (i, page) in layout.pages.enumerated() {
            let isActive = (i == layout.activePageIndex)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .bold)
            ]
            let sz = (page.name as NSString).size(withAttributes: attrs)
            let tabW = max(90.0, sz.width + 36.0)

            let tabBtn = AirTabButton(frame: NSRect(x: curX, y: tabY, width: tabW, height: tabH))
            tabBtn.title = page.name
            tabBtn.pageIndex = i
            tabBtn.isActiveTab = isActive
            tabBtn.tabBar = self
            tabBtn.image = AirSymbol(isActive ? "rectangle.split.2x1.fill" : "rectangle", 11.0)
            tabBtn.target = self
            tabBtn.action = #selector(onTabClicked(_:))
            container.addSubview(tabBtn)

            // Right-click context menu on tab
            let tabMenu = NSMenu(title: "Tab Options")
            let itemRename = NSMenuItem(title: "Rename Screen...", action: #selector(onRenameTabClicked(_:)), keyEquivalent: "")
            itemRename.representedObject = i
            itemRename.target = self
            tabMenu.addItem(itemRename)

            if layout.pages.count > 1 {
                let itemDelete = NSMenuItem(title: "Delete Screen", action: #selector(onDeleteTabClicked(_:)), keyEquivalent: "")
                itemDelete.representedObject = i
                itemDelete.target = self
                tabMenu.addItem(itemDelete)
            }
            tabBtn.menu = tabMenu

            curX += tabW + 6.0
        }

        // Add "+" New Screen Button
        btnAdd = NSButton(frame: NSRect(x: curX, y: tabY, width: 94.0, height: tabH))
        btnAdd.bezelStyle = .texturedRounded
        btnAdd.title = "+ Screen"
        btnAdd.font = NSFont.systemFont(ofSize: 11.0, weight: .medium)
        btnAdd.image = AirSymbol("plus", 10.0)
        btnAdd.imagePosition = .imageLeading
        btnAdd.toolTip = "Add a new screen/page to this preset"
        btnAdd.target = self
        btnAdd.action = #selector(onAddPageClicked(_:))
        container.addSubview(btnAdd)

        curX += 104.0
        container.frame = NSRect(x: 0, y: 0, width: max(curX, self.bounds.size.width), height: self.bounds.size.height)
    }

    @objc private func onTabClicked(_ sender: AirTabButton) {
        delegate?.tabBarDidSelectPageIndex(sender.pageIndex)
    }

    @objc private func onAddPageClicked(_ sender: Any?) {
        delegate?.tabBarDidRequestAddPage()
    }

    @objc private func onDeleteTabClicked(_ sender: NSMenuItem) {
        if let idx = sender.representedObject as? Int {
            delegate?.tabBarDidRequestDeletePageIndex(idx)
        }
    }

    @objc private func onRenameTabClicked(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int,
              let layout = self.layout,
              idx >= 0 && idx < layout.pages.count else { return }

        let page = layout.pages[idx]

        let alert = NSAlert()
        alert.messageText = "Rename Screen"
        alert.informativeText = "Enter a new name for this screen / tab:"
        alert.icon = AirSymbol("rectangle.and.pencil.and.ellipsis", 36.0)
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = page.name.isEmpty ? "Screen" : page.name
        alert.accessoryView = input

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            if returnCode == .alertFirstButtonReturn {
                let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newName.isEmpty {
                    self?.delegate?.tabBarDidRenamePageIndex(idx, toName: newName)
                }
            }
        }
    }
}
