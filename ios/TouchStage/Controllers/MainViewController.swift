import UIKit

public class MainViewController: UIViewController, SettingsModalDelegate {
    private let surfaceView = MidiSurfaceView()
    private let sidebarContainer = UIView()
    private let settingsButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let pageControlStack = UIStackView()
    private var sidebarConstraints: [NSLayoutConstraint] = []
    private var currentSidebarPosition: String = "Left"

    public override var prefersStatusBarHidden: Bool {
        return true
    }

    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()

        // Start local network auto-discovery beacon listener
        NetworkDiscovery.shared.start()

        // Load bundled default preset or saved layout
        loadInitialLayout()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1.0)

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surfaceView)

        sidebarContainer.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 0.85)
        sidebarContainer.layer.cornerRadius = 14
        sidebarContainer.layer.borderWidth = 1.0
        sidebarContainer.layer.borderColor = UIColor(white: 0.18, alpha: 0.6).cgColor
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarContainer)

        // Status indicator dot
        statusDot.backgroundColor = .systemYellow
        statusDot.layer.cornerRadius = 4.0
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(statusDot)

        // Settings gear button
        settingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        settingsButton.tintColor = UIColor(white: 0.85, alpha: 1.0)
        settingsButton.addTarget(self, action: #selector(onSettingsClicked), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(settingsButton)

        // Page tabs
        pageControlStack.axis = .vertical
        pageControlStack.spacing = 6
        pageControlStack.alignment = .center
        pageControlStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(pageControlStack)

        applySidebarLayout(position: "Left")
    }

    private func applySidebarLayout(position: String) {
        currentSidebarPosition = position
        NSLayoutConstraint.deactivate(sidebarConstraints)
        sidebarConstraints.removeAll()

        let pad: CGFloat = 12.0

        // Surface View fills the view
        sidebarConstraints.append(contentsOf: [
            surfaceView.topAnchor.constraint(equalTo: view.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        switch position {
        case "Right":
            pageControlStack.axis = .vertical
            sidebarConstraints.append(contentsOf: [
                sidebarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -pad),
                sidebarContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                sidebarContainer.widthAnchor.constraint(equalToConstant: 44),
                sidebarContainer.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: pad)
            ])
        case "Top":
            pageControlStack.axis = .horizontal
            sidebarConstraints.append(contentsOf: [
                sidebarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: pad),
                sidebarContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                sidebarContainer.heightAnchor.constraint(equalToConstant: 44),
                sidebarContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: pad)
            ])
        case "Bottom":
            pageControlStack.axis = .horizontal
            sidebarConstraints.append(contentsOf: [
                sidebarContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -pad),
                sidebarContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                sidebarContainer.heightAnchor.constraint(equalToConstant: 44),
                sidebarContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: pad)
            ])
        default: // Left
            pageControlStack.axis = .vertical
            sidebarConstraints.append(contentsOf: [
                sidebarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: pad),
                sidebarContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                sidebarContainer.widthAnchor.constraint(equalToConstant: 44),
                sidebarContainer.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: pad)
            ])
        }

        // Inside sidebar container
        if position == "Top" || position == "Bottom" {
            sidebarConstraints.append(contentsOf: [
                statusDot.centerYAnchor.constraint(equalTo: sidebarContainer.centerYAnchor),
                statusDot.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 12),
                statusDot.widthAnchor.constraint(equalToConstant: 8),
                statusDot.heightAnchor.constraint(equalToConstant: 8),

                settingsButton.centerYAnchor.constraint(equalTo: sidebarContainer.centerYAnchor),
                settingsButton.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 10),
                settingsButton.widthAnchor.constraint(equalToConstant: 32),
                settingsButton.heightAnchor.constraint(equalToConstant: 32),

                pageControlStack.centerYAnchor.constraint(equalTo: sidebarContainer.centerYAnchor),
                pageControlStack.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 12),
                pageControlStack.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -12)
            ])
        } else {
            sidebarConstraints.append(contentsOf: [
                statusDot.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 12),
                statusDot.centerXAnchor.constraint(equalTo: sidebarContainer.centerXAnchor),
                statusDot.widthAnchor.constraint(equalToConstant: 8),
                statusDot.heightAnchor.constraint(equalToConstant: 8),

                settingsButton.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 10),
                settingsButton.centerXAnchor.constraint(equalTo: sidebarContainer.centerXAnchor),
                settingsButton.widthAnchor.constraint(equalToConstant: 32),
                settingsButton.heightAnchor.constraint(equalToConstant: 32),

                pageControlStack.topAnchor.constraint(equalTo: settingsButton.bottomAnchor, constant: 12),
                pageControlStack.centerXAnchor.constraint(equalTo: sidebarContainer.centerXAnchor),
                pageControlStack.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor, constant: -12)
            ])
        }

        NSLayoutConstraint.activate(sidebarConstraints)
        refreshPageTabs()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onConnectionChanged), name: .touchStageConnectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onLayoutReceived(_:)), name: .touchStageDidReceiveLayout, object: nil)
    }

    @objc private func onConnectionChanged() {
        DispatchQueue.main.async { [weak self] in
            let isConn = NetworkManager.shared.isConnected
            self?.statusDot.backgroundColor = isConn ? UIColor.systemGreen : UIColor.systemYellow
        }
    }

    @objc private func onLayoutReceived(_ notif: Notification) {
        guard let layout = notif.object as? LayoutModel else { return }
        DispatchQueue.main.async { [weak self] in
            self?.surfaceView.layout = layout
            self?.refreshPageTabs()
        }
    }

    private func refreshPageTabs() {
        pageControlStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard surfaceView.layout.pages.count > 1 else { return }

        for (idx, _) in surfaceView.layout.pages.enumerated() {
            let btn = UIButton(type: .system)
            let isCurrent = (idx == surfaceView.layout.activePageIndex)
            btn.setTitle("\(idx + 1)", for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
            btn.setTitleColor(isCurrent ? .white : UIColor(white: 0.6, alpha: 1.0), for: .normal)
            btn.backgroundColor = isCurrent ? UIColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.35) : UIColor(white: 0.15, alpha: 0.5)
            btn.layer.cornerRadius = 6.0
            btn.tag = idx
            btn.addTarget(self, action: #selector(onPageTabTapped(_:)), for: .touchUpInside)

            btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            pageControlStack.addArrangedSubview(btn)
        }
    }

    @objc private func onPageTabTapped(_ sender: UIButton) {
        let idx = sender.tag
        surfaceView.layout.activePageIndex = idx
        refreshPageTabs()
        surfaceView.setNeedsDisplay()
    }

    @objc private func onSettingsClicked() {
        let vc = SettingsModalViewController()
        vc.delegate = self
        vc.modalPresentationStyle = .formSheet
        present(vc, animated: true)
    }

    // SettingsModalDelegate
    public func settingsDidUpdateSidebarPosition(_ position: String) {
        applySidebarLayout(position: position)
    }

    public func settingsDidSelectPreset(_ preset: LayoutModel) {
        surfaceView.layout = preset
        refreshPageTabs()
    }

    private func loadInitialLayout() {
        // Try bundled preset first
        if let url = Bundle.main.url(forResource: "preset_stage8", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let layout = LayoutModel(jsonData: data) {
            surfaceView.layout = layout
        } else {
            surfaceView.layout = LayoutModel.presetStage8Track()
        }
        refreshPageTabs()
    }
}
