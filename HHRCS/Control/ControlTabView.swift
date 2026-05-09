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

    // MARK: – ISO / WB constants

    private let isoStops   = [100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600]
    private let wbPresets: [(String, Int)] = [
        ("TUNG", 3200), ("FLUO", 4000), ("SUN", 5600), ("CLOUD", 6500), ("SHADE", 7500)
    ]

    // MARK: – Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 12) {

                SectionCard(title: "CONFIGURATION") {
                    VStack(spacing: 12) {

                        isoRow
                        HRule()
                        wbRow
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
                    }
                }

                Button(action: { settings.lockOwnerMode() }) {
                    Text("LOCK OWNER MODE")
                        .font(Theme.label(size: 11))
                        .tracking(Theme.headerTracking)
                        .foregroundStyle(Theme.text2)
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
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }

    // MARK: – ISO slider row

    private var isoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ISO")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(vm.iso)")
                    .font(Theme.body(size: 11))
                    .foregroundStyle(.white)
            }
            Slider(
                value: Binding(
                    get: { Double(isoStops.firstIndex(of: vm.iso) ?? 3) },
                    set: { vm.iso = isoStops[Int($0.rounded())] }
                ),
                in: 0...Double(isoStops.count - 1),
                step: 1
            ) { editing in
                if !editing { Task { await vm.setISO(vm.iso) } }
            }
            .tint(Theme.text1)
        }
    }

    // MARK: – White balance slider + presets row

    private var wbRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WHITE BALANCE")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(vm.wbKelvin) K")
                    .font(Theme.body(size: 11))
                    .foregroundStyle(.white)
            }
            Slider(
                value: Binding(
                    get: { Double(vm.wbKelvin) },
                    set: { vm.wbKelvin = Int($0.rounded()) }
                ),
                in: 2500...10000,
                step: 100
            ) { editing in
                if !editing { Task { await vm.setWB(vm.wbKelvin) } }
            }
            .tint(Theme.text1)

            HStack(spacing: 6) {
                ForEach(wbPresets, id: \.0) { name, kelvin in
                    Button(name) {
                        vm.wbKelvin = kelvin
                        Task { await vm.setWB(kelvin) }
                    }
                    .font(Theme.label(size: 8))
                    .tracking(1.0)
                    .foregroundStyle(vm.wbKelvin == kelvin ? settings.activeColor : Theme.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                vm.wbKelvin == kelvin ? settings.activeColor.opacity(0.5) : Theme.rule,
                                lineWidth: Theme.ruleWidth
                            )
                    )
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
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
