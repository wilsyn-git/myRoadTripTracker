import SwiftUI
import CoreData

/// The trip's editable name. Typing edits a local draft, and the draft is written back to
/// the trip once editing ends. Writing every keystroke to the managed object re-rendered
/// the whole trip screen and the trip list behind it, letter by letter (#37). Collaborators
/// also never see a half-typed name.
struct TripNameField: View {
    @ObservedObject var trip: Trip
    let focusOnAppear: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isFocused: Bool
    @State private var draftName: String

    init(trip: Trip, focusOnAppear: Bool) {
        self.trip = trip
        self.focusOnAppear = focusOnAppear
        _draftName = State(initialValue: trip.name)
    }

    var body: some View {
        TextField("Trip Name", text: $draftName)
            .font(.title2)
            .bold()
            .focused($isFocused)
            .disabled(trip.isClosed)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: trip.name) { _, newName in
                // Follow a collaborator's rename, unless we're mid-edit.
                if !isFocused { draftName = newName }
            }
            // Safety net: the view can tear down while the field is still focused
            // (e.g. navigating back without dismissing the keyboard).
            .onDisappear(perform: commit)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                    }
                }
            }
            .task {
                if focusOnAppear {
                    try? await Task.sleep(for: .milliseconds(100))
                    isFocused = true
                }
            }
    }

    /// Writes the draft to the trip and saves, if it changed. An emptied field keeps the
    /// previous name.
    private func commit() {
        guard !trip.isDeleted, trip.managedObjectContext != nil else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = trip.name
            return
        }
        draftName = trimmed
        guard trimmed != trip.name else { return }
        trip.name = trimmed
        viewContext.save(contextInfo: "tripNameChange")
    }
}
