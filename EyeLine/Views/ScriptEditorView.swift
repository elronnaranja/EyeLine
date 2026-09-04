import SwiftUI
import SwiftData

/// Create/edit screen for a single script. Scripts can run to several
/// thousand words, so this uses a plain TextEditor bound directly to the
/// SwiftData model — no intermediate string copies of the whole script are
/// kept around.
struct ScriptEditorView: View {
    @Bindable var script: Script
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Script title", text: $script.title)
                    .focused($titleFocused)
                    .font(.headline)
            }

            Section("Script") {
                TextEditor(text: $script.content)
                    .frame(minHeight: 320)
                    .font(.body)
            }

            if let onDelete {
                Section {
                    Button("Delete Script", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Script")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    script.updatedAt = .now
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }
}
