import AppIntents

/// The 64 plates as Siri names them. Raw values are `Location.code`.
///
/// The App Intents compiler needs the cases and their display representations as
/// literals, so this can't be built from `Location.allLocations`. In debug builds,
/// `assertMatchesLocations()` runs at launch and keeps the two lists in step.
nonisolated enum PlateRegion: String, AppEnum {
    case alabama = "AL", alaska = "AK", arizona = "AZ", arkansas = "AR", california = "CA"
    case colorado = "CO", connecticut = "CT", delaware = "DE", districtOfColumbia = "DC", florida = "FL"
    case georgia = "GA", hawaii = "HI", idaho = "ID", illinois = "IL", indiana = "IN"
    case iowa = "IA", kansas = "KS", kentucky = "KY", louisiana = "LA", maine = "ME"
    case maryland = "MD", massachusetts = "MA", michigan = "MI", minnesota = "MN", mississippi = "MS"
    case missouri = "MO", montana = "MT", nebraska = "NE", nevada = "NV", newHampshire = "NH"
    case newJersey = "NJ", newMexico = "NM", newYork = "NY", northCarolina = "NC", northDakota = "ND"
    case ohio = "OH", oklahoma = "OK", oregon = "OR", pennsylvania = "PA", rhodeIsland = "RI"
    case southCarolina = "SC", southDakota = "SD", tennessee = "TN", texas = "TX", utah = "UT"
    case vermont = "VT", virginia = "VA", washington = "WA", westVirginia = "WV", wisconsin = "WI"
    case wyoming = "WY"
    case alberta = "AB", britishColumbia = "BC", manitoba = "MB", newBrunswick = "NB"
    case newfoundlandAndLabrador = "NL", novaScotia = "NS", ontario = "ON", princeEdwardIsland = "PE"
    case quebec = "QC", saskatchewan = "SK", northwestTerritories = "NT", nunavut = "NU", yukon = "YT"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plate"

    // "Washington" is the state; DC answers only to its own names (spec, "Decisions").
    static let caseDisplayRepresentations: [PlateRegion: DisplayRepresentation] = [
        .alabama: "Alabama", .alaska: "Alaska", .arizona: "Arizona", .arkansas: "Arkansas",
        .california: "California", .colorado: "Colorado", .connecticut: "Connecticut",
        .delaware: "Delaware",
        .districtOfColumbia: DisplayRepresentation(
            title: "District of Columbia",
            synonyms: ["DC", "D.C.", "Washington DC", "Washington D.C."]
        ),
        .florida: "Florida", .georgia: "Georgia", .hawaii: "Hawaii", .idaho: "Idaho",
        .illinois: "Illinois", .indiana: "Indiana", .iowa: "Iowa", .kansas: "Kansas",
        .kentucky: "Kentucky", .louisiana: "Louisiana", .maine: "Maine", .maryland: "Maryland",
        .massachusetts: "Massachusetts", .michigan: "Michigan", .minnesota: "Minnesota",
        .mississippi: "Mississippi", .missouri: "Missouri", .montana: "Montana",
        .nebraska: "Nebraska", .nevada: "Nevada", .newHampshire: "New Hampshire",
        .newJersey: "New Jersey", .newMexico: "New Mexico", .newYork: "New York",
        .northCarolina: "North Carolina", .northDakota: "North Dakota", .ohio: "Ohio",
        .oklahoma: "Oklahoma", .oregon: "Oregon", .pennsylvania: "Pennsylvania",
        .rhodeIsland: "Rhode Island", .southCarolina: "South Carolina",
        .southDakota: "South Dakota", .tennessee: "Tennessee", .texas: "Texas", .utah: "Utah",
        .vermont: "Vermont", .virginia: "Virginia",
        .washington: DisplayRepresentation(title: "Washington", synonyms: ["Washington State"]),
        .westVirginia: "West Virginia", .wisconsin: "Wisconsin", .wyoming: "Wyoming",
        .alberta: "Alberta",
        .britishColumbia: DisplayRepresentation(title: "British Columbia", synonyms: ["BC", "B.C."]),
        .manitoba: "Manitoba", .newBrunswick: "New Brunswick",
        .newfoundlandAndLabrador: DisplayRepresentation(
            title: "Newfoundland and Labrador",
            synonyms: ["Newfoundland", "Labrador"]
        ),
        .novaScotia: "Nova Scotia", .ontario: "Ontario",
        .princeEdwardIsland: DisplayRepresentation(title: "Prince Edward Island", synonyms: ["PEI", "P.E.I."]),
        .quebec: DisplayRepresentation(title: "Quebec", synonyms: ["Québec"]),
        .saskatchewan: "Saskatchewan",
        .northwestTerritories: DisplayRepresentation(title: "Northwest Territories", synonyms: ["NWT"]),
        .nunavut: "Nunavut",
        .yukon: DisplayRepresentation(title: "Yukon", synonyms: ["Yukon Territory"]),
    ]

    @MainActor
    var location: Location {
        guard let location = Location.byCode[rawValue] else {
            preconditionFailure("PlateRegion \(rawValue) has no Location")
        }
        return location
    }

    #if DEBUG
    /// Fails fast in debug builds if a region is added to one list and not the other.
    @MainActor
    static func assertMatchesLocations() {
        let codes = Set(allCases.map(\.rawValue))
        let expected = Set(Location.allLocations.map(\.code))
        assert(codes == expected,
               "PlateRegion out of step with Location.allLocations: missing \(expected.subtracting(codes)), extra \(codes.subtracting(expected))")
        for region in allCases {
            let title = String(localized: caseDisplayRepresentations[region]?.title ?? "")
            assert(title == region.location.name, "PlateRegion \(region.rawValue) title \"\(title)\" ≠ \"\(region.location.name)\"")
        }
    }
    #endif
}

extension Location {
    static let byCode: [String: Location] = Dictionary(uniqueKeysWithValues: allLocations.map { ($0.code, $0) })
}

// Experiment (build 67): group the per-plate tiles the Shortcuts app shows for
// plate phrases into a US and a Canada collection. Spec, "Changes after TestFlight 62".

nonisolated struct USPlateOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [PlateRegion] {
        Location.usStates.compactMap { PlateRegion(rawValue: $0.code) }
    }
}

nonisolated struct CanadaPlateOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [PlateRegion] {
        Location.canadaLocations.compactMap { PlateRegion(rawValue: $0.code) }
    }
}
