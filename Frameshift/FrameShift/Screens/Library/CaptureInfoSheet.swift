import SwiftUI

/// Compact info sheet for a captured shot: date/time, pixel dimensions, and
/// the reference it was shot against, if any. No EXIF display — hard
/// constraint (CLAUDE.md).
struct CaptureInfoSheet: View {
    let shot: CapturedPhoto?
    let reference: ReferencePhoto?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let shot {
                    LabeledContent("Captured", value: shot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Dimensions", value: dimensionsString(for: shot.image))
                }
                if let reference {
                    Section("Shot against") {
                        HStack(spacing: 12) {
                            Image(uiImage: reference.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("Imported \(reference.importedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Photo Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dimensionsString(for image: UIImage) -> String {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return "\(width)×\(height)"
    }
}
