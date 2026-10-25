import AppKit
import Combine

/// One native undo stack for metadata transactions in this window. Source file
/// deletion and successful playback metadata never masquerade as reversible edits.
@MainActor final class WallpaperLibraryRelationshipUndo {
    let undoManager = RelationshipUndoManager()
    private let collections: UserCollectionsController
    private let report: (Error) -> Void
    private let didRestore: () -> Void
    private var subscription: AnyCancellable?

    init(collections: UserCollectionsController, report: @escaping (Error) -> Void,
         didRestore: @escaping () -> Void) {
        self.collections = collections; self.report = report; self.didRestore = didRestore
        undoManager.levelsOfUndo = 30
        collections.onOrganizationTransaction = { [weak self] before, after, name, epoch in
            self?.register(expected: after, replacement: before, name: name, epoch: epoch)
        }
        subscription = collections.$snapshot.map(\.resetEpoch).removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.undoManager.removeAllActions()
        }
    }

    private func register(expected: LibraryCollectionsOrganizationState, replacement: LibraryCollectionsOrganizationState,
                          name: String, epoch: UUID) {
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(expected: expected, replacement: replacement, name: name, epoch: epoch)
        }
        undoManager.setActionName(name)
    }

    private func restore(expected: LibraryCollectionsOrganizationState, replacement: LibraryCollectionsOrganizationState,
                         name: String, epoch: UUID) {
        // Register the reciprocal synchronously while NSUndoManager is inside
        // undo/redo. Registering only after await would clear its redo stack.
        register(expected: replacement, replacement: expected, name: name, epoch: epoch)
        undoManager.isApplyingTransaction = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.undoManager.isApplyingTransaction = false }
            do {
                try await self.collections.restoreOrganization(expected: expected, replacement: replacement, expectedEpoch: epoch)
                guard self.collections.snapshot.resetEpoch == epoch, !self.collections.isResetting else { return }
                self.didRestore()
            } catch {
                // Expected-state comparison in SQLite rejects a later unrelated
                // edit or alias change. Never roll that state back to an old UI.
                guard self.collections.snapshot.resetEpoch == epoch, !self.collections.isResetting else { return }
                self.undoManager.removeAllActions()
                self.report(error)
            }
        }
    }
}

@MainActor final class RelationshipUndoManager: UndoManager {
    let applyingChanges = PassthroughSubject<Void, Never>()
    var isApplyingTransaction = false {
        didSet {
            guard oldValue != isApplyingTransaction else { return }
            applyingChanges.send(())
        }
    }
    override var canUndo: Bool { !isApplyingTransaction && super.canUndo }
    override var canRedo: Bool { !isApplyingTransaction && super.canRedo }
    override func undo() { guard !isApplyingTransaction else { return }; super.undo() }
    override func redo() { guard !isApplyingTransaction else { return }; super.redo() }
}
