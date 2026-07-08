import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ShelfViewModel
    @State private var isDropTargeted = false
    @State private var selection = Set<ShelfItem.ID>()
    @State private var lastSelectedID: ShelfItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if viewModel.items.isEmpty {
                emptyStateView
            } else {
                itemListView
            }
        }
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var headerView: some View {
        HStack {
            Text("FileShelf")
                .font(.headline)
            Spacer()
            Button("Clear All") {
                viewModel.clearAll()
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.items.isEmpty ? .secondary : .red)
            .disabled(viewModel.items.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("ファイルをドロップ")
                .foregroundColor(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemListView: some View {
        List(selection: $selection) {
            ForEach(viewModel.items) { item in
                ShelfItemRow(
                    item: item,
                    isSelected: selection.contains(item.id),
                    onSelect: { modifiers in handleSelection(of: item, modifiers: modifiers) },
                    onDelete: { viewModel.remove(item) },
                    urlsToDrag: { urlsToDrag(for: item) }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .tag(item.id)
            }
        }
        .listStyle(.plain)
    }

    // 選択中のアイテムをドラッグした場合は選択済み全アイテムをまとめて、
    // 選択されていないアイテムをドラッグした場合はそのアイテム単体を対象にする
    private func urlsToDrag(for item: ShelfItem) -> [URL] {
        if selection.contains(item.id), selection.count > 1 {
            return viewModel.items.filter { selection.contains($0.id) }.map(\.url)
        }
        return [item.url]
    }

    // クリックが確定した(ドラッグしなかった)場合にのみ選択を更新する。
    // 複数選択は Cmd/Shift + クリックの時だけ発生し、ドラッグ中の状態変化には関与しない。
    private func handleSelection(of item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
            lastSelectedID = item.id
        } else if modifiers.contains(.shift),
                  let lastID = lastSelectedID,
                  let lastIndex = viewModel.items.firstIndex(where: { $0.id == lastID }),
                  let currentIndex = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            let range = lastIndex < currentIndex ? lastIndex...currentIndex : currentIndex...lastIndex
            selection = Set(viewModel.items[range].map(\.id))
        } else {
            selection = [item.id]
            lastSelectedID = item.id
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        self.viewModel.add(url: url)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
