import CoreFoundation
import SwiftUI
import MacSetupCore

struct MacOSPreferenceCard: View {
    let setting: MacOSSetting
    @Binding var edit: MacOSPreferenceEdit
    let currentDescription: String
    @LocalViewState private var showingDetails = false

    private var descriptor: TweakDescriptor? { TweakRegistry.all.first { $0.id == setting.id } }
    private var isList: Bool { setting.value is [Any] }
    private var isDictionary: Bool { setting.operation == "finder-list" }
    private var boolean: Bool {
        if let number = setting.value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() }
        if let descriptor, case .toggle = descriptor.kind { return true }
        return ["spaces.order", "finder.tabs", "menubar.desktop"].contains(setting.id)
    }
    private var fallback: Any {
        if let value = setting.value { return value }
        if let descriptor { return descriptor.fallback }
        if let choice = stringChoices?.first(where: { !$0.value.isEmpty }) { return choice.value }
        return NSNumber(value: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(setting.title).font(SetupDesign.sectionTitle)
                    Text(summary).font(SetupDesign.body).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Include in profile", isOn: $edit.enabled).toggleStyle(.checkbox)
                    .accessibilityLabel("Include \(setting.title) in profile")
            }
            Text("Current: " + currentDescription).font(SetupDesign.caption).foregroundStyle(.secondary)
            if isList {
                Text("Including this card clears the pinned list. Leaving it off keeps your existing pins; app paths and bookmarks are never copied into the portable file.")
                    .font(SetupDesign.body).foregroundStyle(.secondary)
            } else if isDictionary {
                DisclosureGroup("Finder list details", isExpanded: $showingDetails) {
                    finderDetails.padding(.top, 8)
                }.disabled(!edit.enabled)
            } else {
                HStack {
                    Toggle("Use system default", isOn: Binding(
                        get: { edit.value == nil },
                        set: { edit.value = $0 ? nil : fallback }))
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Use system default for \(setting.title)")
                    Spacer()
                    valueControl.disabled(edit.value == nil || !edit.enabled).frame(width: 240)
                }.disabled(!edit.enabled)
            }
            if setting.minimumOS > ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
                Text("Requires macOS \(setting.minimumOS) or later.")
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
            }
        }.setupCard()
    }

    private var summary: String {
        if let descriptor { return descriptor.summary }
        switch setting.id {
        case "spaces.order": return "Allow macOS to reorder Spaces based on recent use."
        case "spaces.displays": return "Choose whether a Space spans connected displays. Log out for this to take effect."
        case "appearance.dark": return "Choose the native macOS appearance."
        case "dock.orientation": return "Place the Dock along the bottom, left or right screen edge."
        case "desktop.icons": return "Show files and folders on the desktop."
        case "desktop.widgets": return "Hide widgets from the desktop."
        case "finder.view": return "Choose the initial Finder view for folders without their own saved view."
        case "finder.group": return "Choose how Finder groups items. Individual folders can keep their own view."
        case "finder.tabs", "finder.windowTabs": return "Control whether folders and app windows open in tabs."
        case "finder.listOptions": return "Choose list columns, sizes, sorting and previews without replacing unrelated Finder metadata."
        case "trackpad.builtIn.secondary", "trackpad.bluetooth.secondary": return "Use two fingers for secondary click on this trackpad."
        case "trackpad.builtIn.corner", "trackpad.bluetooth.corner": return "Choose a trackpad corner for secondary click."
        default: return "Include this preference in your saved macOS setup."
        }
    }

    @ViewBuilder private var valueControl: some View {
        if boolean {
            Toggle("On", isOn: Binding(get: { (edit.value as? NSNumber)?.boolValue ?? false },
                                      set: { edit.value = $0 })).toggleStyle(.checkbox)
                .accessibilityLabel(setting.title)
        } else if let choices = stringChoices {
            SetupDropdown(title: setting.title,
                          selection: Binding(get: { edit.value as? String ?? "" }, set: { edit.value = $0.isEmpty ? nil : $0 }),
                          choices: choices)
        } else if let descriptor, case .selection(let choices) = descriptor.kind {
            SetupDropdown(title: setting.title,
                          selection: Binding(get: { (edit.value as? NSNumber)?.intValue ?? descriptor.fallback.intValue }, set: { edit.value = $0 }),
                          choices: choices.map { .init(value: $0.value, title: $0.title) })
        } else if let descriptor, case let .slider(minimum, maximum, step) = descriptor.kind {
            VStack(spacing: 4) {
                Text(String(format: step < 1 ? "%.2f" : "%.0f", (edit.value as? NSNumber)?.doubleValue ?? descriptor.fallback.doubleValue)).monospacedDigit()
                SetupValueSlider(value: Binding(get: { (edit.value as? NSNumber)?.doubleValue ?? descriptor.fallback.doubleValue }, set: { edit.value = $0 }),
                       range: minimum...maximum, step: step, title: setting.title)
            }
        } else if setting.id.hasSuffix(".corner") {
            SetupDropdown(title: setting.title,
                          selection: Binding(get: { (edit.value as? NSNumber)?.intValue ?? 0 }, set: { edit.value = $0 }),
                          choices: [.init(value: 0, title: "No corner"), .init(value: 2, title: "Bottom right"), .init(value: 3, title: "Bottom left")])
        } else {
            TextField(setting.title, text: Binding(get: { edit.value.map { String(describing: $0) } ?? "" }, set: { edit.value = $0 }))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var stringChoices: [SetupChoice<String>]? {
        switch setting.id {
        case "appearance.dark": return [.init(value: "", title: "Light (system default)"), .init(value: "Dark", title: "Dark")]
        case "dock.orientation": return [.init(value: "bottom", title: "Bottom"), .init(value: "left", title: "Left"), .init(value: "right", title: "Right")]
        case "finder.view": return [.init(value: "Nlsv", title: "List"), .init(value: "icnv", title: "Icons"), .init(value: "clmv", title: "Columns"), .init(value: "Flwv", title: "Gallery")]
        case "finder.group": return ["None", "Kind", "Date Modified", "Date Created", "Size", "Tags"].map { .init(value: $0, title: $0) }
        case "finder.windowTabs": return [.init(value: "always", title: "Always"), .init(value: "manual", title: "Manually"), .init(value: "fullscreen", title: "In full screen")]
        default: return nil
        }
    }

    private func option<T>(_ key: String, fallback: T) -> Binding<T> {
        Binding(get: { (edit.value as? [String: Any])?[key] as? T ?? fallback }, set: { value in
            var options = edit.value as? [String: Any] ?? setting.value as? [String: Any] ?? [:]
            options[key] = value; edit.value = options
        })
    }

    private var finderDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Icon size")
                Stepper(value: option("iconSize", fallback: 32.0), in: 16...512, step: 1) {
                    Text("\(Int(option("iconSize", fallback: 32.0).wrappedValue)) pt")
                }
                Text("Text size")
                Stepper(value: option("textSize", fallback: 13.0), in: 9...40, step: 1) {
                    Text("\(Int(option("textSize", fallback: 13.0).wrappedValue)) pt")
                }
            }
            HStack {
                Text("Sort by")
                SetupDropdown(title: "Finder sort column", selection: option("sortColumn", fallback: "dateModified"),
                              choices: columns.map { .init(value: $0.id, title: $0.title) })
                Toggle("Ascending", isOn: option("sortAscending", fallback: false)).toggleStyle(.checkbox)
            }
            ForEach([("useRelativeDates", "Use relative dates"), ("calculateAllSizes", "Calculate folder sizes"), ("showIconPreview", "Show icon previews")], id: \.0) { key, title in
                Toggle(title, isOn: option(key, fallback: false)).toggleStyle(.checkbox)
            }
            Text("Visible columns").fontWeight(.medium)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                ForEach(columns, id: \.id) { column in
                    Toggle(column.title, isOn: Binding(get: { option("visibleColumns", fallback: ["name"]).wrappedValue.contains(column.id) }, set: { included in
                        var selected = option("visibleColumns", fallback: ["name"]).wrappedValue.filter { $0 != column.id }
                        if included { selected.append(column.id) }
                        option("visibleColumns", fallback: ["name"]).wrappedValue = selected
                    })).toggleStyle(.checkbox).disabled(column.id == "name")
                }
            }
        }
    }

    private var columns: [(id: String, title: String)] {
        [("name", "Name"), ("dateModified", "Date modified"), ("size", "Size"), ("kind", "Kind"),
         ("dateCreated", "Date created"), ("dateLastOpened", "Date last opened"), ("dateAdded", "Date added"),
         ("version", "Version"), ("comments", "Comments"), ("label", "Tags"), ("ubiquity", "iCloud status"),
         ("shareOwner", "Shared by"), ("shareLastEditor", "Last editor"), ("invitationStatus", "Invitation status")]
    }
}
