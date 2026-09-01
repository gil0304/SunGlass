import PhotosUI
import SwiftUI

struct MemoryEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let date: Date

    @State private var comment = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var existingPhotoPath: String?
    @State private var representativeColor: String?
    @State private var photoPalette: [String] = []
    @State private var photoBrightness: Double?
    @State private var photoEdgeDensity: Double?
    @State private var isLoadingPhoto = false
    @State private var error: String?

    var body: some View {
        let pickerImage = previewImage.map { Image(uiImage: $0) }
        let pickerIsLoading = isLoadingPhoto
        let pickerCream = SunGlassStyle.cream
        let pickerTitle = pickerIsLoading ? "読み込み中…" : (pickerImage == nil ? "写真を選ぶ" : "写真を変更")

        NavigationStack {
            ZStack {
                SunGlassBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "text.quote")
                                .font(SunGlassStyle.label(11))
                                .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                                .accessibilityLabel("一言")
                            TextField("今日の記憶", text: $comment, axis: .vertical)
                                .lineLimit(4, reservesSpace: true)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(SunGlassStyle.cream)
                                .padding(16)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "photo")
                                .font(SunGlassStyle.label(11))
                                .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                                .accessibilityLabel("写真")

                            if let pickerImage {
                                pickerImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .accessibilityHidden(true)
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Group {
                                    if pickerIsLoading {
                                        ProgressView()
                                    } else {
                                        Image(systemName: pickerImage == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath")
                                    }
                                }
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(pickerCream)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(pickerIsLoading)
                            .accessibilityLabel(pickerTitle)

                            if representativeColor != nil {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: "wand.and.stars")
                                        .font(SunGlassStyle.label(11))
                                        .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                                        .accessibilityLabel("解析結果")

                                    if !resolvedPalette.isEmpty {
                                        HStack(spacing: 9) {
                                            ForEach(Array(resolvedPalette.enumerated()), id: \.offset) { index, color in
                                                Circle()
                                                    .fill(color)
                                                    .frame(width: index == 0 ? 24 : 20, height: index == 0 ? 24 : 20)
                                            }
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("写真から抽出した色、\(resolvedPalette.count)色")
                                    }

                                    if photoBrightness != nil || photoEdgeDensity != nil {
                                        Text("明るさ \(percentage(photoBrightness))　輪郭 \(percentage(photoEdgeDensity))")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(SunGlassStyle.cream.opacity(0.7))
                                            .accessibilityLabel("明るさ、\(percentage(photoBrightness))、輪郭、\(percentage(photoEdgeDensity))")
                                    }

                                    Label("端末内で解析", systemImage: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(SunGlassStyle.cream.opacity(0.47))
                                }
                                .padding(.top, 4)
                            }
                        }

                        if let error {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(SunGlassStyle.coral)
                        }

                        Button(action: save) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                            .buttonStyle(SunGlassPrimaryButtonStyle())
                            .accessibilityLabel("保存")
                    }
                    .padding(22)
                }
            }
            .navigationTitle(date.formatted(.dateTime.month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(SunGlassStyle.lime)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
            .task {
                if let memory = store.memory(on: date, projectID: projectID) {
                    comment = memory.comment
                    existingPhotoPath = memory.photoPath
                    representativeColor = memory.representativeColor
                    photoPalette = memory.photoPalette ?? []
                    photoBrightness = memory.photoBrightness
                    photoEdgeDensity = memory.photoEdgeDensity
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    imageData = try await selectedPhoto.loadTransferable(type: Data.self)
                    if let imageData {
                        if let analysis = PhotoMemoryService.analyze(imageData) {
                            representativeColor = analysis.representativeColor
                            photoPalette = analysis.palette
                            photoBrightness = analysis.brightness
                            photoEdgeDensity = analysis.edgeDensity
                            error = nil
                        } else {
                            representativeColor = nil
                            photoPalette = []
                            photoBrightness = nil
                            photoEdgeDensity = nil
                            error = "写真の色を解析できませんでした。写真自体は保存できます。"
                        }
                    }
                } catch {
                    self.error = "写真を読み込めませんでした。"
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var previewImage: UIImage? {
        if let imageData { return UIImage(data: imageData) }
        return PhotoMemoryService.load(path: existingPhotoPath)
    }

    @MainActor private var resolvedPalette: [Color] {
        let analyzedColors = photoPalette.compactMap { Color.sunGlassHex($0) }
        if !analyzedColors.isEmpty { return analyzedColors }
        guard let representativeColor, let color = Color.sunGlassHex(representativeColor) else { return [] }
        return [color]
    }

    private func percentage(_ value: Double?) -> String {
        value?.formatted(.percent.precision(.fractionLength(0))) ?? "—"
    }

    private func save() {
        do {
            var path = existingPhotoPath
            if let imageData {
                path = try PhotoMemoryService.store(imageData, projectID: projectID)
            }
            guard store.saveMemory(
                projectID: projectID,
                date: date,
                comment: comment,
                photoPath: path,
                representativeColor: representativeColor,
                photoPalette: photoPalette.isEmpty ? nil : photoPalette,
                photoBrightness: photoBrightness,
                photoEdgeDensity: photoEdgeDensity
            ) != nil else {
                error = store.lastErrorMessage ?? "記憶を端末へ保存できませんでした。"
                return
            }
            dismiss()
        } catch {
            self.error = "写真を端末へ保存できませんでした。"
        }
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSinceReferenceDate }
}
