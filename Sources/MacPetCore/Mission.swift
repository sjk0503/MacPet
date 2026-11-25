import Foundation

/// missions.json 의 트리거 정의. 모르는 type 은 .unknown 으로 받는다.
public enum Trigger: Codable, Equatable {
    case appearanceChange
    case screenshot
    case defaultsChange(domain: String, keys: [String], ignoreValues: [String], to: String?)
    case appOpen(bundleId: String)
    case clipboardChange
    case spaceChange
    case manual
    case accessibility(flag: String, to: Bool)
    case shortcut(keys: String)
    case accessibilityPermission
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type, domain, keys, ignoreValues, flag, to, bundleId
    }

    /// JSON 의 숫자·불리언·문자열을 정규 문자열로 바꿔 받는다(정수 14 → "14", true → "1").
    private struct FlexValue: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { value = b ? "1" : "0" }
            else if let i = try? c.decode(Int.self) { value = String(i) }
            else if let d = try? c.decode(Double.self) { value = NSNumber(value: d).stringValue }
            else { value = try c.decode(String.self) }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "appearanceChange":
            self = .appearanceChange
        case "screenshot":
            self = .screenshot
        case "defaultsChange":
            self = .defaultsChange(
                domain: try c.decode(String.self, forKey: .domain),
                keys: try c.decodeIfPresent([String].self, forKey: .keys) ?? [],
                ignoreValues: (try c.decodeIfPresent([FlexValue].self, forKey: .ignoreValues) ?? []).map(\.value),
                to: try c.decodeIfPresent(FlexValue.self, forKey: .to)?.value)
        case "appOpen":
            self = .appOpen(bundleId: try c.decode(String.self, forKey: .bundleId))
        case "clipboardChange":
            self = .clipboardChange
        case "spaceChange":
            self = .spaceChange
        case "manual":
            self = .manual
        case "accessibility":
            self = .accessibility(
                flag: try c.decode(String.self, forKey: .flag),
                to: try c.decodeIfPresent(Bool.self, forKey: .to) ?? true)
        case "shortcut":
            self = .shortcut(keys: try c.decode(String.self, forKey: .keys))
        case "accessibilityPermission":
            self = .accessibilityPermission
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appearanceChange:
            try c.encode("appearanceChange", forKey: .type)
        case .screenshot:
            try c.encode("screenshot", forKey: .type)
        case let .defaultsChange(domain, keys, ignoreValues, to):
            try c.encode("defaultsChange", forKey: .type)
            try c.encode(domain, forKey: .domain)
            try c.encode(keys, forKey: .keys)
            try c.encode(ignoreValues, forKey: .ignoreValues)
            try c.encodeIfPresent(to, forKey: .to)
        case let .appOpen(bundleId):
            try c.encode("appOpen", forKey: .type)
            try c.encode(bundleId, forKey: .bundleId)
        case .clipboardChange:
            try c.encode("clipboardChange", forKey: .type)
        case .spaceChange:
            try c.encode("spaceChange", forKey: .type)
        case .manual:
            try c.encode("manual", forKey: .type)
        case let .accessibility(flag, to):
            try c.encode("accessibility", forKey: .type)
            try c.encode(flag, forKey: .flag)
            try c.encode(to, forKey: .to)
        case let .shortcut(keys):
            try c.encode("shortcut", forKey: .type)
            try c.encode(keys, forKey: .keys)
        case .accessibilityPermission:
            try c.encode("accessibilityPermission", forKey: .type)
        case let .unknown(type):
            try c.encode(type, forKey: .type)
        }
    }
}

public struct Mission: Codable, Equatable {
    public var id: String
    public var group: String?
    public var after: String?
    public var title: String
    // steps·why 는 웹만 쓰므로 모델에 두지 않는다(JSON 에 있어도 무시)
    public var needs: String?
    public var permission: String?
    public var settingsURL: String?
    public var xp: Int
    public var trigger: Trigger
}
