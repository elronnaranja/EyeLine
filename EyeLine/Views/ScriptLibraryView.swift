import SwiftUI
import SwiftData

struct ScriptLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Script.updatedAt, order: .reverse) private var scripts: [Script]

    @State private var viewModel: ScriptLibraryViewModel?
    @State private var newlyCreatedScript: Script?
    @State private var recordingScript: Script?
    @State private var showingSettings = false

    var body: some View {
        List {
            if scripts.isEmpty {
                ContentUnavailableView(
                    "No Scripts Yet",
                    systemImage: "doc.text",
                    description: Text("Create a script to start recording.")
                )
            }
            ForEach(scripts) { script in
                NavigationLink(value: script) {
                    ScriptRow(script: script)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        viewModel?.delete(script)
                    }
                    Button("Duplicate") {
                        viewModel?.duplicate(script)
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button("Record") {
                        recordingScript = script
                    }
                    .tint(.green)
                }
            }
        }
        .navigationTitle("Scripts")
        .navigationDestination(for: Script.self) { script in
            ScriptEditorView(script: script, onDelete: { viewModel?.delete(script) })
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let viewModel else { return }
                    newlyCreatedScript = viewModel.createScript()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $newlyCreatedScript) { script in
            ScriptEditorView(script: script)
        }
        .fullScreenCover(item: $recordingScript) { script in
            CameraRecordingView(script: script)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(settings: TeleprompterSettings.fetchOrCreate(in: modelContext))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ScriptLibraryViewModel(modelContext: modelContext)
            }
        }
    }
}

private struct ScriptRow: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(script.title.isEmpty ? "Untitled Script" : script.title)
                .font(.headline)
            if !script.preview.isEmpty {
                Text(script.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(script.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
