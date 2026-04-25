import SwiftUI

struct ObservationEntryRow: View {
    @ObservedObject var entry: ObservationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.createdDate ?? Date(), style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
