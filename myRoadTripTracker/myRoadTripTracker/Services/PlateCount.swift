/// A plate and how many trips saw it (#78).
struct PlateCount: Identifiable {
    let location: Location
    let trips: Int
    var id: String { location.code }
}
