import Foundation
import SwiftData

enum ProductCategory: String, CaseIterable, Codable {
    case carne = "Carne"
    case pescado = "Pescado"
    case lacteos = "Lacteos"
    case aceite = "Aceite"
    case pasta = "Pasta"
    case frutaVerdura = "Fruta y Verdura"
    case limpieza = "Limpieza"
    case otros = "Otros"
}

@Model
final class Product {
    @Attribute(.unique) var canonicalName: String
    var category: String
    var unit: String
    @Relationship(deleteRule: .cascade, inverse: \PriceRecord.product)
    var records: [PriceRecord] = []

    init(canonicalName: String, category: String, unit: String) {
        self.canonicalName = canonicalName
        self.category = category
        self.unit = unit
    }

    var cheapestRecord: PriceRecord? {
        records.min(by: { .unitPrice < .unitPrice })
    }
}

@Model
final class PriceRecord {
    var rawText: String
    var supermarket: String
    var totalPaid: Double
    var quantity: Double
    var unitPrice: Double
    var purchaseDate: Date
    var product: Product?

    init(rawText: String, supermarket: String, totalPaid: Double, quantity: Double, purchaseDate: Date, product: Product? = nil) {
        let safeQty = quantity > 0 ? quantity : 1.0
        self.rawText = rawText
        self.supermarket = supermarket
        self.totalPaid = totalPaid
        self.quantity = safeQty
        self.unitPrice = totalPaid / safeQty
        self.purchaseDate = purchaseDate
        self.product = product
    }
}

struct ParsedReceiptDTO: Codable {
    let supermarket: String
    let dateISO: String
    let items: [ParsedItemDTO]
}

struct ParsedItemDTO: Codable {
    let rawTicketText: String
    let canonicalName: String
    let category: String
    let totalPaid: Double
    let netQuantity: Double
    let unit: String
}
