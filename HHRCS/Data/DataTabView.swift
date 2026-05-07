import SwiftUI

struct DataTabView: View {
    @EnvironmentObject var vm: DataViewModel


    var body: some View {
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
        .background(Theme.background)
        .refreshable {
            await vm.refreshWeather()
            await vm.refreshAstro()
        }
    }

    // MARK: – Camera (BMPCC via ethernet)
    private var cameraSection: some View {
        SectionCard(title: "CAMERA") {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camCodec, label: "CODEC")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camFrameRate, label: "FRAME RATE")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camResolution, label: "RESOLUTION")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: vm.camIso.map { "\($0)" } ?? "—", label: "ISO")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camWhiteBalance.map { "\($0)K" } ?? "—", label: "WHITE BAL")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camGain.map { "\($0) dB" } ?? "—", label: "GAIN")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 0) {
                    let recLabel: String = {
                        switch vm.recordingState {
                        case .recording:  return "YES"
                        case .finalizing: return "FINALIZING"
                        case .idle:       return "NO"
                        }
                    }()
                    let recColor: Color = {
                        switch vm.recordingState {
                        case .recording:  return Theme.dotRed
                        case .finalizing: return Theme.accentColor
                        case .idle:       return .white
                        }
                    }()
                    MetricCell(
                        value:      recLabel,
                        label:      "RECORDING",
                        valueColor: recColor
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.camActiveMediaSlot, label: "MEDIA SLOT")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(
                        value: vm.camRemainingRecordTime.map { "\($0 / 60)m \($0 % 60)s" } ?? "—",
                        label: "REC TIME LEFT"
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
                    MetricCell(value: String(format: "%.1f°", vm.enclosureTempC), label: "TEMPERATURE")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: String(format: "%.0f%%", vm.enclosureHumidity), label: "HUMIDITY")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: String(format: "%.1f°", vm.dewPoint), label: "DEW POINT")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                // Row 2: PRESSURE, CPU TEMP, TIMECODE
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(value: String(format: "%.1f", vm.pressure), label: "PRESSURE hPa")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: String(format: "%.1f°", vm.cpuTemp), label: "CPU TEMP")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    MetricCell(value: vm.smpteTimecode, label: "TIMECODE", valueSize: 13)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    MetricCell(value: String(format: "%.1f°C", w.current.temperatureC), label: "TEMPERATURE")
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

                    MetricCell(value: String(format: "%.0f km/h", w.current.windspeedKmh), label: "WIND")
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)

                HRule()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(w.hourly.enumerated()), id: \.offset) { _, hour in
                            HourCell(hour: hour)
                        }
                    }
                }

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
                BarCell(
                    label:    "HOUSE DRIVE",
                    percent:  vm.driveUsedPercent,
                    subtitle: String(format: "%.1f TB of %.1f TB", vm.driveUsedTB, vm.driveTotalTB)
                )

                if let usedPct = vm.storageUsedPct,
                   let freeGb  = vm.storageFreeGb,
                   let totalGb = vm.storageTotalGb {
                    HRule()
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
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
            Image(systemName: WeatherService.sfSymbol(for: hour.weatherCode))
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            Text(String(format: "%.0f°", hour.temperatureC))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 48)
        .padding(.vertical, 4)
    }
}
