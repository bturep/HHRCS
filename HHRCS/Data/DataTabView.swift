import SwiftUI

struct DataTabView: View {
    @EnvironmentObject var vm: DataViewModel


    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DATA")
                    .font(Theme.label(size: 11))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.text1)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)
            .frame(height: 32)
            HRule().padding(.horizontal, Theme.pagePadding)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    cameraSection
                    enclosureSection
                    weatherSection
                    astroSection
                    storageSection
                }
                .padding(Theme.pagePadding)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await vm.refreshWeather()
                await vm.refreshAstro()
            }
        }
        .background(Theme.background)
    }

    // MARK: – Camera (BMPCC via ethernet)
    private var cameraSection: some View {
        let codecDisplay: String = {
            if let v = vm.camCodecVariant { return v }
            return vm.camCodec
        }()
        return SectionCard(title: "CAMERA") {
            VStack(spacing: 12) {
                // CODEC (with variant) · SHUTTER · spacer
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: codecDisplay, label: "CODEC")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.camShutterAngle.map { String(format: "%.1f°", $0) } ?? "—",
                        label: "SHUTTER ANG"
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer().frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                // ISO · WHITE BAL · GAIN
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camIso.map { "\($0)" } ?? "—", label: "ISO")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camWhiteBalance.map { "\($0)K" } ?? "—", label: "WHITE BAL")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camGain.map { "\($0) dB" } ?? "—", label: "GAIN")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                // MEDIA SLOT · REC TIME LEFT · spacer
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camActiveMediaSlot, label: "MEDIA SLOT")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.camRemainingRecordTime.map { "\($0 / 60)m \($0 % 60)s" } ?? "—",
                        label: "REC TIME LEFT"
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer().frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                // FORMAT · spacer · spacer
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camFormatDetails ?? "—", label: "FORMAT")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                // MEDIA VOL · CLIP COUNT · SPACE REM
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camMediaVolume ?? "—", label: "MEDIA VOL")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camMediaClipCount.map { "\($0)" } ?? "—", label: "CLIP COUNT")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.camMediaSpaceRemainingGb.map { String(format: "%.1f GB", $0) } ?? "—",
                        label: "SPACE REM"
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: – Enclosure (two rows of 3)
    private var enclosureSection: some View {
        SectionCard(title: "ENCLOSURE") {
            VStack(spacing: 12) {
                // Row 1: TEMPERATURE, HUMIDITY, DEW POINT
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(
                        value: vm.enclosureTempC.map { String(format: "%.1f°C", $0) } ?? "—",
                        label: "TEMPERATURE",
                        valueSize: 17,
                        valueColor: vm.enclosureTempC == nil ? Theme.tertiary : .white
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.enclosureHumidity.map { String(format: "%.0f%%", $0) } ?? "—",
                        label: "HUMIDITY",
                        valueSize: 17,
                        valueColor: vm.enclosureHumidity == nil ? Theme.tertiary : .white
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.dewPoint.map { String(format: "%.1f°C", $0) } ?? "—",
                        label: "DEW POINT",
                        valueColor: vm.dewPoint == nil ? Theme.tertiary : .white
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                // Row 2: PRESSURE, CPU TEMP
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(
                        value: vm.pressure.map { String(format: "%.1f", $0) } ?? "—",
                        label: "PRESSURE hPa",
                        valueColor: vm.pressure == nil ? Theme.tertiary : .white
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: String(format: "%.1f°C", vm.cpuTemp), label: "CPU TEMP", valueSize: 17)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: – Weather
    private var weatherSection: some View {
        SectionCard(title: "WEATHER  ·  PROSPECT LAKE") {
            if vm.weather == nil && vm.weatherError == nil {
                ProgressView().scaleEffect(0.6).tint(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let w = vm.weather {
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: String(format: "%.1f°C", w.current.temperatureC), label: "TEMPERATURE", valueSize: 17)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    // Icon column — centered vertically
                    VStack {
                        Spacer(minLength: 0)
                        Image(systemName: WeatherService.sfSymbol(for: w.current.weatherCode))
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    MetricCell(value: String(format: "%.0f km/h", w.current.windspeedKmh), label: "WIND", valueSize: 17)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                HRule()

                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(w.hourly.enumerated()), id: \.offset) { _, hour in
                            HourCell(hour: hour)
                        }
                    }
                }
                .scrollIndicators(.hidden)

            } else if let err = vm.weatherError {
                Text(err)
                    .font(Theme.statusCaption())
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: – Astro
    private var astroSection: some View {
        SectionCard(title: "ASTRO") {
            if vm.astro == nil && vm.astroError == nil {
                ProgressView().scaleEffect(0.6).tint(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let a = vm.astro {
                AstroArcView(astro: a)
            } else if let err = vm.astroError {
                Text(err)
                    .font(Theme.statusCaption())
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: – Storage
    private var storageSection: some View {
        SectionCard(title: "STORAGE") {
            VStack(spacing: 12) {
                if !vm.externalDrives.isEmpty {
                    ForEach(vm.externalDrives) { drive in
                        BarCell(
                            label:    drive.name.uppercased(),
                            percent:  drive.usedPercent,
                            subtitle: String(format: "%.2f TB of %.2f TB", drive.usedTB, drive.totalTB)
                        )
                        if drive.id != vm.externalDrives.last?.id {
                            HRule()
                        }
                    }
                }

                if let usedPct = vm.storageUsedPct,
                   let freeGb  = vm.storageFreeGb,
                   let totalGb = vm.storageTotalGb {
                    if !vm.externalDrives.isEmpty { HRule() }
                    BarCell(
                        label:    "SSD",
                        percent:  usedPct,
                        subtitle: String(format: "%.1f GB free  ·  %.0f GB total", freeGb, totalGb)
                    )
                    if let days = vm.storageDaysRemaining,
                       let rate = vm.storageBurnRateGbPerDay {
                        HStack(alignment: .top, spacing: 0) {
                            MetricCell(
                                value: String(format: "%.0f days", days),
                                label: "EST. REMAINING"
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            MetricCell(
                                value: String(format: "%.1f GB/day", rate),
                                label: "BURN RATE"
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

}

// MARK: – Hourly cell
private struct HourCell: View {
    let hour: WeatherData.HourForecast

    var body: some View {
        VStack(spacing: 5) {
            Text(hour.time)
                .font(Theme.label(size: 9))
                .foregroundStyle(Theme.tertiary)
            Image(systemName: WeatherService.sfSymbol(for: hour.weatherCode))
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            Text(String(format: "%.0f°", hour.temperatureC))
                .font(Theme.label(size: 11))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 48)
        .padding(.vertical, 4)
    }
}
