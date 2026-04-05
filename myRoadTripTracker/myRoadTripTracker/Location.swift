//
//  Location.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import Foundation

struct Location: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let type: LocationType
    
    var flagImageName: String {
        name.lowercased().replacing(" ", with: "_")
    }

    enum LocationType {
        case usState
        case canadianProvince
        case canadianTerritory
    }
}

extension Location {
    static let allLocations: [Location] = usStates + canadianProvinces + canadianTerritories
    static let canadaLocations: [Location] = canadianProvinces + canadianTerritories
    
    static let usStates: [Location] = [
        Location(code: "AL", name: "Alabama", type: .usState),
        Location(code: "AK", name: "Alaska", type: .usState),
        Location(code: "AZ", name: "Arizona", type: .usState),
        Location(code: "AR", name: "Arkansas", type: .usState),
        Location(code: "CA", name: "California", type: .usState),
        Location(code: "CO", name: "Colorado", type: .usState),
        Location(code: "CT", name: "Connecticut", type: .usState),
        Location(code: "DE", name: "Delaware", type: .usState),
        Location(code: "DC", name: "District of Columbia", type: .usState),
        Location(code: "FL", name: "Florida", type: .usState),
        Location(code: "GA", name: "Georgia", type: .usState),
        Location(code: "HI", name: "Hawaii", type: .usState),
        Location(code: "ID", name: "Idaho", type: .usState),
        Location(code: "IL", name: "Illinois", type: .usState),
        Location(code: "IN", name: "Indiana", type: .usState),
        Location(code: "IA", name: "Iowa", type: .usState),
        Location(code: "KS", name: "Kansas", type: .usState),
        Location(code: "KY", name: "Kentucky", type: .usState),
        Location(code: "LA", name: "Louisiana", type: .usState),
        Location(code: "ME", name: "Maine", type: .usState),
        Location(code: "MD", name: "Maryland", type: .usState),
        Location(code: "MA", name: "Massachusetts", type: .usState),
        Location(code: "MI", name: "Michigan", type: .usState),
        Location(code: "MN", name: "Minnesota", type: .usState),
        Location(code: "MS", name: "Mississippi", type: .usState),
        Location(code: "MO", name: "Missouri", type: .usState),
        Location(code: "MT", name: "Montana", type: .usState),
        Location(code: "NE", name: "Nebraska", type: .usState),
        Location(code: "NV", name: "Nevada", type: .usState),
        Location(code: "NH", name: "New Hampshire", type: .usState),
        Location(code: "NJ", name: "New Jersey", type: .usState),
        Location(code: "NM", name: "New Mexico", type: .usState),
        Location(code: "NY", name: "New York", type: .usState),
        Location(code: "NC", name: "North Carolina", type: .usState),
        Location(code: "ND", name: "North Dakota", type: .usState),
        Location(code: "OH", name: "Ohio", type: .usState),
        Location(code: "OK", name: "Oklahoma", type: .usState),
        Location(code: "OR", name: "Oregon", type: .usState),
        Location(code: "PA", name: "Pennsylvania", type: .usState),
        Location(code: "RI", name: "Rhode Island", type: .usState),
        Location(code: "SC", name: "South Carolina", type: .usState),
        Location(code: "SD", name: "South Dakota", type: .usState),
        Location(code: "TN", name: "Tennessee", type: .usState),
        Location(code: "TX", name: "Texas", type: .usState),
        Location(code: "UT", name: "Utah", type: .usState),
        Location(code: "VT", name: "Vermont", type: .usState),
        Location(code: "VA", name: "Virginia", type: .usState),
        Location(code: "WA", name: "Washington", type: .usState),
        Location(code: "WV", name: "West Virginia", type: .usState),
        Location(code: "WI", name: "Wisconsin", type: .usState),
        Location(code: "WY", name: "Wyoming", type: .usState),
    ]
    
    static let canadianProvinces: [Location] = [
        Location(code: "AB", name: "Alberta", type: .canadianProvince),
        Location(code: "BC", name: "British Columbia", type: .canadianProvince),
        Location(code: "MB", name: "Manitoba", type: .canadianProvince),
        Location(code: "NB", name: "New Brunswick", type: .canadianProvince),
        Location(code: "NL", name: "Newfoundland and Labrador", type: .canadianProvince),
        Location(code: "NS", name: "Nova Scotia", type: .canadianProvince),
        Location(code: "ON", name: "Ontario", type: .canadianProvince),
        Location(code: "PE", name: "Prince Edward Island", type: .canadianProvince),
        Location(code: "QC", name: "Quebec", type: .canadianProvince),
        Location(code: "SK", name: "Saskatchewan", type: .canadianProvince),
    ]
    
    static let canadianTerritories: [Location] = [
        Location(code: "NT", name: "Northwest Territories", type: .canadianTerritory),
        Location(code: "NU", name: "Nunavut", type: .canadianTerritory),
        Location(code: "YT", name: "Yukon", type: .canadianTerritory),
    ]
}
