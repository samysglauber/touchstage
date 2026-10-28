import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct CardContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .white.opacity(0.7) : .white)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.065))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08), lineWidth: 0.5)
                    )
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DeviceRowView: View {
    let name: String
    let ipAddress: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                .frame(width: 18, height: 18)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? "Android Device" : name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(ipAddress.isEmpty ? "Wi-Fi" : ipAddress) • Connected")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("Ready")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(Color(red: 0.25, green: 0.85, blue: 0.45))
                .padding(.horizontal, 10)
                .frame(height: 18)
                .background(
                    Capsule()
                        .fill(Color(red: 0.2, green: 0.82, blue: 0.4).opacity(0.15))
                )
        }
        .frame(height: 29)
    }
}

struct BridgeView: View {
    @ObservedObject var state: BridgeState
    var closePopover: () -> Void = {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Network / Server Card (top margin adjusted to 16 pt to match 14 pt lateral margin)
            CardContainer {
                VStack(spacing: 0) {
                    // Row 1: CoreMIDI
                    HStack(spacing: 8) {
                        Image(systemName: "pianokeys")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        
                        Text("MIDI Port")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("TouchStage Controller")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    
                    // Hairline separator inside card
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                    
                    // Row 2: Wi-Fi IP
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        
                        Text("Wi-Fi IP")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(state.localIP):\(state.port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        
                        Button(action: {
                            state.copyIP()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(state.isCopied ? Color(red: 0.2, green: 0.82, blue: 0.4).opacity(0.18) : Color.white.opacity(0.06))
                                    .frame(width: 24, height: 22)
                                
                                Image(systemName: state.isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(state.isCopied ? Color(red: 0.25, green: 0.85, blue: 0.45) : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(state.isCopied ? "Copied!" : "Copy IP and Port")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 35)
                }
            }
            .frame(height: 70)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            
            // 2. Section Header: Connected Devices
            Text(state.devices.isEmpty ? "CONNECTED DEVICES" : "CONNECTED DEVICES (\(state.devices.count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            
            // 3. Connected Devices Container Card (Adaptive)
            CardContainer {
                if state.devices.isEmpty {
                    // Empty state
                    VStack(spacing: 4) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 17, weight: .light))
                            .foregroundColor(Color.white.opacity(0.35))
                        
                        Text("Waiting for mobile devices...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                } else if state.devices.count == 1 {
                    // 1 Device: Compact 45 pt card with 8 pt top/bottom margins
                    DeviceRowView(name: state.devices[0].name ?? "Android Device",
                                  ipAddress: state.devices[0].ipAddress ?? "Wi-Fi")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: 45)
                } else if state.devices.count == 2 {
                    // 2 Devices: 82 pt card, 8 pt top/bottom/gap margins, divider centered
                    VStack(spacing: 0) {
                        DeviceRowView(name: state.devices[0].name ?? "Android Device",
                                      ipAddress: state.devices[0].ipAddress ?? "Wi-Fi")
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, 26)
                            .padding(.trailing, 12)
                            .padding(.vertical, 3.5)
                        
                        DeviceRowView(name: state.devices[1].name ?? "Android Device",
                                      ipAddress: state.devices[1].ipAddress ?? "Wi-Fi")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(height: 82)
                } else {
                    // 3+ Devices: Scrollable with height capped at 82 pt
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(0..<state.devices.count, id: \.self) { idx in
                                if idx > 0 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.05))
                                        .frame(height: 1)
                                        .padding(.leading, 26)
                                        .padding(.trailing, 12)
                                        .padding(.vertical, 3.5)
                                }
                                DeviceRowView(name: state.devices[idx].name ?? "Android Device",
                                              ipAddress: state.devices[idx].ipAddress ?? "Wi-Fi")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 82)
                }
            }
            .padding(.horizontal, 14)
            
            // 4. Hairline Separator before footer
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 12)
                .padding(.bottom, 10)
            
            // 5. Footer Buttons (Native Capsule Pills)
            HStack {
                Button(action: {
                    state.openEditor(closePopover: closePopover)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Open Editor")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                }
                .buttonStyle(PillButtonStyle())
                
                Spacer()
                
                Button(action: {
                    state.quit()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("Quit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 320, height: state.expectedHeight)
        .background(VisualEffectBackground().ignoresSafeArea())
        .ignoresSafeArea()
    }
}
