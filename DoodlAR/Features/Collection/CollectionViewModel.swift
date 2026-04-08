import Foundation
import SwiftData
import os

/// Manages the creature collection state and SwiftData persistence.
@Observable
@MainActor
final class CollectionViewModel {
    /// All discovered creatures, ordered by discovery date (newest first).
    var creatures: [Creature] = []

    private var modelContext: ModelContext?

    /// Configures the model context for persistence.
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Loads the creature collection from SwiftData.
    func loadCollection() {
        guard let modelContext else {
            Logger.persistence.warning("ModelContext not configured — skipping load")
            return
        }

        do {
            let descriptor = FetchDescriptor<PersistedCreature>(
                sortBy: [SortDescriptor(\.discoveredAt, order: .reverse)]
            )
            let persisted = try modelContext.fetch(descriptor)
            creatures = persisted.compactMap { $0.toDomainModel() }
            Logger.persistence.info("Loaded \(self.creatures.count) creatures from SwiftData")
        } catch {
            Logger.persistence.error("Failed to load collection: \(error.localizedDescription)")
        }
    }

    /// Adds a newly discovered creature to the collection and persists it.
    /// Prevents duplicates based on CreatureType.
    func addCreature(_ creature: Creature) {
        if creatures.contains(where: { $0.type == creature.type }) {
            Logger.persistence.info("Creature \(creature.type.displayName) already in collection, ignoring duplicate.")
            return
        }

        creatures.insert(creature, at: 0)

        guard let modelContext else {
            Logger.persistence.warning("ModelContext not configured — creature not persisted")
            return
        }

        let persisted = PersistedCreature(from: creature)
        modelContext.insert(persisted)

        do {
            try modelContext.save()
            Logger.persistence.info("Persisted \(creature.type.displayName) (total: \(self.creatures.count))")
        } catch {
            Logger.persistence.error("Failed to persist creature: \(error.localizedDescription)")
        }
    }

    /// Updates a creature's nickname.
    func updateNickname(for creatureID: UUID, nickname: String) {
        guard let index = creatures.firstIndex(where: { $0.id == creatureID }) else { return }
        creatures[index].nickname = nickname

        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<PersistedCreature>(
                predicate: #Predicate { $0.id == creatureID }
            )
            if let persisted = try modelContext.fetch(descriptor).first {
                persisted.nickname = nickname
                try modelContext.save()
            }
        } catch {
            Logger.persistence.error("Failed to update nickname: \(error.localizedDescription)")
        }
    }

    /// Clears the entire collection.
    func clearCollection() {
        creatures.removeAll()
        guard let modelContext else { return }
        do {
            try modelContext.delete(model: PersistedCreature.self)
            try modelContext.save()
            Logger.persistence.info("Cleared entire collection")
        } catch {
            Logger.persistence.error("Failed to clear collection: \(error.localizedDescription)")
        }
    }

    /// Deletes a creature from the collection.
    func deleteCreature(id: UUID) {
        creatures.removeAll { $0.id == id }

        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<PersistedCreature>(
                predicate: #Predicate { $0.id == id }
            )
            if let persisted = try modelContext.fetch(descriptor).first {
                modelContext.delete(persisted)
                try modelContext.save()
                Logger.persistence.info("Deleted creature \(id)")
            }
        } catch {
            Logger.persistence.error("Failed to delete creature: \(error.localizedDescription)")
        }
    }
}
