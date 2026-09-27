import SwiftUI

struct HistoryView: View {
    var viewModel: PhotoEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.editHistory.isEmpty {
                    ContentUnavailableView(
                        "No Edits Yet",
                        systemImage: "clock",
                        description: Text("Edits you make will show up here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.editHistory) { edit in
                            HStack(spacing: Theme.spacingM) {
                                Image(systemName: "textformat")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.accentSoft, in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(edit.originalText)
                                            .strikethrough()
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(edit.newText)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.subheadline)
                                    .lineLimit(1)

                                    Text(Self.timeFormatter.string(from: edit.timestamp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("\(viewModel.editHistory.count) edit\(viewModel.editHistory.count == 1 ? "" : "s")")
                    }

                    Section {
                        Button(role: .destructive) {
                            Haptics.warning()
                            withAnimation { viewModel.revertToOriginal() }
                            dismiss()
                        } label: {
                            Label("Revert to Original Photo", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .navigationTitle("Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
