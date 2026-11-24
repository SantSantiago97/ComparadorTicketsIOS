import Foundation
import SwiftUI

struct RemoteConfigPayload: Codable {
    let latestAppVersion: String
    let releaseNotes: String
    let downloadIPAURL: String?
    let extraCategories: [String]?
    let systemPromptAdditions: String?
}

@MainActor
final class AppUpdateManager: ObservableObject {
    let currentVersion = "1.0.0"

    @Published var statusText = "Listo para comprobar mejoras."
    @Published var releaseNotes = ""
    @Published var downloadURL: URL?
    @Published var isChecking = false

    @AppStorage("dynamicPromptRules") var dynamicPromptRules = ""
    @AppStorage("customCategoriesJSON") var customCategoriesJSON = "[]"

    private let configURL = URL(string: "https://raw.githubusercontent.com/SantSantiago97/ComparadorTicketsIOS/main/config.json")!

    var extraCategories: [String] {
        guard let data = customCategoriesJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    func checkForUpdates() async {
        isChecking = true
        statusText = "Comprobando mejoras..."
        defer { isChecking = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: configURL)
            let remote = try JSONDecoder().decode(RemoteConfigPayload.self, from: data)

            if let rules = remote.systemPromptAdditions, !rules.isEmpty {
                dynamicPromptRules = rules
            }
            if let cats = remote.extraCategories,
               let encoded = try? JSONEncoder().encode(cats),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                customCategoriesJSON = jsonStr
            }
            if let urlStr = remote.downloadIPAURL, !urlStr.isEmpty {
                downloadURL = URL(string: urlStr)
            }
            releaseNotes = remote.releaseNotes

            if remote.latestAppVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                statusText = "Nueva version \(remote.latestAppVersion) disponible."
            } else {
                statusText = "Reglas actualizadas. App en version \(currentVersion)."
            }
        } catch {
            statusText = "Error al consultar config.json en GitHub."
        }
    }
}
