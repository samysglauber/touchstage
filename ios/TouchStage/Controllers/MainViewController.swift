import UIKit

public class MainViewController: UIViewController, MidiSurfaceViewDelegate, SettingsModalDelegate {
    private let surfaceView = MidiSurfaceView()

    public override var prefersStatusBarHidden: Bool {
        return true
    }

    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    public override var shouldAutorotate: Bool {
        return true
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lockToLandscape()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lockToLandscape()
    }

    private func lockToLandscape() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            if let windowScene = view.window?.windowScene {
                let geom = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
                windowScene.requestGeometryUpdate(geom) { _ in }
            }
        }
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.05, green: 0.055, blue: 0.07, alpha: 1.0)

        surfaceView.delegate = self
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surfaceView)

        NSLayoutConstraint.activate([
            surfaceView.topAnchor.constraint(equalTo: view.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onConnectionChanged), name: .touchStageConnectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onLayoutReceived(_:)), name: .touchStageDidReceiveLayout, object: nil)
    }

    @objc private func onConnectionChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.surfaceView.setNeedsDisplay()
        }
    }

    @objc private func onLayoutReceived(_ notif: Notification) {
        guard let layout = notif.object as? LayoutModel else { return }
        DispatchQueue.main.async { [weak self] in
            self?.surfaceView.layout = layout
        }
    }

    // -------------------------------------------------------------
    // MidiSurfaceViewDelegate
    // -------------------------------------------------------------

    public func midiSurfaceDidRequestSettings() {
        let vc = SettingsModalViewController()
        vc.delegate = self
        vc.modalPresentationStyle = .formSheet
        present(vc, animated: true)
    }

    public func midiSurfaceDidRequestPageChange(to index: Int) {
        surfaceView.layout.activePageIndex = index
        surfaceView.setNeedsDisplay()
    }

    // -------------------------------------------------------------
    // SettingsModalDelegate
    // -------------------------------------------------------------

    public func settingsDidUpdateSidebarPosition(_ position: String) {
        surfaceView.sidebarPosition = position.lowercased()
    }

    public func settingsDidSelectPreset(_ preset: LayoutModel) {
        surfaceView.layout = preset
    }

    private func loadInitialLayout() {
        if let url = Bundle.main.url(forResource: "preset_stage8", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let layout = LayoutModel(jsonData: data) {
            surfaceView.layout = layout
        } else {
            surfaceView.layout = LayoutModel.presetStage8Track()
        }
    }
}
