import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var forge: ForgeStore
    @State private var selectedId: String?
    @State private var search = ""
    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var draftPinned = false
    @State private var draftTaskId = ""
    @State private var saving = false
    @State private var lastError: String?

    private var filtered: [PlannerNote] {
        forge.notes.filter { note in
            search.isEmpty
                || note.title.localizedCaseInsensitiveContains(search)
                || note.content.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedNote: PlannerNote? {
        guard let selectedId else { return nil }
        return forge.notes.first(where: { $0.id == selectedId })
    }

    var body: some View {
        HSplitView {
            sidebar
            editor
        }
        .navigationTitle("Notes")
        .alert("Notes Action Failed", isPresented: Binding(
            get: { lastError != nil },
            set: { if !$0 { lastError = nil } }
        )) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
        .onAppear {
            if selectedId == nil {
                selectedId = forge.notes.first?.id
                loadSelectedNote()
            }
        }
        .onChange(of: selectedId) { _, _ in
            loadSelectedNote()
        }
        .onChange(of: forge.notes) { _, _ in
            if selectedId == nil {
                selectedId = forge.notes.first?.id
            }
            loadSelectedNote()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                SearchField(text: $search, placeholder: "Search notes…")
                Button {
                    forge.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Button {
                    createBlankNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.bar)

            Divider()

            if !forge.isAvailable && !forge.isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Planner notes unavailable")
                        .foregroundStyle(.secondary)
                    Text(forge.lastError ?? "The harness control plane is not reachable.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(search.isEmpty ? "No notes yet" : "No matching notes")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selectedId) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.title)
                                .font(.body)
                                .lineLimit(1)
                            if note.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(note.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                    .tag(note.id)
                }
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedNote == nil ? "New Note" : "Edit Note")
                    .font(.title3.bold())
                Spacer()
                if let task = linkedTask {
                    Label(task.title, systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Note title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Linked task ID (optional)", text: $draftTaskId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Toggle("Pinned", isOn: $draftPinned)
                .toggleStyle(.checkbox)

            TextEditor(text: $draftContent)
                .font(.body)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

            HStack {
                if selectedNote != nil {
                    Button("Delete", role: .destructive) {
                        Task { await deleteSelectedNote() }
                    }
                }
                Spacer()
                Button("New Note") {
                    createBlankNote()
                }
                .buttonStyle(.bordered)
                Button(saving ? "Saving…" : "Save") {
                    Task { await saveNote() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }

            Spacer()
        }
        .padding(20)
    }

    private var linkedTask: PlannerTask? {
        guard let taskId = selectedNote?.taskId, !taskId.isEmpty else { return nil }
        return forge.tasks.first(where: { $0.id == taskId })
    }

    private func loadSelectedNote() {
        guard let selectedNote else {
            draftTitle = ""
            draftContent = ""
            draftPinned = false
            draftTaskId = ""
            return
        }
        draftTitle = selectedNote.title
        draftContent = selectedNote.content
        draftPinned = selectedNote.pinned
        draftTaskId = selectedNote.taskId ?? ""
    }

    private func createBlankNote() {
        selectedId = nil
        draftTitle = ""
        draftContent = ""
        draftPinned = false
        draftTaskId = ""
    }

    private func saveNote() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if var note = selectedNote {
                note.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                note.content = draftContent
                note.pinned = draftPinned
                note.taskId = draftTaskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftTaskId
                try await forge.updateNote(note)
                selectedId = note.id
            } else {
                let created = try await forge.createNote(
                    title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftTitle,
                    content: draftContent,
                    pinned: draftPinned,
                    taskId: draftTaskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftTaskId
                )
                selectedId = created.id
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func deleteSelectedNote() async {
        guard let selectedNote else { return }
        do {
            try await forge.deleteNote(selectedNote.id)
            selectedId = forge.notes.first?.id
        } catch {
            lastError = error.localizedDescription
        }
    }
}
