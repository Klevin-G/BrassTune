import Foundation

final class NativePersistenceWriter: @unchecked Sendable {
    private final class SaveRequest: @unchecked Sendable {
        let generation: Int
        let snapshot: NativeLocalSnapshot
        let store: NativePersistenceStore
        let completion: @MainActor (Int, Result<Void, Error>) -> Void

        init(
            generation: Int,
            snapshot: NativeLocalSnapshot,
            store: NativePersistenceStore,
            completion: @escaping @MainActor (Int, Result<Void, Error>) -> Void
        ) {
            self.generation = generation
            self.snapshot = snapshot
            self.store = store
            self.completion = completion
        }
    }

    private let queue = DispatchQueue(label: "com.brasstune.snapshot-writer", qos: .utility)

    func save(
        generation: Int,
        snapshot: NativeLocalSnapshot,
        store: NativePersistenceStore,
        completion: @escaping @MainActor (Int, Result<Void, Error>) -> Void
    ) {
        let request = SaveRequest(
            generation: generation,
            snapshot: snapshot,
            store: store,
            completion: completion
        )
        queue.async {
            let result = Result { try request.store.saveOrThrow(request.snapshot) }
            Task { @MainActor in
                request.completion(request.generation, result)
            }
        }
    }

    func flush() {
        queue.sync {}
    }
}
