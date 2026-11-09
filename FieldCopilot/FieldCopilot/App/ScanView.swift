import SwiftUI

/// One scan: the photo with the text it was read from boxed, the steps while it's being read, then
/// the unit at a glance and voice notes about it. Pushed from the list, so it has a back button.
struct ScanView: View {
    let scan: Scan
    /// Deletes the scan and goes back to the list.
    var onDelete: () -> Void = {}
    /// Saves a correction or a voice note.
    var onEdit: () -> Void = {}
    @State private var editing: Scan.Field?
    @State private var dictation = Dictation()
    @State private var readAloud = ReadAloud()
    @State private var showingText = false
    @State private var showingPhoto = false
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LabelPhoto(scan: scan, usedOnly: true)
                    .frame(maxHeight: scan.label == nil ? 360 : 220)
                    .frame(maxWidth: .infinity)
                    .background {
                        Image(uiImage: scan.image).resizable().scaledToFill().blur(radius: 30).overlay(.black.opacity(0.3))
                    }
                    .clipShape(.rect(cornerRadius: 16))
                    .onTapGesture { showingPhoto = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Photo of the label. Show full size")

                if scan.step != .done {
                    ReadingSteps(scan: scan)
                }
                if let warning = scan.photoWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.black)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.25), in: .rect(cornerRadius: 12))
                }
                if let label = scan.label {
                    UnitHeader(scan: scan, label: label, edit: edit)
                    DetailsCard(scan: scan, label: label, edit: edit)
                }
                if scan.step == .done {
                    VoiceNotesCard(scan: scan, dictation: dictation, onSave: onEdit)
                }
                CaptureInfo(scan: scan)
                if let message = scan.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if scan.step == .done, scan.label == nil {
                    Button("Enter details yourself", systemImage: "square.and.pencil") { scan.enterDetails() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
                if scan.step == .done {
                    Button("Delete scan", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .confirmationDialog("Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete scan", role: .destructive, action: onDelete)
                        } message: {
                            Text("The photo and what was read from it are removed from this phone.")
                        }
                }
            }
            .padding()
            .animation(.default, value: scan.step)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(scan.label?.brand.value ?? "Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if readAloud.isSpeaking {
                    Button("Stop reading", systemImage: "stop.fill") { readAloud.stop() }
                } else {
                    Button("Read aloud", systemImage: "speaker.wave.2") { readAloud.speak(scan) }
                        .disabled(scan.step != .done || dictation.state != .idle)
                }
                Button("All text", systemImage: "text.alignleft") { showingText = true }
                ShareLink(item: scan.summary)
            }
        }
        // The microphone and the voice share the phone's audio, so recording stops the reading.
        .onChange(of: dictation.state) { if $1 != .idle { readAloud.stop() } }
        .onDisappear { readAloud.stop() }
        .sheet(isPresented: $showingText) { AllTextView(scan: scan) }
        .sheet(item: $editing) { field in FieldEditor(scan: scan, field: field, onSave: onEdit) }
        .sheet(isPresented: $showingPhoto) { PhotoView(scan: scan) }
    }
}

extension ScanView {
    /// Opens the editor for a field, once the scan has been read.
    private func edit(_ field: Scan.Field) {
        if scan.step == .done { editing = field }
    }
}

/// A field name with a pencil, marking the value under it as tappable to correct.
struct EditableName: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
            Image(systemName: "pencil").imageScale(.small)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// When and where the photo was taken. Only a photo taken in the app has a location.
struct CaptureInfo: View {
    let scan: Scan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(scan.captureSummary, systemImage: scan.source == .camera ? "camera" : "photo.on.rectangle")
            if let location = scan.location,
               let url = URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=Equipment%20label") {
                Link(destination: url) {
                    Label("Location within \(Int(location.accuracy.rounded())) m. Open in Maps", systemImage: "mappin.and.ellipse")
                }
            } else if scan.source == .camera {
                Label("No location: location access is off", systemImage: "location.slash")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The photo with boxes over the text: orange for what the brand, model and serial came from.
struct LabelPhoto: View {
    let scan: Scan
    /// Box only the text the fields came from, or every line.
    var usedOnly = false

    var body: some View {
        let used = scan.usedLines
        Image(uiImage: scan.image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geometry in
                    ForEach(scan.lines) { line in
                        let isUsed = used.contains(line.id)
                        if isUsed || !usedOnly || scan.label == nil {
                            box(line.box, in: geometry.size)
                                .stroke(isUsed ? Color.orange : Color.white.opacity(0.7), lineWidth: isUsed ? 2.5 : 1)
                        }
                    }
                    if !usedOnly {
                        ForEach(scan.barcodes) { barcode in
                            box(barcode.box, in: geometry.size).stroke(Color.cyan, lineWidth: 2)
                        }
                    }
                }
            }
    }

    private func box(_ rect: CGRect, in size: CGSize) -> Path {
        Path(roundedRect: CGRect(x: rect.minX * size.width - 2, y: rect.minY * size.height - 2,
                                 width: rect.width * size.width + 4, height: rect.height * size.height + 4),
             cornerRadius: 3)
    }
}

