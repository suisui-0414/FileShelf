import Darwin
import Foundation

class ShelfViewModel: ObservableObject {
    @Published var items: [ShelfItem] = []
    private var fileMonitors: [UUID: DispatchSourceFileSystemObject] = [:]

    func add(url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        let item = ShelfItem(url: url)
        items.append(item)
        startMonitoring(item)
    }

    func remove(_ item: ShelfItem) {
        stopMonitoring(item)
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items.forEach(stopMonitoring)
        items.removeAll()
    }

    // ゴミ箱へ移動されると元のパスがリネーム/削除されるため、
    // それを検知してシェルフから自動的に取り除く
    private func startMonitoring(_ item: ShelfItem) {
        let fd = open(item.url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.remove(item)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitors[item.id] = source
    }

    private func stopMonitoring(_ item: ShelfItem) {
        fileMonitors.removeValue(forKey: item.id)?.cancel()
    }
}
