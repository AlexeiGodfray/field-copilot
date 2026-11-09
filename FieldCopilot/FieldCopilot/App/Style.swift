import SwiftUI

extension Color {
    /// Orange for icons and text. System orange (used for filled buttons, with black text) is too light
    /// to read on white, so light mode uses a deeper shade.
    static let accentOrange = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0xB8 / 255, green: 0x5E / 255, blue: 0, alpha: 1)
    })
}

extension EquipmentKind {
    var symbol: String {
        switch self {
        case .waterHeater: "drop.degreesign"
        case .airConditioner: "air.conditioner.horizontal"
        case .heatPump: "heat.waves"
        case .airConditionerOrHeatPump: "air.conditioner.horizontal"
        case .furnace: "flame"
        case .boiler: "heater.vertical"
        case .airHandler: "wind"
        case .evaporatorCoil: "square.grid.3x3"
        case .packagedUnit: "shippingbox"
        case .solarInverter: "sun.max"
        case .solarPanel: "rectangle.grid.3x2"
        case .battery: "battery.100"
        case .electricalPanel: "bolt"
        case .transferSwitch: "switch.2"
        case .unknown: "questionmark.circle"
        }
    }
}

/// An icon for where a note says a value came from.
func noteSymbol(_ note: String) -> String {
    if note.contains("by you") { return "pencil" }
    if note.contains("Apple Intelligence") { return "sparkles" }
    if note.contains("barcode") { return "barcode" }
    if ["Certified", "Listed", "Not in"].contains(where: note.hasPrefix) { return "checkmark.seal" }
    if note.contains("ENERGY STAR") { return "star" }
    if note.contains("serial") { return "calendar" }
    if note.contains("model number") || note.hasPrefix("Sold as") { return "number" }
    if note.contains("label") { return "text.viewfinder" }
    return "info.circle"
}

/// A note under a value, with an icon for its source.
struct NoteLine: View {
    let note: String

    var body: some View {
        Label {
            Text(note)
        } icon: {
            Image(systemName: noteSymbol(note))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Lays its views out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let positions = place(subviews, width: proposal.width ?? .infinity)
        let height = zip(positions, subviews).map { $0.y + $1.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (position, view) in zip(place(subviews, width: bounds.width), subviews) {
            view.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> [CGPoint] {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return positions
    }
}
