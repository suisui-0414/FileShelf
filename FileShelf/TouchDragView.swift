import AppKit
import CoreGraphics

/// トラックパッドの二本指タッチ（クリック不要）でウィンドウを移動させるための透明なコンテナビュー。
/// SwiftUI 側のビューが touchesBegan/Moved を実装しないため、レスポンダチェーンを通じて
/// このビュー（contentView）まで自動的にイベントが伝播してくる。
final class TouchDragView: NSView {
    /// 正規化されたタッチ移動量を実際のウィンドウ移動量（ポイント）に変換する倍率。
    /// 体感速度に合わせて調整する。
    private let speedMultiplier: CGFloat = 3.5

    private var lastAveragePosition: CGPoint?
    private var isDraggingWindow = false
    /// ジェスチャー開始時点でのポインタとウィンドウ原点の相対オフセット。
    /// ポインタ位置はこのオフセット＋ウィンドウの実測原点から毎回算出する。
    /// （差分を自前で積算すると setFrameOrigin 側の丸め・クランプで少しずつズレが蓄積するため）
    private var cursorOffsetFromWindowOrigin: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowedTouchTypes = [.indirect]
    }

    override func touchesBegan(with event: NSEvent) {
        guard !FileDragState.shared.isDragging else {
            super.touchesBegan(with: event)
            return
        }
        handleTouchesChanged(event)
        super.touchesBegan(with: event)
    }

    override func touchesMoved(with event: NSEvent) {
        guard !FileDragState.shared.isDragging else {
            super.touchesMoved(with: event)
            return
        }
        let touches = event.touches(matching: .touching, in: self)
        if isDraggingWindow, touches.count == 2, let window,
           let deviceSize = touches.first?.deviceSize, let last = lastAveragePosition {
            let average = averagePosition(of: touches)
            let deltaX = (average.x - last.x) * deviceSize.width * speedMultiplier
            let deltaY = (average.y - last.y) * deviceSize.height * speedMultiplier
            moveWindow(window, by: CGPoint(x: deltaX, y: deltaY))
            lastAveragePosition = average
        } else if touches.count == 1, isDraggingWindow {
            endDrag()
        } else {
            handleTouchesChanged(event)
        }
        super.touchesMoved(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        guard !FileDragState.shared.isDragging else {
            super.touchesEnded(with: event)
            return
        }
        handleTouchesChanged(event)
        super.touchesEnded(with: event)
    }

    override func touchesCancelled(with event: NSEvent) {
        guard !FileDragState.shared.isDragging else {
            super.touchesCancelled(with: event)
            return
        }
        handleTouchesChanged(event)
        super.touchesCancelled(with: event)
    }

    private func handleTouchesChanged(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        switch touches.count {
        case 2:
            if !isDraggingWindow {
                // リスト（スクロール可能領域）の上で始まったジェスチャーは
                // 通常のスクロール操作に譲り、ウィンドウ移動としては扱わない
                guard !isOverScrollableContent(event), let window else {
                    lastAveragePosition = nil
                    return
                }
                isDraggingWindow = true
                let mouseLocation = NSEvent.mouseLocation
                cursorOffsetFromWindowOrigin = CGPoint(
                    x: mouseLocation.x - window.frame.origin.x,
                    y: mouseLocation.y - window.frame.origin.y
                )
                // 連続でワープさせる間はOS側のポインタ追従とワープが競合してカクつくため、切り離す
                CGAssociateMouseAndMouseCursorPosition(0)
            }
            lastAveragePosition = averagePosition(of: touches)
        case 0:
            endDrag()
        default:
            lastAveragePosition = nil
        }
    }

    private func isOverScrollableContent(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard let hitView = hitTest(point) else { return false }
        return hitView.enclosingScrollView != nil
    }

    private func endDrag() {
        lastAveragePosition = nil
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        cursorOffsetFromWindowOrigin = nil
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func averagePosition(of touches: Set<NSTouch>) -> CGPoint {
        let sum = touches.reduce(CGPoint.zero) { partial, touch in
            CGPoint(x: partial.x + touch.normalizedPosition.x, y: partial.y + touch.normalizedPosition.y)
        }
        let count = CGFloat(touches.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    /// ウィンドウを移動したら、その「実際に反映された」原点をもとにポインタ位置を算出する。
    /// window.setFrameOrigin は丸めやクランプで指定値と微妙にズレることがあるため、
    /// 差分を自前で積算せず、都度実測値から計算し直してポインタとウィンドウの相対位置を保つ。
    private func moveWindow(_ window: NSWindow, by delta: CGPoint) {
        guard let offset = cursorOffsetFromWindowOrigin,
              let mainScreenHeight = NSScreen.screens.first?.frame.height else { return }

        var origin = window.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        window.setFrameOrigin(origin)

        let actualOrigin = window.frame.origin
        let newAppKitPoint = CGPoint(x: actualOrigin.x + offset.x, y: actualOrigin.y + offset.y)
        let cgPoint = CGPoint(x: newAppKitPoint.x, y: mainScreenHeight - newAppKitPoint.y)
        CGWarpMouseCursorPosition(cgPoint)
    }
}
