import SwiftUI

// Horizontal day-timeline. DAWN/DUSK show labels + times above the line. RISE/SET show tick marks only.
struct AstroArcView: View {
    let astro: AstroData
    private let tz = TimeZone(identifier: "America/Vancouver")!

    private func dayFraction(_ date: Date) -> Double {
        var cal = Calendar.current
        cal.timeZone = tz
        let sod = cal.startOfDay(for: date)
        return date.timeIntervalSince(sod) / 86400.0
    }

    var body: some View {
        Canvas { ctx, size in
            let totalDuration = astro.civilDusk.timeIntervalSince(astro.civilDawn)
            guard totalDuration > 0 else { return }

            let margin: CGFloat = 10
            let lineY:  CGFloat = 38
            let lo = margin
            let hi = size.width - margin
            let span = hi - lo

            func xOf(_ f: Double) -> CGFloat { lo + CGFloat(f) * span }

            let dawnF = dayFraction(astro.civilDawn)
            let riseF = dayFraction(astro.sunrise)
            let setF  = dayFraction(astro.sunset)
            let duskF = dayFraction(astro.civilDusk)
            let nowF  = dayFraction(Date())

            // ── Three line segments ─────────────────────────────────────
            let nightColor = Color(white: 0.20)
            let dayColor   = Color(white: 0.46)

            for (x0, x1, w, c): (CGFloat, CGFloat, CGFloat, Color) in [
                (xOf(0),     xOf(dawnF), 1, nightColor),
                (xOf(dawnF), xOf(duskF), 2, dayColor),
                (xOf(duskF), xOf(1.0),  1, nightColor),
            ] {
                ctx.stroke(Path { p in
                    p.move(to:    .init(x: x0, y: lineY))
                    p.addLine(to: .init(x: x1, y: lineY))
                }, with: .color(c), lineWidth: w)
            }

            // ── Four event ticks; DAWN/DUSK get labels, RISE/SET tick only ──
            let aboveName: CGFloat = 22
            let aboveTime: CGFloat = 11

            let events: [(f: Double, name: String, time: String, up: Bool, labeled: Bool)] = [
                (dawnF, "DAWN", AstroService.format(astro.civilDawn), true,  true),
                (riseF, "RISE", AstroService.format(astro.sunrise),   false, false),
                (setF,  "SET",  AstroService.format(astro.sunset),    false, false),
                (duskF, "DUSK", AstroService.format(astro.civilDusk), true,  true),
            ]

            for ev in events {
                let x = xOf(ev.f)
                let tickEnd: CGFloat = ev.up ? lineY - 7 : lineY + 7

                ctx.stroke(Path { p in
                    p.move(to:    .init(x: x, y: lineY))
                    p.addLine(to: .init(x: x, y: tickEnd))
                }, with: .color(Color(white: 0.44)), lineWidth: 0.75)

                guard ev.labeled else { continue }

                ctx.draw(
                    Text(ev.name)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundColor(.white),
                    at: .init(x: x, y: aboveName), anchor: .center
                )
                ctx.draw(
                    Text(ev.time)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white),
                    at: .init(x: x, y: aboveTime), anchor: .center
                )
            }

            // ── Current-time dot ─────────────────────────────────────────
            if nowF > 0 && nowF < 1 {
                let x = xOf(nowF)
                ctx.fill(
                    Path(ellipseIn: .init(x: x - 4, y: lineY - 4, width: 8, height: 8)),
                    with: .color(Theme.accent)
                )
            }
        }
        .frame(height: 56)
    }
}
