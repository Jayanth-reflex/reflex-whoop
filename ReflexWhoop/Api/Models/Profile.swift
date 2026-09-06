import Foundation

/// `GET /v2/user/profile/basic`.
struct Profile: Decodable {
    let userId: Int64
    let email: String
    let firstName: String
    let lastName: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

/// `GET /v2/user/measurement/body`.
struct BodyMeasurement: Decodable {
    let heightMeter: Double
    let weightKilogram: Double
    let maxHeartRate: Int

    enum CodingKeys: String, CodingKey {
        case heightMeter = "height_meter"
        case weightKilogram = "weight_kilogram"
        case maxHeartRate = "max_heart_rate"
    }
}
