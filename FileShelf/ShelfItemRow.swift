import AppKit
import SwiftUI

struct ShelfItemRow: View {
    let item: ShelfItem
    let isSelected: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onDelete: () -> Void
    let urlsToDrag: () -> [URL]
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isEmphasizedSelection ? .white : .primary)
                Spacer(minLength: 0)
            }
            // 行の上下左右の余白(padding)もこの内側に含めることで、
            // 余白部分をクリックしても自作ビューの範囲から外れないようにする
            // （外れると下の List 標準のドラッグ選択に奪われ、複数選択と誤認識される原因になっていた）
            .padding(.vertical, 4)
            .padding(.leading, 4)
            // .background だと画像/テキストのレイヤーがヒットテストを先取りしてしまい、
            // アイコンやテキストの真上でクリックしても自作ビューまで届かなかったため、
            // 常に最前面でクリックを受け取れる .overlay に変更する
            .overlay(RowInteractionView(onSelect: onSelect, urlsToDrag: urlsToDrag))

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(isEmphasizedSelection ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .transition(.opacity)
            } else {
                Color.clear.frame(width: 4)
            }
        }
        .contentShape(Rectangle())
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private var isEmphasizedSelection: Bool {
        isSelected && controlActiveState == .key
    }

    private var backgroundColor: Color {
        if isSelected {
            return controlActiveState == .key
                ? Color(nsColor: .selectedContentBackgroundColor)
                : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
        return isHovered ? Color.secondary.opacity(0.1) : Color.clear
    }
}
