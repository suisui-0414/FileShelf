import AppKit
import SwiftUI

/// ファイルドラッグ中かどうかを TouchDragView 側と共有するためのフラグ。
/// 二本指タッチ処理とファイルドラッグのマウスイベントが重なって干渉するのを防ぐために使う。
final class FileDragState {
    static let shared = FileDragState()
    var isDragging = false
    private init() {}
}

/// 行のクリック選択（Cmd/Shift対応）と、複数選択時の一斉ドラッグアウトを
/// AppKitレベルで自前実装するためのビュー。
/// SwiftUIの `.onDrag` は1ビューにつき1アイテムしか扱えず、
/// List(selection:) の複数選択と連動して自動で全選択アイテムをまとめてドラッグする
/// ことができないため、NSDraggingSession を直接使う。
struct RowInteractionView: NSViewRepresentable {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let urlsToDrag: () -> [URL]

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onSelect = onSelect
        view.urlsToDrag = urlsToDrag
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onSelect = onSelect
        nsView.urlsToDrag = urlsToDrag
    }
}

final class InteractionNSView: NSView {
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var urlsToDrag: (() -> [URL])?

    private var mouseDownLocation: NSPoint?
    private var didStartDrag = false

    // パネルがキーウィンドウでない時、既定では最初のクリックはフォーカスを当てるためだけに
    // 消費されてしまい、実際のクリックは2回目から扱われる。それだと「フォーカスが当たって
    // いないと取り出せない」ことになるため、最初のクリックからそのまま反応させる
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownLocation else { return }
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) > 4 else { return }
        didStartDrag = true
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag {
            onSelect?(event.modifierFlags)
        }
        mouseDownLocation = nil
        didStartDrag = false
    }

    private func beginDrag(with event: NSEvent) {
        let urls = urlsToDrag?() ?? []
        guard !urls.isEmpty else { return }

        // willBeginAt デリゲート呼び出しは非同期で来ることがあり、そのわずかな遅れの間
        // TouchDragView 側のガードが効かない瞬間ができてしまうため、ここで同期的に立てる
        FileDragState.shared.isDragging = true

        let draggingItems: [NSDraggingItem] = urls.enumerated().map { index, url in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 32, height: 32)
            let cascade = CGFloat(index) * 6
            draggingItem.setDraggingFrame(
                NSRect(x: cascade, y: -cascade, width: size.width, height: size.height),
                contents: icon
            )
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }
}

extension InteractionNSView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        FileDragState.shared.isDragging = true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        FileDragState.shared.isDragging = false
    }
}
