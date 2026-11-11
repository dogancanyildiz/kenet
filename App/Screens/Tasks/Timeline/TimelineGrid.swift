import SwiftUI
import VaultFormat

struct TimelineGrid: View {
    let days: [CalendarDate]
    let today: CalendarDate
    let dayWidth: CGFloat
    var showsWeekends = true
    /// Where the vertical lines start: under the axis' date row, so neither the week rules nor
    /// the today line cross a date label (fark3 P6).
    var lineTop: CGFloat = 0
    var body: some View {
        Canvas { context, size in
            for (index, day) in days.enumerated() {
                let x = CGFloat(index) * dayWidth
                if showsWeekends && day.weekday >= 5 {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.ink.well))
                }
                if day.weekday == 0 {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: lineTop))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(Color.ink.rule), lineWidth: 1)
                }
                if day == today {
                    let center = x + dayWidth / 2
                    var path = Path()
                    path.move(to: CGPoint(x: center, y: lineTop))
                    path.addLine(to: CGPoint(x: center, y: size.height))
                    context.stroke(path, with: .color(Color.ink.accent), lineWidth: InkStroke.highPriority)
                }
            }
        }.accessibilityHidden(true)
    }
}
