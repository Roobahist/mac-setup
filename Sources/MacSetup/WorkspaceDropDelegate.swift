import SwiftUI
import UniformTypeIdentifiers
import MacSetupCore

let workspaceDragType = UTType(exportedAs: "com.roobahist.mac-setup.workspace", conformingTo: .text)

struct WorkspaceDropDelegate: DropDelegate {
    let targetID: String
    let selectedTasks: Set<String>
    @Binding var layout: WorkspaceConfiguration
    @Binding var draggingID: String?
    @Binding var dropTargetID: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [workspaceDragType]) && draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTargetID = targetID
    }

    func dropExited(info: DropInfo) { if dropTargetID == targetID { dropTargetID = nil } }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let source = draggingID else { return false }
        layout.moveWorkspace(source, to: targetID, selectedTasks: selectedTasks)
        draggingID = nil; dropTargetID = nil
        return true
    }
}
