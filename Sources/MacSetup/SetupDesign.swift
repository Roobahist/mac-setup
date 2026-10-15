import SwiftUI

/// Product-wide typography, spacing and surfaces for the native control center.
enum SetupDesign {
    static let pageWidth: CGFloat = 980
    static let pagePadding: CGFloat = 28
    static let pageSpacing: CGFloat = 20
    static let pageTitle: Font = .system(size: 27, weight: .semibold)
    static let body: Font = .system(size: 13)
    static let sheetTitle: Font = .system(size: 20, weight: .semibold)
    static let sectionTitle: Font = .system(size: 15, weight: .semibold)
    static let caption: Font = .system(size: 11)
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 18
    static let controlHeight: CGFloat = 32
    static let sidebarWidth: CGFloat = 248
    static let sidebarRail: CGFloat = 70
    static let sidebarIconColumn: CGFloat = 54
    static let sidebarRowHeight: CGFloat = 36
}

struct SetupPageHeader: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(SetupDesign.pageTitle).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(SetupDesign.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func setupCard() -> some View {
        padding(SetupDesign.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetupDesign.cardRadius))
    }

    func workspaceControl() -> some View {
        frame(maxWidth: .infinity, minHeight: SetupDesign.controlHeight)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
    }

    func workspaceDropdown() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.leading, 8)
            .padding(.trailing, 23)
            .workspaceControl()
            .overlay(alignment: .trailing) {
                WorkspaceDisclosure(direction: "down")
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }
    }
}

struct WorkspaceDisclosure: View {
    let direction: String

    var body: some View {
        Image(systemName: "chevron.\(direction)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// Header and body cells use the same column widths and gutters.
enum WorkspaceColumns {
    static let gap: CGFloat = 8
    static let inset: CGFloat = 12
    static let verticalInset: CGFloat = 8
    static let grip: CGFloat = 18
    static let glyph: CGFloat = 36
    static let apps: CGFloat = 90
    static let key: CGFloat = 72
    static let display: CGFloat = 108
    static let remove: CGFloat = 24
}
