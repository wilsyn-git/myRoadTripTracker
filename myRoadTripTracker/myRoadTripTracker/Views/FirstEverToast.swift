import SwiftUI

/// The banner after marking a plate no trip on this phone has seen (#78).
struct FirstEverToast: View {
    let location: Location
    /// The collection's size including this plate.
    let collectedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 24)
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text("First time ever: \(location.name)!")
                    .font(.subheadline)
                    .bold()
                Text("Your collection is now \(collectedCount) of \(Location.allLocations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
