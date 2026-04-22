import SwiftUI

struct ControlTabView: View {
    @EnvironmentObject var vm: DataViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if settings.ownerModeEnabled {
                controlPanel
            } else {
                ownerRequiredState
            }
        }
    }

    // MARK: – Owner lock screen

    private var ownerRequiredState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Theme.tertiary)
            Text("OWNER ACCESS REQUIRED")
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.headerTracking)
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
    }

    // MARK: – Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 12) {

                SectionCard(title: "CONFIGURATION") {
                    VStack(spacing: 12) {

                        pickerRow(label: "ND FILTER") {
                            Picker("ND", selection: $vm.ndPosition) {
                                Text("CLEAR").tag(0)
                                Text("ND2").tag(2)
                                Text("ND4").tag(4)
                                Text("ND6").tag(6)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: vm.ndPosition) { _, val in Task { await vm.setND(val) } }
                        }

                        HRule()

                        pickerRow(label: "ISO") {
                            Picker("ISO", selection: $vm.iso) {
                                Text("400").tag(400)
                                Text("3200").tag(3200)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: vm.iso) { _, val in Task { await vm.setISO(val) } }
                        }

                        HRule()

                        pickerRow(label: "SHUTTER ANGLE") {
                            Picker("SHUTTER", selection: $vm.shutterAngle) {
                                Text("90").tag(90.0)
                                Text("120").tag(120.0)
                                Text("172.8").tag(172.8)
                                Text("180").tag(180.0)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: vm.shutterAngle) { _, val in Task { await vm.setShutterAngle(val) } }
                        }

                        HRule()

                        pickerRow(label: "WHITE BALANCE") {
                            Picker("WB", selection: $vm.wbKelvin) {
                                Text("3200K").tag(3200)
                                Text("4500K").tag(4500)
                                Text("5600K").tag(5600)
                                Text("AUTO").tag(0)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: vm.wbKelvin) { _, val in Task { await vm.setWB(val) } }
                        }

                        HRule()

                        pickerRow(label: "FRAME RATE") {
                            Picker("FPS", selection: $vm.fps) {
                                Text("24").tag(24)
                                Text("25").tag(25)
                                Text("30").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: vm.fps) { _, val in Task { await vm.setFPS(val) } }
                        }
                    }
                }

                Button(action: { settings.lockOwnerMode() }) {
                    Text("LOCK OWNER MODE")
                        .font(.system(size: 13, weight: .regular))
                        .tracking(Theme.headerTracking)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
    }

    private func pickerRow<P: View>(label: String, @ViewBuilder picker: () -> P) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.secondary)
            picker()
        }
    }
}
