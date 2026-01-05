import CoreGraphics

struct InkTileIdentifier: Hashable {
    let x: Int
    let y: Int
    let scaleStep: Int
}

final class InkTileCache {
    private let capacity: Int
    private var storage: [InkTileIdentifier: CGImage] = [:]
    private var order: [InkTileIdentifier] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func image(for identifier: InkTileIdentifier) -> CGImage? {
        guard let image = storage[identifier] else { return nil }
        if let index = order.firstIndex(of: identifier) {
            order.remove(at: index)
            order.insert(identifier, at: 0)
        }
        return image
    }

    func insert(_ image: CGImage, for identifier: InkTileIdentifier) {
        storage[identifier] = image
        if let index = order.firstIndex(of: identifier) {
            order.remove(at: index)
        }
        order.insert(identifier, at: 0)
        trimIfNeeded()
    }

    func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private func trimIfNeeded() {
        while order.count > capacity {
            let identifier = order.removeLast()
            storage.removeValue(forKey: identifier)
        }
    }
}
