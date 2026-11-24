import Foundation

struct ReceiptAnalyzerService {
    let apiKey: String

    func analyze(data: Data, mimeType: String, existingNames: [String], extraRules: String) async throws -> ParsedReceiptDTO {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "ReceiptAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta la API Key de Gemini en Ajustes."])
        }

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(cleanKey)")!
        let catalogText = existingNames.isEmpty ? "Ninguno" : existingNames.joined(separator: ", ")

        let prompt = """
        Extrae de este ticket (imagen o PDF) el supermercado, la fecha en formato YYYY-MM-DD y cada articulo.
        1. Si el articulo coincide con alguno de estos productos ya existentes: [\(catalogText)], usa exactamente ese canonicalName. Si es nuevo, usa un nombre generico claro y normalizado.
        2. Clasifica en una categoria clara como: Carne, Pescado, Lacteos, Aceite, Pasta, Fruta y Verdura, Limpieza u Otros (o las adicionales indicadas en reglas).
        3. Normaliza netQuantity y unit: usa "kg" para pesos (500g -> 0.5), "L" para liquidos (750ml -> 0.75) o "ud" si va por unidades.
        \(extraRules)
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_schema": [
                    "type": "OBJECT",
                    "properties": [
                        "supermarket": ["type": "STRING"],
                        "dateISO": ["type": "STRING"],
                        "items": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "rawTicketText": ["type": "STRING"],
                                    "canonicalName": ["type": "STRING"],
                                    "category": ["type": "STRING"],
                                    "totalPaid": ["type": "NUMBER"],
                                    "netQuantity": ["type": "NUMBER"],
                                    "unit": ["type": "STRING"]
                                ],
                                "required": ["rawTicketText", "canonicalName", "category", "totalPaid", "netQuantity", "unit"]
                            ]
                        ]
                    ],
                    "required": ["supermarket", "dateISO", "items"]
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: responseData)
        guard let jsonString = decoded.candidates.first?.content.parts.first?.text,
              let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "ReceiptAnalyzer", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo interpretar la respuesta del modelo."])
        }

        return try JSONDecoder().decode(ParsedReceiptDTO.self, from: jsonData)
    }
}

private struct GeminiResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}
