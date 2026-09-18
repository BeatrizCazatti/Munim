extension Calendar {
    static var dashboard: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        cal.firstWeekday = 1
        return cal
    }
}

import SwiftUI

/// Um intervalo inclusivo de datas usado pelo navegador de período do dashboard.
struct WeekRange: Equatable {
    let start: Date
    let end: Date

    /// Cria o intervalo padrão de uma semana, de domingo a sábado.
    init(start: Date, calendar: Calendar = .dashboard) {
        let day = calendar.startOfDay(for: start)
        let interval = calendar.dateInterval(of: .weekOfYear, for: day)
        self.start = interval?.start ?? day
        self.end = calendar.date(byAdding: .day, value: 6, to: self.start) ?? self.start
    }

    init(start: Date, end: Date, calendar: Calendar = .dashboard) {
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        let s = min(normalizedStart, normalizedEnd)
        let rawEnd = max(normalizedStart, normalizedEnd)

        // Limita o volume máximo a 30 dias
        let maxAllowedEnd = calendar.date(byAdding: .day, value: 29, to: s) ?? rawEnd
        let clampedEnd = min(rawEnd, maxAllowedEnd)

        self.start = s
        self.end = clampedEnd
    }

    func contains(_ date: Date, calendar: Calendar = .dashboard) -> Bool {
        let startOfDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) else {
            return date >= startOfDay && date <= end
        }
        return date >= startOfDay && date <= endOfDay
    }
}

/// Date-range picker de mês único. A seleção é aplicada imediatamente ao binding.
struct WeekRangePicker: View {
    @Binding var selection: WeekRange

    @State private var displayedMonth: Date
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectionPhase: SelectionPhase

    @Environment(\.appTheme) private var theme

    private let calendar = Calendar.dashboard

    init(selection: Binding<WeekRange>) {
        self._selection = selection
        let initialRange = selection.wrappedValue
        self._displayedMonth = State(initialValue: Self.month(containing: initialRange.start))
        self._startDate = State(initialValue: initialRange.start)
        self._endDate = State(initialValue: initialRange.end)
        self._selectionPhase = State(initialValue: initialRange == WeekRange(start: Date()) ? .defaultWeek : .complete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selecione um período (máx. 30 dias)")
//                .font(.title2.weight(.semibold))
                .adaptiveTextStyle(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(theme.calendar)
                .padding(.bottom, 28)

            HStack {
                Text(monthTitle)
//                    .font(.title3.weight(.semibold))
                    .adaptiveTextStyle(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.secondary)
                Spacer()
                monthButton(systemImage: "chevron.left", label: "Mês anterior") {
                    changeMonth(by: -1)
                }
                monthButton(systemImage: "chevron.right", label: "Próximo mês") {
                    changeMonth(by: 1)
                }
            }
            .padding(.bottom, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
//                        .font(.caption.weight(.semibold))
                        .adaptiveTextStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }

                ForEach(daysInMonth) { day in
                    if day.isWithinDisplayedMonth {
                        CalendarDayButton(
                            day: day,
                            state: selectionState(for: day.date),
                            isToday: calendar.isDateInToday(day.date),
                            action: { select(day.date) }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 380)
        .background(Color.Token.surfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private extension WeekRangePicker {
    var monthTitle: String {
        displayedMonth.formatted(.dateTime.locale(Locale(identifier: "pt_BR")).month(.wide).year())
            .capitalized
    }

    var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        var symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        if calendar.firstWeekday == 2, !symbols.isEmpty {
            symbols.append(symbols.removeFirst())
        }
        return symbols
    }

    var daysInMonth: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else { return [] }

        var days: [CalendarDay] = []
        var currentDate = monthFirstWeek.start

        while currentDate < monthLastWeek.end {
            let isWithinMonth = calendar.isDate(currentDate, equalTo: displayedMonth, toGranularity: .month)
            days.append(CalendarDay(date: currentDate, isWithinDisplayedMonth: isWithinMonth))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return days
    }

    static func month(containing date: Date, calendar: Calendar = .dashboard) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func selectionState(for date: Date) -> CalendarDaySelectionState {
        if calendar.isDate(date, inSameDayAs: startDate) && calendar.isDate(date, inSameDayAs: endDate) {
            return .single
        }
        if calendar.isDate(date, inSameDayAs: startDate) { return .start }
        if calendar.isDate(date, inSameDayAs: endDate) { return .end }
        return date > startDate && date < endDate ? .middle : .none
    }

    func select(_ date: Date) {
        let selectedDay = calendar.startOfDay(for: date)
        switch selectionPhase {
        case .complete:
            if calendar.isDate(selectedDay, inSameDayAs: startDate),
               !calendar.isDate(startDate, inSameDayAs: endDate) {
                selectSingleDay(endDate)
                return
            }
            if calendar.isDate(selectedDay, inSameDayAs: endDate) {
                selectSingleDay(startDate)
                return
            }
            selectSingleDay(selectedDay)
        case .defaultWeek:
            selectSingleDay(selectedDay)
        case .awaitingEnd:
            guard !calendar.isDate(selectedDay, inSameDayAs: startDate) else { return }
            let range = WeekRange(start: startDate, end: selectedDay, calendar: calendar)
            startDate = range.start
            endDate = range.end
            selectionPhase = .complete
            selection = range
        }
    }

    func selectSingleDay(_ date: Date) {
        startDate = date
        endDate = date
        selectionPhase = .awaitingEnd
        selection = WeekRange(start: date, end: date, calendar: calendar)
    }

    func changeMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            displayedMonth = month
        }
    }

    func monthButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
//                .font(.subheadline.weight(.semibold))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.calendar)
        .background(Capsule().fill(theme.calendar.opacity(0.09)))
        .accessibilityLabel(label)
    }
}

private enum SelectionPhase {
    case defaultWeek
    case awaitingEnd
    case complete
}

private struct CalendarDayButton: View {
    let day: CalendarDay
    let state: CalendarDaySelectionState
    let isToday: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .overlay { rangeHighlight }
                .overlay { dayIndicator }
                .overlay {
                    Text(day.date.formatted(.dateTime.day()))
//                        .font(.body.weight(.medium))
                        .adaptiveTextStyle(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(foregroundColor)
                        .frame(width: 42, height: 42)
                }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var rangeHighlight: some View {
        switch state {
        case .middle:
            Rectangle()
                .fill(theme.calendar.opacity(0.18))
        case .start:
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(theme.calendar.opacity(0.18))
                    .frame(maxWidth: .infinity)
            }
        case .end:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.calendar.opacity(0.18))
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        case .single, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dayIndicator: some View {
        switch state {
        case .single, .start, .end:
            Circle()
                .fill(theme.calendar)
                .frame(width: 36, height: 36)
        case .none:
            if isToday {
                Circle()
                    .stroke(theme.calendar, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
            } else if isHovering {
                Circle()
                    .fill(theme.calendar.opacity(0.12))
                    .frame(width: 36, height: 36)
            }
        case .middle:
            EmptyView()
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .single, .start, .end:
            .white
        case .middle:
            theme.calendar
        case .none:
            Color.primary
        }
    }
}

private struct CalendarDay: Identifiable {
    var id: Date { date }
    let date: Date
    let isWithinDisplayedMonth: Bool
}

private enum CalendarDaySelectionState {
    case none
    case single
    case start
    case middle
    case end
}
