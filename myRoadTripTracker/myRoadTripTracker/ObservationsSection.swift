//
//  ObservationsSection.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct ObservationsSection: View {
    @Bindable var trip: Trip
    let currentUserName: String
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""

    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]

    var body: some View {
        ForEach(allCategories, id: \.self) { category in
            Section {
                let entries = entriesForCategory(category)
                if entries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries) { entry in
                    ObservationEntryRow(entry: entry)
                }
                if !trip.isClosed {
                    ComposeEntryRow(category: category, authorName: currentUserName) { text in
                        addEntry(category: category, text: text)
                    }
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
                    newCategoryName = ""
                }
            }
        }
    }

    private var allCategories: [String] {
        let entryCategories = Set(trip.observationEntries.map { $0.category })
        var categories = predefinedCategories
        let custom = entryCategories.filter { !predefinedCategories.contains($0) }.sorted()
        categories.append(contentsOf: custom)
        return categories
    }

    private func entriesForCategory(_ category: String) -> [ObservationEntry] {
        trip.observationEntries
            .filter { $0.category == category }
            .sorted { $0.createdDate < $1.createdDate }
    }

    private func addEntry(category: String, text: String) {
        let entry = ObservationEntry(category: category, authorName: currentUserName, text: text)
        entry.trip = trip
        trip.observationEntries.append(entry)
        modelContext.insert(entry)
    }
}

struct ComposeEntryRow: View {
    let category: String
    let authorName: String
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("Add an observation...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitEntry()
                }
            Button {
                submitEntry()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
    }
}
