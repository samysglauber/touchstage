import UIKit

public protocol SettingsModalDelegate: AnyObject {
    func settingsDidUpdateSidebarPosition(_ position: String)
    func settingsDidSelectPreset(_ preset: LayoutModel)
}

public class SettingsModalViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    public weak var delegate: SettingsModalDelegate?

    private var discoveredServers: [DiscoveredServer] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let ipTextField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let hapticSwitch = UISwitch()
    private let sidebarSegment = UISegmentedControl(items: ["Left", "Right", "Top", "Bottom"])

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NetworkDiscovery.shared.delegate = self
        discoveredServers = NetworkDiscovery.shared.availableServers
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.98)

        // Title Bar
        let titleLabel = UILabel()
        titleLabel.text = "TouchStage Settings"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Done", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        closeButton.setTitleColor(UIColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 1.0), for: .normal)
        closeButton.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func onClose() {
        dismiss(animated: true)
    }

    // -------------------------------------------------------------
    // TableView Sections
    // -------------------------------------------------------------

    public func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(1, discoveredServers.count) // Discovered Macs
        case 1: return 1 // Manual IP Connection
        case 2: return 2 // Sidebar Position & Haptics
        case 3: return 2 // Built-in Presets
        default: return 0
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "DISCOVERED MACS (AUTO-DISCOVERY)"
        case 1: return "MANUAL IP CONNECTION"
        case 2: return "PREFERENCES"
        case 3: return "PRESETS"
        default: return nil
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        cell.backgroundColor = UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1.0)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = UIColor(white: 0.7, alpha: 1.0)

        switch indexPath.section {
        case 0:
            if discoveredServers.isEmpty {
                cell.textLabel?.text = "Searching for Bridge beacons on Wi-Fi..."
                cell.textLabel?.textColor = .gray
                cell.detailTextLabel?.text = "Make sure TouchStage Bridge is running on your Mac."
                cell.selectionStyle = .none
            } else {
                let s = discoveredServers[indexPath.row]
                let isConnected = (NetworkManager.shared.host == s.ip && NetworkManager.shared.isConnected)
                cell.textLabel?.text = s.name + (isConnected ? " (Connected)" : "")
                cell.detailTextLabel?.text = "\(s.ip):\(s.port)"
                cell.accessoryType = isConnected ? .checkmark : .none
            }

        case 1:
            cell.selectionStyle = .none
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            ipTextField.placeholder = "192.168.1.xxx"
            ipTextField.text = NetworkManager.shared.host
            ipTextField.textColor = .white
            ipTextField.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
            ipTextField.keyboardType = .numbersAndPunctuation

            connectButton.setTitle("Connect", for: .normal)
            connectButton.setTitleColor(UIColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 1.0), for: .normal)
            connectButton.addTarget(self, action: #selector(onManualConnect), for: .touchUpInside)

            stack.addArrangedSubview(ipTextField)
            stack.addArrangedSubview(connectButton)
            cell.contentView.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
            ])

        case 2:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Sidebar Position"
                sidebarSegment.selectedSegmentIndex = 0
                sidebarSegment.addTarget(self, action: #selector(onSidebarPositionChanged), for: .valueChanged)
                cell.accessoryView = sidebarSegment
            } else {
                cell.textLabel?.text = "Haptic Vibration"
                hapticSwitch.isOn = UserDefaults.standard.bool(forKey: "TouchStage_HapticsEnabled")
                hapticSwitch.addTarget(self, action: #selector(onHapticToggled), for: .valueChanged)
                cell.accessoryView = hapticSwitch
            }

        case 3:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Stage 8-Track (Mixer, Pads & Knobs)"
                cell.detailTextLabel?.text = "8 Channels aligned to 20px grid"
            } else {
                cell.textLabel?.text = "16-Pad Matrix (Drum Grid)"
                cell.detailTextLabel?.text = "4x4 velocity illuminated pads"
            }

        default:
            break
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && !discoveredServers.isEmpty {
            let s = discoveredServers[indexPath.row]
            NetworkManager.shared.connect(to: s.ip, port: s.port, name: s.name)
            tableView.reloadData()
        } else if indexPath.section == 3 {
            if indexPath.row == 0 {
                delegate?.settingsDidSelectPreset(LayoutModel.presetStage8Track())
            } else {
                delegate?.settingsDidSelectPreset(LayoutModel.presetDrumPads())
            }
            dismiss(animated: true)
        }
    }

    @objc private func onManualConnect() {
        guard let ip = ipTextField.text, !ip.isEmpty else { return }
        NetworkManager.shared.connect(to: ip, port: 9000, name: "Manual IP")
        tableView.reloadData()
    }

    @objc private func onSidebarPositionChanged() {
        let posNames = ["Left", "Right", "Top", "Bottom"]
        let pos = posNames[sidebarSegment.selectedSegmentIndex]
        delegate?.settingsDidUpdateSidebarPosition(pos)
    }

    @objc private func onHapticToggled() {
        UserDefaults.standard.set(hapticSwitch.isOn, forKey: "TouchStage_HapticsEnabled")
    }
}

extension SettingsModalViewController: NetworkDiscoveryDelegate {
    public func networkDiscoveryDidUpdateServers(_ servers: [DiscoveredServer]) {
        self.discoveredServers = servers
        tableView.reloadData()
    }
}
