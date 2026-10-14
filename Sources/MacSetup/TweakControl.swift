import AppKit
import SwiftUI
import MacSetupCore

struct TweakControl: View {
    let tweak: TweakDescriptor
    let service: TweakService
    @LocalViewState private var current: Double = 0
    @LocalViewState private var draft: Double = 0
    @LocalViewState private var isStored = false
    @LocalViewState private var status = ""
    @LocalViewState private var working = false
    @LocalViewState private var lastTransaction: String?

    private var changed: Bool { abs(draft - current) > 0.00001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tweak.title).font(.headline)
                    Text(tweak.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 18)
                switch tweak.kind {
                case .toggle:
                    Toggle(tweak.title, isOn: Binding(
                        get: { draft != 0 },
                        set: { draft = $0 ? 1 : 0 }))
                        .labelsHidden().disabled(working)
                case let .slider(minimum, maximum, step):
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: step >= 1 ? "%.0f" : "%.2f", draft))
                            .font(.system(.callout, design: .monospaced))
                        Slider(value: $draft, in: minimum...maximum, step: step)
                            .frame(width: 210).disabled(working)
                    }
                case let .selection(choices):
                    Picker(tweak.title, selection: Binding(
                        get: { Int(draft) },
                        set: { draft = Double($0) })) {
                            ForEach(choices) { choice in
                                Text(choice.title).tag(choice.value)
                            }
                        }
                        .labelsHidden().frame(width: 150).disabled(working)
                }
            }
            if let warning = tweak.warning {
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(status.isEmpty ? (isStored ? "Customized" : "System default") : status)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reload") { load() }.disabled(working)
                    .buttonStyle(.borderless)
                if let transaction = lastTransaction {
                    Button("Undo") { restore(transaction) }.disabled(working)
                        .buttonStyle(.borderless)
                }
                Button("Apply") { apply() }.disabled(working || !changed)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .onAppear(perform: load)
    }

    private func load() {
        do {
            let value = try service.value(for: tweak)
            current = value.doubleValue
            draft = current
            isStored = try service.storedValue(for: tweak) != nil
            status = ""
        } catch { status = "Unable to read: \(error)" }
    }

    private func apply() {
        working = true
        let requested: NSNumber
        switch tweak.kind {
        case .toggle: requested = NSNumber(value: draft != 0)
        case .selection: requested = NSNumber(value: Int(draft))
        case .slider: requested = NSNumber(value: draft)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try service.apply(tweak, value: requested) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(let id):
                    lastTransaction = id
                    load()
                    status = "Applied. Recovery record: \(id)"
                case .failure(let error): status = "Not applied: \(error)"
                }
            }
        }
    }

    private func restore(_ transaction: String) {
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try service.restore(transaction, tweak: tweak) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success:
                    lastTransaction = nil
                    load()
                    status = "Previous setting restored."
                case .failure(let error): status = "Could not restore: \(error)"
                }
            }
        }
    }
}

