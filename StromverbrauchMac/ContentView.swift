import Charts
import SwiftUI

struct MeterReading: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var value: Double
    var pricePerKilowattHour: Double

    init(
        id: UUID = UUID(),
        date: Date,
        value: Double,
        pricePerKilowattHour: Double
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.pricePerKilowattHour = pricePerKilowattHour
    }
}

private struct MonthPeriod: Identifiable, Hashable {
    let startDate: Date

    var id: Date { startDate }
}

private struct DailyConsumption: Identifiable {
    let id: UUID
    let date: Date
    let kilowattHours: Double

    var color: Color {
        switch kilowattHours {
        case ...20:
            .green
        case ...50:
            .orange
        default:
            .red
        }
    }
}

private struct MonthlyEstimate {
    let measuredConsumption: Double
    let observedDays: Int
    let projectedConsumption: Double
    let projectedCost: Double
}

private struct AnnualForecast {
    let annualCost: Double
    let paidInInstallments: Double
    let recommendedMonthlyInstallment: Double

    var difference: Double {
        paidInInstallments - annualCost
    }
}

struct ContentView: View {
    @AppStorage("meterReadings") private var storedReadings = ""
    @AppStorage("pricePerKilowattHour") private var pricePerKilowattHour = 0.35
    @AppStorage("monthlyBasePrice") private var monthlyBasePrice = 0.0
    @AppStorage("currentMonthlyInstallment") private var currentMonthlyInstallment = 0.0

    @State private var readings: [MeterReading] = []
    @State private var showingAddReading = false
    @State private var showingTariffSettings = false

    private var sortedReadings: [MeterReading] {
        readings.sorted { $0.date < $1.date }
    }

    private var availableMonths: [MonthPeriod] {
        let calendar = Calendar.current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let months = Set(readings.map {
            MonthPeriod(
                startDate: calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
            )
        })

        return Array(months.union([MonthPeriod(startDate: currentMonth)]))
            .sorted { $0.startDate > $1.startDate }
    }

    private var currentMonthEstimate: MonthlyEstimate? {
        let currentMonthReadings = sortedReadings.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }
        guard
            let first = currentMonthReadings.first,
            let last = currentMonthReadings.last,
            currentMonthReadings.count > 1,
            let dayRange = Calendar.current.range(of: .day, in: .month, for: Date())
        else {
            return nil
        }

        let observedDays = max(
            Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0,
            1
        )
        let measuredConsumption = max(last.value - first.value, 0)
        let projectedConsumption = measuredConsumption / Double(observedDays) * Double(dayRange.count)

        return MonthlyEstimate(
            measuredConsumption: measuredConsumption,
            observedDays: observedDays,
            projectedConsumption: projectedConsumption,
            projectedCost: projectedConsumption * pricePerKilowattHour + monthlyBasePrice
        )
    }

    private var annualForecast: AnnualForecast? {
        guard let currentMonthEstimate, currentMonthlyInstallment > 0 else { return nil }

        let annualCost = currentMonthEstimate.projectedCost * 12
        return AnnualForecast(
            annualCost: annualCost,
            paidInInstallments: currentMonthlyInstallment * 11,
            recommendedMonthlyInstallment: annualCost / 11
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    StartHeader()
                    AnnualForecastCard(
                        forecast: annualForecast,
                        currentMonthlyInstallment: currentMonthlyInstallment,
                        onEdit: { showingTariffSettings = true }
                    )
                    MonthPicker(months: availableMonths, readings: readings)
                    TariffOverview(
                        pricePerKilowattHour: pricePerKilowattHour,
                        monthlyBasePrice: monthlyBasePrice,
                        onEdit: { showingTariffSettings = true }
                    )
                }
                .padding()
            }
            .background(.background)
            .navigationTitle("Stromverbrauch")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddReading = true
                    } label: {
                        Label("Tageswert erfassen", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingTariffSettings = true
                    } label: {
                        Label("Tarif bearbeiten", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationDestination(for: MonthPeriod.self) { month in
                MonthDetailView(
                    month: month,
                    readings: sortedReadings,
                    pricePerKilowattHour: pricePerKilowattHour,
                    monthlyBasePrice: monthlyBasePrice,
                    onDelete: deleteReading
                )
            }
            .sheet(isPresented: $showingAddReading) {
                AddReadingView(
                    pricePerKilowattHour: pricePerKilowattHour,
                    onSave: addReading
                )
            }
            .sheet(isPresented: $showingTariffSettings) {
                TariffSettingsView(
                    pricePerKilowattHour: $pricePerKilowattHour,
                    monthlyBasePrice: $monthlyBasePrice,
                    currentMonthlyInstallment: $currentMonthlyInstallment
                )
            }
            .task {
                loadReadings()
            }
        }
    }

    private func addReading(_ reading: MeterReading) {
        readings.append(reading)
        saveReadings()
    }

    private func deleteReading(_ reading: MeterReading) {
        readings.removeAll { $0.id == reading.id }
        saveReadings()
    }

    private func loadReadings() {
        guard
            let data = storedReadings.data(using: .utf8),
            let decodedReadings = try? JSONDecoder().decode([MeterReading].self, from: data)
        else {
            return
        }

        readings = decodedReadings
    }

    private func saveReadings() {
        guard
            let data = try? JSONEncoder().encode(readings),
            let encodedReadings = String(data: data, encoding: .utf8)
        else {
            return
        }

        storedReadings = encodedReadings
    }
}

