import SwiftUI

/// What a person said about the unit: each note's words, and a button to record another. The words
/// appear as they're spoken, and a note can be corrected or deleted afterwards.
struct VoiceNotesCard: View {
    let scan: Scan
    @Bindable var dictation: Dictation
    /// Saves the scan's notes.
    let onSave: () -> Void
    @State private var editing: VoiceNote?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice notes").font(.headline)
            ForEach(scan.voiceNotes) { note in
                Button { editing = note } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text).foregroundStyle(.primary)
                        Text(note.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit or delete this note")
                Divider()
            }
            switch dictation.state {
            case .idle:
                Button("Record a voice note", systemImage: "mic.fill") {
                    Task { await dictation.start() }
                }
                .buttonStyle(.bordered)
                problem
            case .starting:
                Label { Text("Getting ready…") } icon: { ProgressView().controlSize(.small) }
                    .foregroundStyle(.secondary)
            case .downloading:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading the speech model. This happens once.").foregroundStyle(.secondary)
                    if let download = dictation.download { ProgressView(download).labelsHidden() }
                }
            case .listening, .finishing:
                listening
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .sensoryFeedback(trigger: dictation.state) { old, new in
            new == .listening ? .start : old == .listening ? .stop : nil
        }
        .sheet(item: $editing) { note in
            VoiceNoteEditor(note: note) { replace(note, with: $0) }
        }
        .onDisappear {
            // Leaving the scan while talking keeps what was said.
            Task { add(await dictation.stop()) }
        }
    }

    /// The words so far, the ones still being recognized in gray, and the button to finish.
    private var listening: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dictation.text.isEmpty {
                    Text("Listening…").foregroundStyle(.secondary)
                } else {
                    Text("\(dictation.settled) \(Text(dictation.tentative).foregroundStyle(.secondary))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: dictation.text)
            Button {
                Task { add(await dictation.stop()) }
            } label: {
                Label(dictation.state == .finishing ? "Saving…" : "Done", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange, in: .capsule)
            }
            .disabled(dictation.state == .finishing)
        }
    }

    @ViewBuilder private var problem: some View {
        switch dictation.problem {
        case .microphoneDenied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Microphone access is off. Allow it in Settings to record voice notes.", systemImage: "mic.slash")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func add(_ said: String) {
        guard !said.isEmpty else { return }
        scan.voiceNotes.append(VoiceNote(text: said))
        onSave()
    }

    /// Replaces a note with its corrected words, or deletes it for nil.
    private func replace(_ note: VoiceNote, with changed: VoiceNote?) {
        guard let index = scan.voiceNotes.firstIndex(where: { $0.id == note.id }) else { return }
        if let changed {
            scan.voiceNotes[index] = changed
        } else {
            scan.voiceNotes.remove(at: index)
        }
        onSave()
    }
}

/// Corrects the words of a voice note, or deletes it.
struct VoiceNoteEditor: View {
    let note: VoiceNote
    /// Called with the corrected note, or nil to delete it.
    let onSave: (VoiceNote?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 120)
                } footer: {
                    Text("Recorded \(note.date.formatted(date: .abbreviated, time: .shortened))")
                }
                Section {
                    Button("Delete note", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete note", role: .destructive) {
                                onSave(nil)
                                dismiss()
                            }
                        }
                }
            }
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var changed = note
                        changed.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if changed != note { onSave(changed) }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = note.text }
        }
        .presentationDetents([.medium, .large])
    }
}
