import SwiftUI

/// Corrects one field of a scan: shows what the app read, checks the new value as it's typed, and can go
/// back to what was read.
struct FieldEditor: View {
    let scan: Scan
    let field: Scan.Field
    /// Called after a change is saved to the scan.
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind = EquipmentKind.unknown
    @State private var year = Calendar.current.component(.year, from: .now)
    /// 0 when the month isn't known.
    @State private var month = 0
    @State private var initialValue: String?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    input
                } footer: {
                    if let read = scan.readValue(field) {
                        Text("The app read “\(read)”.")
                    } else {
                        Text("The app didn't find this on the label.")
                    }
                }
                check
                if field == .brand { brandSuggestions }
                if scan.edit(field) != nil {
                    Section {
                        Button("Use what the app read") { save(nil) }
                    }
                }
            }
            .navigationTitle("Edit \(field.name.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(newValue) }
                        .disabled([.brand, .model, .serial].contains(field) && text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Input

    @ViewBuilder private var input: some View {
        switch field {
        case .brand:
            HStack {
                TextField("Brand", text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { save(newValue) }
                clearButton
            }
        case .model, .serial:
            HStack {
                TextField(field == .model ? "Model number" : "Serial number", text: $text)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { save(newValue) }
                clearButton
            }
        case .kind:
            Picker("Type", selection: $kind) {
                ForEach(EquipmentKind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        case .made:
            Picker("Month", selection: $month) {
                Text("Not known").tag(0)
                ForEach(1...12, id: \.self) { month in
                    Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                }
            }
            Picker("Year", selection: $year) {
                ForEach((1960...Calendar.current.component(.year, from: .now)).reversed(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
        }
    }

    @ViewBuilder private var clearButton: some View {
        if !text.isEmpty {
            Button("Clear", systemImage: "xmark.circle.fill") {
                text = ""
                typing = true
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)
        }
    }

    /// What the typed value decodes to, so a correction can be checked before it's saved.
    @ViewBuilder private var check: some View {
        let value = text.trimmingCharacters(in: .whitespaces)
        switch field {
        case .model where !value.isEmpty:
            Section {
                if let info = ModelLookup.lookup(value) {
                    let who = info.brands.count == 1 ? info.brands[0] : info.manufacturer
                    let what = [info.kind?.displayName.lowercased(), info.size].compactMap { $0 }.joined(separator: ", ")
                    Label("\(who) \(what)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let listed = EquipmentDatabase.lookup(value) {
                    let listing = listed.listing
                    let who = listed.brands.count == 1 ? listed.brands[0] : listing.maker
                    let what = [who, listing.product].filter { !$0.isEmpty }.joined(separator: " ")
                    Label("Listed by \(listing.source.spoken): \(what)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                if ModelLookup.lookup(value) == nil, EquipmentDatabase.lookup(value) == nil {
                    Label("Field Copilot can't decode this model number. It's saved as typed.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        case .serial where !value.isEmpty:
            Section {
                let brand = scan.label?.brand.value
                if let date = SerialDecoder.decode(brand: brand, serial: value, kind: scan.label?.kind ?? .unknown) {
                    Label("Made \(ManufactureAge.text(date.year, date.month)): \(date.explanation)", systemImage: "calendar")
                        .foregroundStyle(.green)
                } else if let brand, SerialDecoder.knowsFormat(for: brand) {
                    Label("This doesn't match \(brand)'s date format", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("The age can't be read from this serial", systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
        case .made:
            Section {
                Text(ManufactureAge.age(year, month == 0 ? 6 : month, .now).prefix(1).uppercased()
                     + ManufactureAge.age(year, month == 0 ? 6 : month, .now).dropFirst())
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    /// For a model sold under several brands, the brands it's sold as; otherwise known brands matching what's typed.
    @ViewBuilder private var brandSuggestions: some View {
        let soldAs = scan.label?.listing?.brands ?? ModelLookup.lookup(scan.label?.model.value)?.brands ?? []
        let typed = text.lowercased().filter(\.isLetter)
        let suggestions = soldAs.count > 1 ? soldAs
            : typed.isEmpty ? []
            : Self.knownBrands.filter { $0.lowercased().filter(\.isLetter).hasPrefix(typed) && $0 != text }.prefix(6).map { $0 }
        if !suggestions.isEmpty {
            Section(soldAs.count > 1 ? "This model is sold as" : "Suggestions") {
                ForEach(suggestions, id: \.self) { brand in
                    Button {
                        text = brand
                    } label: {
                        HStack {
                            Text(brand).foregroundStyle(.primary)
                            Spacer()
                            if brand == text { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }

    static let knownBrands = Set(LabelRules.knownBrands.map(\.name) + ModelLookup.icpBrands + [
        "Armstrong Air", "AirEase", "Ducane", "Concord", "RunTru", "Ameristar", "WeatherKing", "Sure Comfort",
        "State", "American Water Heater", "Richmond", "Bosch", "LG", "Samsung", "Midea", "Gree", "Coleman", "Luxaire",
    ]).sorted()

    // MARK: Saving

    private var newValue: String? {
        switch field {
        case .kind: kind.rawValue
        case .made: month == 0 ? String(year) : String(format: "%04d-%02d", year, month)
        default: text
        }
    }

    /// Fills the inputs with what's shown now.
    private func load() {
        let label = scan.label
        switch field {
        case .brand: text = label?.brand.value ?? ""
        case .model: text = label?.model.value ?? ""
        case .serial: text = label?.serial.value ?? ""
        case .kind: kind = label?.kind ?? .unknown
        case .made:
            if let made = scan.madeDate {
                year = made.year
                month = made.month ?? 0
            }
        }
        initialValue = newValue
        typing = [.brand, .model, .serial].contains(field)
    }

    private func save(_ value: String?) {
        // Saving what's already shown isn't a correction.
        if value == nil || value != initialValue || scan.edit(field) != nil {
            scan.setEdit(field, value)
            onSave()
        }
        dismiss()
    }
}