private struct StartHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deine Monate")
                .font(.title2.weight(.bold))
            Text("Wähle einen Monat aus, um seine täglichen Zählerstände und den Verbrauch zu sehen.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnnualForecastCard: View {
    let forecast: AnnualForecast?
    let currentMonthlyInstallment: Double
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Jahreshochrechnung", systemImage: "calendar.badge.clock")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Abschlag ändern", action: onEdit)
                    .buttonStyle(.borderless)
            }

            if let forecast {
                LabeledContent(
                    "Prognostizierte Jahreskosten",
                    value: forecast.annualCost.formatted(.currency(code: "EUR"))
                )
                LabeledContent(
                    "11 Abschläge à \(currentMonthlyInstallment.formatted(.currency(code: "EUR")))",
                    value: forecast.paidInInstallments.formatted(.currency(code: "EUR"))
                )
                LabeledContent(
                    "Empfohlener Abschlag",
                    value: forecast.recommendedMonthlyInstallment.formatted(.currency(code: "EUR"))
                )

                Text(forecast.difference >= 0
                    ? "Voraussichtlich \(forecast.difference.formatted(.currency(code: "EUR")))) Guthaben im Abrechnungsmonat."
                    : "Voraussichtlich \((-forecast.difference).formatted(.currency(code: "EUR"))) Nachzahlung im Abrechnungsmonat."
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(forecast.difference >= 0 ? .green : .red)
            } else if currentMonthlyInstallment > 0 {
                Text("Erfasse mindestens zwei Zählerstände im laufenden Monat, damit die Jahreshochrechnung berechnet werden kann.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Trage deinen aktuellen monatlichen Abschlag in den Tarif-Einstellungen ein.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MonthPicker: View {
    let months: [MonthPeriod]
    let readings: [MeterReading]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(months) { month in
                NavigationLink(value: month) {
                    MonthCard(
                        month: month,
                        readingCount: readings.filter {
                            Calendar.current.isDate($0.date, equalTo: month.startDate, toGranularity: .month)
                        }.count
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MonthCard: View {
    let month: MonthPeriod
    let readingCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .background(.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(month.startDate, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Text("\(readingCount) tägliche Zählerstände")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MonthDetailView: View {
    let month: MonthPeriod
    let readings: [MeterReading]
    let pricePerKilowattHour: Double
    let monthlyBasePrice: Double
    let onDelete: (MeterReading) -> Void

    @State private var readingPendingDeletion: MeterReading?

    private var monthReadings: [MeterReading] {
        readings.filter {
            Calendar.current.isDate($0.date, equalTo: month.startDate, toGranularity: .month)
        }
    }

    private var dailyConsumptions: [DailyConsumption] {
        monthReadings.map { reading in
            let previousReading = readings.last { $0.date < reading.date }
            return DailyConsumption(
                id: reading.id,
                date: reading.date,
                kilowattHours: max(reading.value - (previousReading?.value ?? reading.value), 0)
            )
        }
    }

    private var estimate: MonthlyEstimate? {
        guard
            let first = monthReadings.first,
            let last = monthReadings.last,
            monthReadings.count > 1,
            let dayRange = Calendar.current.range(of: .day, in: .month, for: month.startDate)
        else {
            return nil
        }

        let observedDays = max(
            Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0,
            1
        )
        let measuredConsumption = max(last.value - first.value, 0)
        let projectedConsumption = measuredConsumption / Double(observedDays) * Double(dayRange.count)

        return MonthlyEstimate(
            measuredConsumption: measuredConsumption,
            observedDays: observedDays,
            projectedConsumption: projectedConsumption,
            projectedCost: projectedConsumption * pricePerKilowattHour + monthlyBasePrice
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MonthlyEstimateCard(estimate: estimate)
                DailyConsumptionChart(consumptions: dailyConsumptions)
                DailyReadingList(
                    readings: monthReadings,
                    onDelete: { readingPendingDeletion = $0 }
                )
            }
            .padding()
        }
        .background(.background)
        .navigationTitle(month.startDate.formatted(.dateTime.month(.wide).year()))
        .confirmationDialog(
            "Zählerstand löschen?",
            isPresented: Binding(
                get: { readingPendingDeletion != nil },
                set: { if !$0 { readingPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let readingPendingDeletion else { return }
                onDelete(readingPendingDeletion)
                self.readingPendingDeletion = nil
            }
        } message: {
            Text("Dieser tägliche Zählerstand kann nicht wiederhergestellt werden.")
        }
    }
}

private struct MonthlyEstimateCard: View {
    let estimate: MonthlyEstimate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monatliche Schätzung")
                .font(.title2.weight(.bold))

            if let estimate {
                HStack(spacing: 12) {
                    SummaryValue(
                        title: "Hochrechnung",
                        value: estimate.projectedConsumption.formatted(.number.precision(.fractionLength(0))),
                        subtitle: "kWh im Monat",
                        color: .green
                    )
                    SummaryValue(
                        title: "Abschlag",
                        value: estimate.projectedCost.formatted(.currency(code: "EUR")),
                        subtitle: "inkl. Grundpreis",
                        color: .orange
                    )
                }
                Text("\(estimate.measuredConsumption.formatted(.number.precision(.fractionLength(1)))) kWh in \(estimate.observedDays) Tagen gemessen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Erfasse mindestens zwei Tageswerte in diesem Monat, um die Hochrechnung zu sehen.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct SummaryValue: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DailyConsumptionChart: View {
    let consumptions: [DailyConsumption]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Täglicher Verbrauch")
                .font(.title2.weight(.bold))

            if consumptions.isEmpty {
                ContentUnavailableView(
                    "Noch keine Tageswerte",
                    systemImage: "chart.bar",
                    description: Text("Erfasse einen Zählerstand, um den Verbrauch zu visualisieren.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                Chart(consumptions) { consumption in
                    BarMark(
                        x: .value("Tag", consumption.date, unit: .day),
                        y: .value("Verbrauch", consumption.kilowattHours)
                    )
                    .foregroundStyle(consumption.color)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text(consumption.kilowattHours, format: .number.precision(.fractionLength(1)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxisLabel("kWh")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .frame(height: 240)

                ConsumptionLegend()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ConsumptionLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            LegendItem(color: .green, title: "bis 20 kWh")
            LegendItem(color: .orange, title: "20–50 kWh")
            LegendItem(color: .red, title: "ab 50 kWh")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct DailyReadingList: View {
    let readings: [MeterReading]
    let onDelete: (MeterReading) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tägliche Zählerstände")
                .font(.title2.weight(.bold))

            ForEach(readings.reversed()) { reading in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reading.date, format: .dateTime.day().month().year())
                            .font(.headline)
                        Text("\(reading.value.formatted(.number.precision(.fractionLength(1)))) kWh")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        onDelete(reading)
                    } label: {
                        Label("Zählerstand löschen", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TariffOverview: View {
    let pricePerKilowattHour: Double
    let monthlyBasePrice: Double
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Dein Tarif", systemImage: "eurosign.circle")
                    .font(.headline)
                Spacer()
                Button("Bearbeiten", action: onEdit)
                    .buttonStyle(.borderless)
            }
            LabeledContent("Arbeitspreis", value: "\(pricePerKilowattHour.formatted(.currency(code: "EUR"))) / kWh")
            LabeledContent("Grundpreis", value: "\(monthlyBasePrice.formatted(.currency(code: "EUR"))) / Monat")
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AddReadingView: View {
    let pricePerKilowattHour: Double
    let onSave: (MeterReading) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var meterValue = ""

    private var meterValueNumber: Double? {
        Double(meterValue.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        guard let meterValueNumber else { return false }
        return meterValueNumber >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Täglicher Zählerstand") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Zählerstand in kWh", text: $meterValue)
                }
                Section("Gespeicherter Tarif") {
                    LabeledContent("Arbeitspreis", value: "\(pricePerKilowattHour.formatted(.currency(code: "EUR"))) / kWh")
                }
            }
            .navigationTitle("Tageswert erfassen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let meterValueNumber else { return }
                        onSave(MeterReading(
                            date: date,
                            value: meterValueNumber,
                            pricePerKilowattHour: pricePerKilowattHour
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

private struct TariffSettingsView: View {
    @Binding var pricePerKilowattHour: Double
    @Binding var monthlyBasePrice: Double

    @Environment(\.dismiss) private var dismiss
    @State private var priceText: String
    @State private var basePriceText: String

    init(pricePerKilowattHour: Binding<Double>, monthlyBasePrice: Binding<Double>) {
        _pricePerKilowattHour = pricePerKilowattHour
        _monthlyBasePrice = monthlyBasePrice
        _priceText = State(initialValue: pricePerKilowattHour.wrappedValue.formatted(.number))
        _basePriceText = State(initialValue: monthlyBasePrice.wrappedValue.formatted(.number))
    }

    private var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: "."))
    }

    private var basePrice: Double? {
        Double(basePriceText.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        guard let price, let basePrice else { return false }
        return price >= 0 && basePrice >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Arbeitspreis") {
                    TextField("Preis pro kWh in Euro", text: $priceText)
                }
                Section("Grundpreis") {
                    TextField("Grundpreis pro Monat in Euro", text: $basePriceText)
                }
            }
            .navigationTitle("Tarif")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let price, let basePrice else { return }
                        pricePerKilowattHour = price
                        monthlyBasePrice = basePrice
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
