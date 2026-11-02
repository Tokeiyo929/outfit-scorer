import SwiftUI
import PhotosUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var editRecord: OutfitRecord?

    var body: some View {
        NavigationStack {
            Group {
                if state.historyBusy && state.records.isEmpty {
                    VStack { ProgressView() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.records.isEmpty {
                    VStack(spacing: 6) {
                        Text("还没有记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let err = state.historyError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(state.records) { rec in
                            HistoryRow(rec: rec,
                                       onEdit: { editRecord = rec },
                                       onDelete: { state.deleteRecord(rec) })
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史记录")
            .refreshable { state.loadHistory(force: true) }
        }
        .onAppear { state.loadHistory() }
        .sheet(item: $editRecord) { rec in
            EditSheet(record: rec)
                .environmentObject(state)
        }
    }
}

// MARK: - 单条记录
struct HistoryRow: View {
    let rec: OutfitRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    ColorDot(hex: rec.top.hex)
                    Text(rec.top.name).font(.subheadline.weight(.medium))
                    if rec.topBad { Text("⚡") }
                    Text("×").font(.subheadline).foregroundStyle(.secondary)
                    ColorDot(hex: rec.bottom.hex)
                    Text(rec.bottom.name).font(.subheadline.weight(.medium))
                    if rec.bottomBad { Text("⚡") }
                }
                Text(rec.dateText).font(.caption).foregroundStyle(.secondary)
                if !rec.comment.isEmpty {
                    Text("💬 " + rec.comment).font(.caption)
                }
            }
            Spacer()

            Text("\(rec.score)").font(.title3.bold()).foregroundStyle(.orange)
            Button(action: onEdit) { Text("✎").font(.title3) }
                .buttonStyle(.plain)
            Button(action: onDelete) { Text("✕").font(.title3).foregroundStyle(.red) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlStr = rec.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    ZStack { Color(uiColor: .systemGray5); ProgressView() }
                }
            }
        } else {
            ZStack { Color(uiColor: .systemGray5); Image(systemName: "photo") }
        }
    }
}

struct ColorDot: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(dotColor)
            .frame(width: 12, height: 12)
    }

    private var dotColor: Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return Color(uiColor: .systemGray3) }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - 编辑记录：评分/点评/雷点/换照片
struct EditSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let record: OutfitRecord

    @State private var score: Double
    @State private var comment: String
    @State private var topBad: Bool
    @State private var bottomBad: Bool
    @State private var newPhoto: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var errText = ""
    @State private var showDeleteConfirm = false

    init(record: OutfitRecord) {
        self.record = record
        _score = State(initialValue: Double(record.score))
        _comment = State(initialValue: record.comment)
        _topBad = State(initialValue: record.topBad)
        _bottomBad = State(initialValue: record.bottomBad)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("评分") {
                    HStack {
                        Slider(value: $score, in: 0...100, step: 1)
                        Text("\(Int(score))").font(.title3.bold()).frame(width: 44)
                    }
                }
                Section("雷点") {
                    HStack(spacing: 10) {
                        thunderChip("⚡ 上衣", on: topBad) { topBad.toggle() }
                        thunderChip("⚡ 裤子", on: bottomBad) { bottomBad.toggle() }
                        Spacer()
                    }
                }
                Section("点评") {
                    TextField("说两句（可选）", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("换照片（可选）") {
                    HStack {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("选新照片", systemImage: "photo.on.rectangle")
                        }
                        Spacer()
                        if let img = newPhoto {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                Section {
                    Button("删除这条记录和照片", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .confirmationDialog("删除这条记录和照片？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                        Button("删除", role: .destructive) {
                            state.deleteRecord(record)
                            dismiss()
                        }
                    }
                }
                if !errText.isEmpty {
                    Section { Text(errText).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "保存中…" : "保存") { save() }
                        .disabled(busy)
                }
            }
            .onChange(of: pickerItem) { item in
                Task { await loadPicked(item) }
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        newPhoto = UIImage(data: data)
    }

    private func thunderChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.orange : Color(uiColor: .systemGray5))
                .foregroundStyle(on ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        errText = ""
        Task {
            do {
                var photo: String?
                if let img = newPhoto { photo = Analyzer.compressToDataUrl(img) }
                _ = try await APIClient.update(id: record.id, body: UpdateRecordBody(
                    score: Int(score.rounded()),
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                    topBad: topBad,
                    bottomBad: bottomBad,
                    photo: photo))
                busy = false
                dismiss()
                state.loadHistory(force: true)
            } catch let e {
                busy = false
                errText = "保存失败：\(e.localizedDescription)"
            }
        }
    }
}
