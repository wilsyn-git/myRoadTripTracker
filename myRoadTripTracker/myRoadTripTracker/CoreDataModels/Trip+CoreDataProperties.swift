import Foundation
import CoreData

extension Trip {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        return NSFetchRequest<Trip>(entityName: "Trip")
    }

    @NSManaged public var tripID: UUID?
    @NSManaged public var name: String
    @NSManaged public var createdDate: Date?
    @NSManaged public var isClosed: Bool
    @NSManaged public var plateSightings: NSSet?
    @NSManaged public var observationEntries: NSSet?
    @NSManaged public var participants: NSSet?
}

// MARK: - Convenience Accessors

extension Trip: Identifiable {
    var plateSightingsArray: [PlateSighting] {
        let set = plateSightings as? Set<PlateSighting> ?? []
        return set.sorted { ($0.seenDate ?? .distantPast) < ($1.seenDate ?? .distantPast) }
    }

    var observationEntriesArray: [ObservationEntry] {
        let set = observationEntries as? Set<ObservationEntry> ?? []
        return set.sorted { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
    }

    var participantsArray: [TripParticipant] {
        let set = participants as? Set<TripParticipant> ?? []
        return set.sorted { ($0.joinedDate ?? .distantPast) < ($1.joinedDate ?? .distantPast) }
    }
}

// MARK: - Generated accessors for plateSightings
extension Trip {
    @objc(addPlateSightingsObject:)
    @NSManaged public func addToPlateSightings(_ value: PlateSighting)

    @objc(removePlateSightingsObject:)
    @NSManaged public func removeFromPlateSightings(_ value: PlateSighting)

    @objc(addPlateSightings:)
    @NSManaged public func addToPlateSightings(_ values: NSSet)

    @objc(removePlateSightings:)
    @NSManaged public func removeFromPlateSightings(_ values: NSSet)
}

// MARK: - Generated accessors for observationEntries
extension Trip {
    @objc(addObservationEntriesObject:)
    @NSManaged public func addToObservationEntries(_ value: ObservationEntry)

    @objc(removeObservationEntriesObject:)
    @NSManaged public func removeFromObservationEntries(_ value: ObservationEntry)

    @objc(addObservationEntries:)
    @NSManaged public func addToObservationEntries(_ values: NSSet)

    @objc(removeObservationEntries:)
    @NSManaged public func removeFromObservationEntries(_ values: NSSet)
}

// MARK: - Generated accessors for participants
extension Trip {
    @objc(addParticipantsObject:)
    @NSManaged public func addToParticipants(_ value: TripParticipant)

    @objc(removeParticipantsObject:)
    @NSManaged public func removeFromParticipants(_ value: TripParticipant)

    @objc(addParticipants:)
    @NSManaged public func addToParticipants(_ values: NSSet)

    @objc(removeParticipants:)
    @NSManaged public func removeFromParticipants(_ values: NSSet)
}
