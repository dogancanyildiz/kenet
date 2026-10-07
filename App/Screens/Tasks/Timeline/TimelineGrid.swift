import SwiftUI
import VaultFormat

struct TimelineGrid: View {
    let days: [CalendarDate]
    let today: CalendarDate
    let dayWidth: CGFloat
    var body: some View {
        Canvas { context, size in
            for (index, day) in days.enumerated() {
                let x = CGFloat(index) * dayWidth
                if day.weekday >= 5 {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.ink.well))
                }
                if day.weekday == 0 {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(Color.ink.rule), lineWidth: 1)
                }
                if day == today {
                    let center = x + dayWidth / 2
                    var path = Path()
                    path.move(to: CGPoint(x: center, y: 0))
                    path.addLine(to: CGPoint(x: center, y: size.height))
                    context.stroke(path, with: .color(Color.ink.accent), lineWidth: InkStroke.highPriority)
                }
            }
        }.accessibilityHidden(true)
    }
}
