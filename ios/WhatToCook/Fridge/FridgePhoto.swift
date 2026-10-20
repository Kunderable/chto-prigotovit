import PhotosUI
import SwiftUI
import UIKit

/// Кнопка в холодильнике: камера или фото из галереи → список найденного → подтверждение.
struct FridgePhotoButton: View {
    let recognizer: FridgeRecognizer
    @State private var pickerItem: PhotosPickerItem?
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var photo: UIImage?

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Камера", systemImage: "camera") { showCamera = true }
            }
            Button("Выбрать из фото", systemImage: "photo.on.rectangle") { showGallery = true }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сфотографировать холодильник").foregroundStyle(.primary)
                    Text("Найду продукты и добавлю их сюда").font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "camera.viewfinder").foregroundStyle(Color.paprika)
            }
        }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo = $0 }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
                pickerItem = nil
            }
        }
        .sheet(item: $photo) { image in
            RecognitionSheet(image: image, recognizer: recognizer)
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private struct RecognitionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let recognizer: FridgeRecognizer

    @State private var items: [RecognizedItem]?
    @State private var selected: Set<String> = []
    @State private var error: String?

    /// Модели хватает 1280 px по длинной стороне, а фото с камеры весит в десятки раз больше.
    private static let maxSide: CGFloat = 1280

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(height: 160).clipped()
                        .listRowInsets(EdgeInsets())
                }
                if let error {
                    ContentUnavailableView {
                        Label("Не получилось", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Попробовать ещё раз") { Task { await run() } }.buttonStyle(.glass)
                    }
                } else if let items {
                    if items.isEmpty {
                        ContentUnavailableView("Продуктов не видно", systemImage: "refrigerator",
                                               description: Text("Попробуй сфотографировать ближе и при хорошем свете."))
                    } else {
                        Section {
                            ForEach(items) { item in row(item) }
                        } footer: {
                            Text("Сними отметку с того, чего на самом деле нет. Количество примерное — его можно поправить в холодильнике.")
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Смотрю, что в холодильнике…").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Что нашлось")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить (\(selected.count))") {
                        model.addRecognized((items ?? []).filter { selected.contains($0.name) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await run() }
        }
    }

    private func row(_ item: RecognizedItem) -> some View {
        Button {
            if selected.contains(item.name) { selected.remove(item.name) } else { selected.insert(item.name) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected.contains(item.name) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(item.name) ? Color.green : Color.secondary)
                Text(item.name).foregroundStyle(.primary)
                Spacer()
                Text(item.amount == nil ? "есть" : Format.amount(item.amount, item.unit))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
    }

    private func run() async {
        error = nil
        items = nil
        guard let jpeg = Self.jpeg(image) else {
            error = "Не получилось прочитать фото."
            return
        }
        do {
            let found = try await recognizer.recognize(jpeg: jpeg)
            items = found
            selected = Set(found.map(\.name))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
