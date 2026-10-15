import Foundation

/// Persists the selected editor configurations in a recoverable journal record.
/// The caller decides which drafts are in scope; unrelated drafts are never saved.
public struct SetupConfigurationWriter {
    private let journal: Journal

    public init(journal: Journal) {
        self.journal = journal
    }

    /// Returns a recovery transaction ID, or nil when no configuration is selected.
    /// This protects the saved drafts, not the full sequence of application installs
    /// and desktop service restarts, which require separate recovery records.
    @discardableResult
    public func save(layout: WorkspaceConfiguration? = nil,
                     shortcuts: ShortcutSettings? = nil) throws -> String? {
        guard layout != nil || shortcuts != nil else { return nil }
        try layout?.validate()
        let id = try journal.begin("setup-configuration")
        do {
            if let layout {
                let bytes = try JSONEncoder().encode(layout)
                try journal.write(WorkspaceConfiguration.path(in: journal.paths),
                                  data: bytes, transaction: id)
            }
            if let shortcuts {
                let bytes = try JSONEncoder().encode(shortcuts)
                try journal.write(ShortcutSettings.path(in: journal.paths),
                                  data: bytes, transaction: id)
            }
            try journal.finish(id)
            return id
        } catch {
            do {
                try journal.restore(id)
            } catch {
                throw SetupError("Configuration could not be saved and its previous version could not be restored: \(error). Recovery record: \(id)")
            }
            throw SetupError("Configuration could not be saved: \(error)")
        }
    }
}
