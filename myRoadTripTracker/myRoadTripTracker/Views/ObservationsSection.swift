import SwiftUI
import CoreData
import PhotosUI

struct ObservationsSection: View {
    @ObservedObject var trip: Trip
    let currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var addedCategories: [String] = []

    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]

    var body: some View {
        // Group entries by category once instead of re-filtering the full list per section.
        let entries = trip.observationEntriesArray
        let grouped = Dictionary(grouping: entries, by: \.category)

        ForEach(categories(from: entries), id: \.self) { category in
            Section {
                let categoryEntries = grouped[category] ?? []
                if categoryEntries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(categoryEntries) { entry in
                    ObservationEntryRow(entry: entry, currentUserName: currentUserName) {
                        entry.imageData = nil
                        entry.thumbnailData = nil
                        viewContext.save(contextInfo: "removeObservationImage")
                    }
                }
                if !trip.isClosed {
                    ComposeEntryRow(
                        trip: trip,
                        category: category,
                        authorName: currentUserName
                    )
                }
            } header: {
                Text(category)
            }
        }

        if !trip.isClosed {
            Section {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Custom Category", systemImage: "plus.circle.fill")
                }
            }
            .alert("Add Custom Category", isPresented: $showingAddCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
                Button("Add") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !categories(from: trip.observationEntriesArray).contains(trimmed) {
                        addedCategories.append(trimmed)
                    }
                    newCategoryName = ""
                }
            }
        }
    }

    private func categories(from entries: [ObservationEntry]) -> [String] {
        let entryCategories = Set(entries.map(\.category))
        var categories = predefinedCategories
        let custom = entryCategories
            .union(addedCategories)
            .filter { !predefinedCategories.contains($0) }
            .sorted()
        categories.append(contentsOf: custom)
        return categories
    }
}
