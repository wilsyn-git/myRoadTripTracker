import SwiftUI
import SwiftData

struct JoinTripNameView: View {
    let trip: Trip
    let onComplete: (String) -> Void
    @AppStorage("defaultDisplayName") private var defaultDisplayName = ""
    @State private var displayName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Joining \"\(trip.name)\"")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("What should other participants call you on this trip?")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Spacer()
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onComplete(name)
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                displayName = defaultDisplayName
                isFocused = true
            }
        }
    }
}
