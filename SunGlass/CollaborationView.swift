import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct CollaborationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var showShare = false
    @State private var copied = false
    @State private var showParticipants = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()
                if let project = store.project(id: projectID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            invitation(project)
                            participants(project)
                        }
                        .padding(20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.7))
                    .accessibilityLabel("共有について")
                }
                ToolbarItem(placement: .principal) {
                    Image(systemName: "person.2.fill")
                        .accessibilityLabel("共同制作")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                        .foregroundStyle(SunGlassStyle.lime)
                        .accessibilityLabel("閉じる")
                }
            }
            .alert("共有について", isPresented: $showPrivacy) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("実名は不要です。カメラ映像は共有されず、共同データはこの端末内に保存されます。")
            }
            .sheet(isPresented: $showShare) {
                if let project = store.project(id: projectID), let code = project.inviteCode {
                    ActivitySheet(items: ["SUN GLASS「\(project.title)」へ参加してください。招待コード: \(code)\nsunglass://join/\(code)"])
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func invitation(_ project: GlassProject) -> some View {
        VStack(spacing: 16) {
            if let code = project.inviteCode {
                if let image = QRCodeRenderer.image(for: "sunglass://join/\(code)") {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 158, height: 158)
                        .padding(10)
                        .background(SunGlassStyle.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("共同作品の招待QRコード")
                }

                VStack(spacing: 4) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .foregroundStyle(SunGlassStyle.cream)
                }

                HStack(spacing: 9) {
                    Button {
                        UIPasteboard.general.string = code
                        withAnimation { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 26)
                    }
                    .buttonStyle(SunGlassSecondaryButtonStyle())
                    .accessibilityLabel(copied ? "コードをコピーしました" : "招待コードをコピー")

                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 26)
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .accessibilityLabel("招待を共有")
                }
            } else {
                Button {
                    _ = store.enableCollaboration(for: projectID)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 19, weight: .bold))
                        .frame(height: 28)
                }
                .buttonStyle(SunGlassPrimaryButtonStyle())
                .accessibilityLabel("共同制作を有効にする")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func participants(_ project: GlassProject) -> some View {
        DisclosureGroup(isExpanded: $showParticipants) {
            VStack(spacing: 0) {
                ForEach(project.members) { member in
                    HStack(spacing: 11) {
                        Circle()
                            .fill(SunGlassStyle.cream.opacity(0.16))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SunGlassStyle.cream)
                                    .accessibilityHidden(true)
                            }

                        Text(member.displayName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                        if member.role == .owner {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SunGlassStyle.lime)
                                .accessibilityLabel("作成者")
                        } else if let region = member.assignedRegion {
                            Text(region)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(SunGlassStyle.cream.opacity(0.42))
                        }
                    }
                    .foregroundStyle(SunGlassStyle.cream)
                    .padding(.vertical, 10)
                    if member.id != project.members.last?.id {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        } label: {
            Label("\(project.members.count) / \(AppStore.maximumMembers)", systemImage: "person.2")
                .accessibilityLabel("参加者 \(project.members.count) / \(AppStore.maximumMembers)")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream.opacity(0.75))
        .padding(14)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}

private enum QRCodeRenderer {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
