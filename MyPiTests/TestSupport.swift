import Foundation
@testable import MyPi

/// A JSONDecoder configured exactly like APIClient's private decoder: it delegates
/// date parsing to `APIClient.parseDate`, so model-decode tests exercise the same
/// multi-format date handling the app uses against the live MyPi server (microsecond
/// precision, with or without a timezone designator).
func makeAPIDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let str = try container.decode(String.self)
        if let date = APIClient.parseDate(str) { return date }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date format: \(str)"
        )
    }
    return decoder
}
