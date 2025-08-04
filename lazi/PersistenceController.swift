import CoreData
import Foundation

/// Lightweight Core Data stack for storing transcribed text with timestamp.
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        // Try to locate compiled or source data model.
        let possibleExtensions = ["momd", "mom", "xcdatamodeld", "xcdatamodel"]
        var foundModel: NSManagedObjectModel? = nil
        for ext in possibleExtensions {
            if let url = Bundle.main.url(forResource: "lazi", withExtension: ext),
               let m = NSManagedObjectModel(contentsOf: url) {
                foundModel = m
                break
            }
        }

        // Fallback to merged models if explicit lookup failed (e.g., model renamed by Xcode).
        let model = foundModel ?? NSManagedObjectModel.mergedModel(from: [Bundle.main]) ?? {
            fatalError("[PERSISTENCE] Could not load Core Data model 'lazi'")
        }()

        // If the loaded model lacks the expected 'Item' entity, create it programmatically so the app
        // can always save transcripts even if the compiled model hasn’t been bundled for some reason.
        if model.entitiesByName["Item"] == nil {
            NSLog("[PERSISTENCE] WARNING: 'Item' entity missing from bundled model – creating programmatically")
            let entity = NSEntityDescription()
            entity.name = "Item"
            entity.managedObjectClassName = NSStringFromClass(Item.self)

            let timestampAttr = NSAttributeDescription()
            timestampAttr.name = "timestamp"
            timestampAttr.attributeType = .dateAttributeType
            timestampAttr.isOptional = true

            let textAttr = NSAttributeDescription()
            textAttr.name = "text"
            textAttr.attributeType = .stringAttributeType
            textAttr.isOptional = true

            entity.properties = [timestampAttr, textAttr]

            var entities = model.entities
            entities.append(entity)
            model.entities = entities
        }

        container = NSPersistentContainer(name: "lazi", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Unresolved error \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Persists a new transcript with the current timestamp.
    func save(transcript text: String) {
        let context = container.viewContext
        let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: context)
        item.setValue(Date(), forKey: "timestamp")
        item.setValue(text, forKey: "text")
        do {
            try context.save()
        } catch {
            NSLog("[PERSISTENCE] Failed to save transcript: \(error.localizedDescription)")
        }
    }

    /// Returns the most recent transcripts (default 20) in reverse-chronological order.
    func fetchLatest(limit: Int = 20) -> [String] {
        let context = container.viewContext
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        do {
            let items = try context.fetch(request)
            return items.compactMap { $0.text }
        } catch {
            NSLog("[PERSISTENCE] Failed to fetch latest transcripts: \(error.localizedDescription)")
            return []
        }
    }
} 