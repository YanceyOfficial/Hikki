import HikkiUI
import SwiftUI

extension ColorTone {
    static let storageKey = "colorTone"

    /// Its traditional name (nipponcolors.com), localized.
    var title: LocalizedStringKey {
        switch self {
        case .sumi: "app:tone.sumi"
        case .kurenai: "app:tone.kurenai"
        case .terigaki: "app:tone.terigaki"
        case .kohaku: "app:tone.kohaku"
        case .wakatake: "app:tone.wakatake"
        case .seiheki: "app:tone.seiheki"
        case .edomurasaki: "app:tone.edomurasaki"
        }
    }
}
