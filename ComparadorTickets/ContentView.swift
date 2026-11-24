import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updateManager: AppUpdateManager
    @Query(sort: \Product.canonicalName) private var products: [Product]

    @AppStorage("geminiAPIKey") private var geminiAPIKey = ""
    @State private var selectedCategory = "Todas"
    @State private var searchText = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isAnalyzing = false
    @State private var statusBanner = ""

    private var allCategories: [String] {
        let base = ["Todas"] + ProductCategory.allCases.map(\.rawValue)
        let extras = updateManager.extraCategories.filter { !base.contains($0) }
        return base + extras
    }

    private var filteredProducts: [Product] {
        products.filter { product in
            let matchesCat = selectedCategory == "Todas" || product.category == selectedCategory
            let matchesSearch = searchText.isEmpty || product.canonicalName.localizedCaseInsensitiveContains(searchText)
            return matchesCat && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Subir ticket (Foto o PDF)") {
                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Foto ticket", systemImage: "photo")
                        }
                        Spacer()
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("PDF ticket", systemImage: "doc.fill")
                        }
                    }
                    if isAnalyzing {
                        ProgressView("Analizando ticket con Gemini...")
                    } else if !statusBanner.isEmpty {
                        Text(statusBanner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Categorias y comparador por kilo / litro") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(allCategories, id: \.self) { cat in
                                Button(cat) {
                                    selectedCategory = cat
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(selectedCategory == cat ? .blue : .gray.opacity(0.25))
                                .foregroundStyle(selectedCategory == cat ? .white : .primary)
                            }
                        }
                    }

                    ForEach(filteredProducts) { product in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(product.canonicalName)
                                    .font(.headline)
                                Spacer()
                                Text(product.category)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            if let best = product.cheapestRecord {
                                Text("Mas barato: \(best.supermarket) — \(String(format: "%.2f", best.unitPrice)) €/\(product.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }

                            ForEach(product.records.sorted(by: { $0.unitPrice < $1.unitPrice })) { rec in
                                Text("• \(rec.supermarket): \(String(format: "%.2f", rec.unitPrice)) €/\(product.unit) (\(String(format: "%.2f", rec.totalPaid)) €)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Ajustes y mejoras") {
                    SecureField("API Key de Gemini", text: $geminiAPIKey)
                    Button {
                        Task { await updateManager.checkForUpdates() }
                    } label: {
                        HStack {
                            Label("Buscar mejoras", systemImage: "arrow.triangle.2.circlepath")
                            if updateManager.isChecking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    Text(updateManager.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !updateManager.releaseNotes.isEmpty {
                        Text(updateManager.releaseNotes)
                            .font(.caption)
                    }
                    if let url = updateManager.downloadURL {
                        Link("Descargar nueva version (.ipa)", destination: url)
                    }
                }
            }
            .navigationTitle("Comparador Tickets")
            .searchable(text: $searchText, prompt: "Buscar producto")
            .onChange(of: selectedPhoto) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                            statusBanner = "No se pudieron leer los datos de la foto seleccionada."
                            return
                        }
                        await processReceipt(data: data, mimeType: "image/jpeg")
                    } catch {
                        statusBanner = error.localizedDescription
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        Task { await processReceipt(data: data, mimeType: "application/pdf") }
                    } catch {
                        statusBanner = error.localizedDescription
                    }
                case .failure(let error):
                    statusBanner = error.localizedDescription
                }
            }
        }
    }

    private func processReceipt(data: Data, mimeType: String) async {
        isAnalyzing = true
        statusBanner = ""
        defer { isAnalyzing = false }

        do {
            let service = ReceiptAnalyzerService(apiKey: geminiAPIKey)
            let existing = products.map(\.canonicalName)
            let parsed = try await service.analyze(
                data: data,
                mimeType: mimeType,
                existingNames: existing,
                extraRules: updateManager.dynamicPromptRules
            )

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let parsedDate = formatter.date(from: parsed.dateISO) ?? Date()

            for item in parsed.items {
                let targetProduct: Product
                if let existingProduct = products.first(where: { $0.canonicalName.caseInsensitiveCompare(item.canonicalName) == .orderedSame }) {
                    targetProduct = existingProduct
                } else {
                    let created = Product(canonicalName: item.canonicalName, category: item.category, unit: item.unit)
                    modelContext.insert(created)
                    targetProduct = created
                }

                let record = PriceRecord(
                    rawText: item.rawTicketText,
                    supermarket: parsed.supermarket,
                    totalPaid: item.totalPaid,
                    quantity: item.netQuantity,
                    purchaseDate: parsedDate,
                    product: targetProduct
                )
                modelContext.insert(record)
            }

            try modelContext.save()
            statusBanner = "Ticket de \(parsed.supermarket) guardado (\(parsed.items.count) articulos)."
        } catch {
            statusBanner = error.localizedDescription
        }
    }
}
