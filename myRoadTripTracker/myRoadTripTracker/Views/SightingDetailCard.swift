import SwiftUI
import CoreData

struct SightingDetailCard: View {
    let sighting: PlateSighting
    var isInterpolated: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(sighting.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 30)
                .clipShape(.rect(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(sighting.locationName)
                    .font(.headline)
                if let date = sighting.seenDate {
                    Text(date, format: .dateTime.month(.wide).day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isInterpolated {
                    Text("Approximate location")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
