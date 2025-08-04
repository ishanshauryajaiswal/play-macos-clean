import CoreData
import Foundation

@objc(Item)
public class Item: NSManagedObject {}

extension Item {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Item> {
        NSFetchRequest<Item>(entityName: "Item")
    }

    @NSManaged public var timestamp: Date?
    @NSManaged public var text: String?
}

extension Item: Identifiable {} 