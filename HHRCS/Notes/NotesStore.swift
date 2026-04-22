import Foundation
import Combine

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private let storageKey = "hhrcs.notes.v1"

    init() { load() }

    func add(authorName: String, text: String,
             lux: Double? = nil, isRecording: Bool? = nil,
             triggerLabel: String? = nil, enclosureTempC: Double? = nil,
             recordingDuration: String? = nil, hasThumbnail: Bool = false) {
        guard !authorName.trimmingCharacters(in: .whitespaces).isEmpty,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let note = Note(
            authorName:        authorName,
            text:              text,
            lux:               lux,
            isRecording:       isRecording,
            triggerLabel:      triggerLabel,
            enclosureTempC:    enclosureTempC,
            recordingDuration: recordingDuration,
            hasThumbnail:      hasThumbnail
        )
        notes.insert(note, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        save()
    }

    func deleteNote(withID id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }
}
