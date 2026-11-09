import PhotosUI
import SwiftUI

/// Your scans, newest first, and the button to scan another label. Opening a scan pushes it on a
/// navigation stack, so its screen has a back button to this list.
struct HomeView: View {
    @State private var store = ScanStore()
    @State private var path: [Scan.ID] = []
    @State private var selection: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var showingCamera = false
    @State private var shortcuts = ShortcutRequests.shared
    /// A blurry photo was turned away; the alert waits until the camera has closed.
    @State private var blurryPhoto = false
    @State private var blurryFromCamera = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.scans.isEmpty {
                    ContentUnavailableView {
                        Label("Scan an equipment label", systemImage: "text.viewfinder")
                    } description: {
                        Text("Scan an equipment nameplate, or choose a photo of one. Field Copilot reads the brand, model, serial and age, and shows where each came from.")
                    }
                } else {
                    List {
                        Section("Your scans") {
                            ForEach(store.scans) { scan in
                                NavigationLink(value: scan.id) { ScanRow(scan: scan) }
                            }
                            .onDelete { store.delete(at: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Field Copilot")
            .navigationDestination(for: Scan.ID.self) { id in
                if let scan = store.scan(id) {
                    ScanView(scan: scan, onDelete: {
                        path.removeAll()
                        store.delete(scan)
                    }, onEdit: { store.save() })
                }
            }
            .safeAreaInset(edge: .bottom) { scanBar }
            .task(id: selection) { await addChosenPhoto() }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                if blurryFromCamera {
                    blurryFromCamera = false
                    blurryPhoto = true
                }
            }) {
                CameraView { data, location in add(data, source: .camera, location: location) }
            }
            // "Scan a label with Field Copilot", from Siri or the Shortcuts app.
            .onChange(of: shortcuts.scanLabel, initial: true) {
                guard shortcuts.scanLabel else { return }
                shortcuts.scanLabel = false
                showingCamera = true
            }
            .alert("Couldn't open this photo", isPresented: $loadFailed) {
                Button("OK", role: .cancel) {}
            }
            .alert("This photo is too blurry to read", isPresented: $blurryPhoto) {
                Button("Take another photo") { showingCamera = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Hold the phone steady and tap the label to focus, or move a little closer.")
            }
        }
        .tint(.accentOrange)
    }

    /// Scan with the camera, or choose a photo from the library.
    private var scanBar: some View {
        HStack(spacing: 12) {
            Button { showingCamera = true } label: {
                Label("Scan label", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange, in: .capsule)
            }
            PhotosPicker(selection: $selection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.headline)
                    .frame(width: 52, height: 52)
                    .background(.regularMaterial, in: .circle)
            }
            .accessibilityLabel("Choose photo")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func addChosenPhoto() async {
        guard let item = selection else { return }
        selection = nil  // so choosing the same photo again starts a new scan
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            loadFailed = true
            return
        }
        add(data, source: .library)
    }

    /// Saves the photo as a scan, opens it, reads it, and saves what was read. A blurry photo is turned
    /// away instead: OCR misreads it, and Apple Intelligence then guesses (a blurred label read as brand
    /// "ERA" with the model and serial swapped). Glare and darkness only warn, since such photos still read.
    private func add(_ data: Data, source: Scan.Source, location: CaptureLocation? = nil) {
        if let image = UIImage(data: data)?.cgImage, PhotoQuality.measure(image)?.problems.contains(.blurry) == true {
            if source == .camera { blurryFromCamera = true } else { blurryPhoto = true }
            return
        }
        guard let scan = store.add(photo: data, source: source, location: location) else {
            loadFailed = true
            return
        }
        path = [scan.id]
        Task {
            await scan.read()
            store.save()
        }
    }
}

/// A scan in the list: photo, brand and type, model number, and age.
struct ScanRow: View {
    let scan: Scan

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: scan.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.label?.brand.value ?? (scan.step == .done ? "Unknown brand" : "Reading…"))
                    .font(.headline)
                if let kind = scan.label?.kind, kind != .unknown {
                    Text(kind.displayName).font(.subheadline).foregroundStyle(.secondary)
                }
                if let model = scan.label?.model.value {
                    Text(model).font(.footnote.monospaced()).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if scan.step != .done {
                    ProgressView()
                } else if let age = scan.made?.age {
                    Text(age == "under a year old" ? "New" : age.replacingOccurrences(of: " years old", with: " yrs")
                        .replacingOccurrences(of: " year old", with: " yr"))
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.fill.tertiary, in: .capsule)
                }
                Text(scan.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HomeView()
}