/// What's happening while a scan is read.
struct ReadingSteps: View {
    let scan: Scan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading the label").font(.headline)
            step("Text and barcodes", .text)
            step("Model number", .modelNumber)
            step("Equipment lists", .lists)
            if scan.askedAppleIntelligence {
                step("Filling gaps with Apple Intelligence", .appleIntelligence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func step(_ name: String, _ step: Scan.Step) -> some View {
        HStack(spacing: 10) {
            if scan.step > step {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if scan.step == step {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            Text(name).foregroundStyle(scan.step >= step ? .primary : .secondary)
        }
    }
}

/// Brand, type and the key specs as chips, with where they came from.
struct UnitHeader: View {
    let scan: Scan
    let label: CheckedLabel
    let edit: (Scan.Field) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: label.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentOrange)
                    .frame(width: 52, height: 52)
                    .background(Color.orange.opacity(0.15), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Button { edit(.brand) } label: {
                        HStack(spacing: 6) {
                            Text(label.brand.value ?? "Add brand").font(.title2.bold()).foregroundStyle(.primary)
                            Image(systemName: "pencil").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Brand: \(label.brand.value ?? "not found"). Edit")
                    Button { edit(.kind) } label: {
                        HStack(spacing: 6) {
                            Text(label.kind == .unknown ? "Add type" : label.kind.displayName).foregroundStyle(.secondary)
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityLabel("Type: \(label.kind.displayName). Edit")
                }
                .buttonStyle(.plain)
            }
            let chips = ([scan.made?.age].compactMap { $0 } + (label.size?.components(separatedBy: " · ") ?? []))
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            if !chips.isEmpty {
                FlowLayout {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                    }
                }
            }
            ForEach(headerNotes, id: \.self) { NoteLine(note: $0) }
        }
    }

    /// The brand, type and specs notes, with notes they share said once: "Brand, type, and specs from
    /// the model number".
    private var headerNotes: [String] {
        var groups: [(note: String, names: [String])] = []
        func add(_ name: String, _ note: String?) {
            guard let note else { return }
            if let index = groups.firstIndex(where: { $0.note == note }) {
                groups[index].names.append(name)
            } else {
                groups.append((note, [name]))
            }
        }
        add("Brand", label.brand.note)
        add("Type", label.kindNote)
        if let source = label.sizeSource { add("Specs", "From \(source)") }
        return groups.map { group in
            let names = group.names.enumerated().map { $0 == 0 ? $1 : $1.lowercased() }.formatted(.list(type: .and))
            if group.note.hasPrefix("From ") || group.note.hasPrefix("Read by ") || group.note.hasPrefix("Entered by ") {
                return "\(names) \(group.note.prefix(1).lowercased())\(group.note.dropFirst())"
            }
            return group.names == ["Brand"] ? group.note : "\(names): \(group.note)"
        }
    }
}

/// Model, serial, when it was made, and ENERGY STAR.
struct DetailsCard: View {
    let scan: Scan
    let label: CheckedLabel
    let edit: (Scan.Field) -> Void
    @State private var copied = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            codeRow(.model, label.model)
            Divider()
            codeRow(.serial, label.serial)
            Divider()
            let made = ManufactureAge.describe(label)
            Button { edit(.made) } label: {
                row("Made", value: scan.made?.date ?? "Add date", note: made.note, editable: true)
            }
            .buttonStyle(.plain)
            if let listed = EquipmentDatabase.describe(label) {
                Divider()
                row(listed.title, value: listed.field.value ?? "", note: listed.field.note,
                    badge: label.listing != nil ? "checkmark.seal.fill" : nil)
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .sensoryFeedback(.success, trigger: copied)
    }

    private func codeRow(_ name: Scan.Field, _ field: CheckedField) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Button { edit(name) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    EditableName(name: name.name)
                    Text(field.value ?? "Add \(name.name.lowercased())")
                        .font(.body.monospaced())
                        .foregroundStyle(field.value == nil ? .secondary : .primary)
                    if let note = field.note { NoteLine(note: note) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name.name): \(field.value ?? "not found"). Edit")
            if let value = field.value {
                Button("Copy \(name.name.lowercased())", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = value
                    copied += 1
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 12)
    }

    private func row(_ name: String, value: String, note: String?, badge: String? = nil, editable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if editable {
                EditableName(name: name)
            } else {
                Text(name).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let badge { Image(systemName: badge).foregroundStyle(.green) }
                Text(value)
            }
            if let note { NoteLine(note: note) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 12)
    }
}

/// Every line of text and barcode found, for checking what the app saw.
struct AllTextView: View {
    let scan: Scan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !scan.barcodes.isEmpty {
                    Section("Barcodes") {
                        ForEach(scan.barcodes) { Text($0.payload).font(.body.monospaced()) }
                    }
                }
                Section("Text") {
                    ForEach(scan.lines) { line in
                        Text(line.text)
                            .font(.body.monospaced())
                            .foregroundStyle(scan.usedLines.contains(line.id) ? Color.accentOrange : .primary)
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("All text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// The photo full screen, with every line and barcode boxed. Pinch to zoom, double-tap to reset.
struct PhotoView: View {
    let scan: Scan
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @GestureState private var pinch = 1.0

    var body: some View {
        NavigationStack {
            LabelPhoto(scan: scan)
                .scaleEffect(zoom * pinch)
                .gesture(MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { zoom = min(max(zoom * $0.magnification, 1), 6) })
                .onTapGesture(count: 2) { withAnimation { zoom = 1 } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .background(Color.black)
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
