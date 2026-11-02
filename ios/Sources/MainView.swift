import SwiftUI
import PhotosUI

extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ cond: Bool, transform: (Self) -> Content) -> some View {
        if cond { transform(self) } else { self }
    }
}

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WeatherCard()

                    switch state.stage {
                    case .pick: pickSection
                    case .crop: CropView()
                    case .preview: previewSection
                    case .result: resultSection
                    }
                }
                .padding()
            }
            .navigationTitle("穿搭打分")
            .toolbar {
                if state.stage != .pick {
                    Button("取消") { state.cancelPhoto() }
                }
            }
        }
        .task { state.loadWeather() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { state.loadWeather() }
        }
        .onChange(of: pickerItem) { item in
            Task { await loadPickerItem(item) }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                state.startNewPhoto(img)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 选拍照/相册
    private var pickSection: some View {
        VStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showPicker = true
            } label: {
                Label("从相册选", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 识别前：拖分界线
    private var previewSection: some View {
        VStack(spacing: 12) {
            PreviewCanvas(
                image: state.loadedImg!, boundary: state.boundary,
                draggable: true, tappable: false,
                topPos: nil, bottomPos: nil, topHSL: nil, bottomHSL: nil,
                onBoundary: { state.boundary = $0 })
            Text("上下拖动虚线，分开上衣和裤子")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("重新框选") { state.reCrop() }
                    .buttonStyle(.bordered)
                Button("开始识别") { state.analyze() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 识别后：点照片取色 + 结果卡
    private var resultSection: some View {
        VStack(spacing: 12) {
            PreviewCanvas(
                image: state.loadedImg!, boundary: state.boundary,
                draggable: false, tappable: true,
                topPos: state.topPos, bottomPos: state.bottomPos,
                topHSL: state.topHSL, bottomHSL: state.bottomHSL,
                onTap: { state.pickColor(at: $0) })
            Text("点照片取色：先取上衣、再取裤子，下方「取色」可切换目标")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ResultCard()
        }
    }

    private func loadPickerItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        state.startNewPhoto(img)
    }
}

// MARK: - 天气卡
struct WeatherCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            if let w = state.weather {
                HStack(spacing: 12) {
                    Text(w.icon).font(.system(size: 34))
                    Text("\(w.temp)°").font(.system(size: 32, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.text + (w.city.isEmpty ? "" : " · " + w.city))
                            .font(.subheadline.weight(.semibold))
                        Text("体感 \(w.feels)° · 湿度 \(w.humidity)% · 风 \(w.wind)km/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("👕 " + w.hint)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if state.weatherBusy {
                HStack {
                    ProgressView()
                    Text("获取天气中…").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let err = state.weatherError {
                Text("📍 " + err).font(.subheadline)
                HStack {
                    TextField("输入城市名，如：杭州", text: $state.manualCity)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { state.queryManualCity() }
                    Button("查询") { state.queryManualCity() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 预览画布：分界线 + 取色点
struct PreviewCanvas: View {
    let image: UIImage
    let boundary: Double
    let draggable: Bool
    let tappable: Bool
    let topPos: CGPoint?
    let bottomPos: CGPoint?
    let topHSL: HSL?
    let bottomHSL: HSL?
    var onBoundary: ((Double) -> Void)? = nil
    var onTap: ((CGPoint) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .applyIf(draggable) { $0.gesture(boundaryDrag(in: rect)) }
                    .applyIf(tappable) { $0.gesture(tapGesture(in: rect)) }

                DashedLine()
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: rect.width, height: 2)
                    .position(x: rect.midX, y: rect.minY + rect.height * boundary)

                if let p = topPos, let hsl = topHSL {
                    PickDot(hsl: hsl, text: "上")
                        .position(x: rect.minX + rect.width * p.x, y: rect.minY + rect.height * p.y)
                }
                if let p = bottomPos, let hsl = bottomHSL {
                    PickDot(hsl: hsl, text: "下")
                        .position(x: rect.minX + rect.width * p.x, y: rect.minY + rect.height * p.y)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func fittedRect(in container: CGSize) -> CGRect {
        let aspect = image.size.width / max(1, image.size.height)
        var w = container.width
        var h = w / aspect
        if h > container.height {
            h = container.height
            w = h * aspect
        }
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func boundaryDrag(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let f = (v.location.y - rect.minY) / max(1, rect.height)
                onBoundary?(min(0.7, max(0.35, f)))
            }
    }

    private func tapGesture(in rect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { v in
                let fx = (v.location.x - rect.minX) / max(1, rect.width)
                let fy = (v.location.y - rect.minY) / max(1, rect.height)
                onTap?(CGPoint(x: fx, y: fy))
            }
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

struct PickDot: View {
    let hsl: HSL
    let text: String

    var body: some View {
        let (r, g, b) = hsl2rgb(hsl.h, hsl.s, hsl.l)
        ZStack {
            Circle()
                .fill(Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .frame(width: 26, height: 26)
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hsl.l > 0.55 ? Color.black : Color.white)
        }
        .shadow(radius: 2)
    }
}

// MARK: - 结果卡
struct ResultCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                SwatchView(hsl: state.topHSL, label: "上衣")
                SwatchView(hsl: state.bottomHSL, label: "裤子")
            }

            chipRow(title: "取色",
                    items: [("上衣", state.pickMode == .top, { state.pickMode = .top }),
                            ("裤子", state.pickMode == .bottom, { state.pickMode = .bottom })])
            chipRow(title: "雷点",
                    items: [("⚡ 上衣", state.topBad, { state.topBad.toggle() }),
                            ("⚡ 裤子", state.bottomBad, { state.bottomBad.toggle() })])

            HStack(spacing: 14) {
                ScoreRing(value: state.score)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自评分 \(Int(state.score))").font(.subheadline.weight(.semibold))
                    Slider(value: $state.score, in: 0...100, step: 1)
                }
            }

            TextField("说两句（可选）", text: $state.comment, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("重新识别") { state.reCrop() }
                    .buttonStyle(.bordered)
                Button {
                    state.save()
                } label: {
                    Text(state.saveBusy ? "保存中…" : "保存记录")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSave || state.saveBusy)
            }
            if !state.saveState.isEmpty {
                Text(state.saveState)
                    .font(.footnote)
                    .foregroundStyle(state.saveState == "已保存" ? Color.green : Color.red)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chipRow(title: String,
                         items: [(String, Bool, () -> Void)]) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(0..<items.count, id: \.self) { i in
                Button {
                    items[i].2()
                } label: {
                    Text(items[i].0)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(items[i].1 ? Color.orange : Color(uiColor: .systemGray5))
                        .foregroundStyle(items[i].1 ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }
}

struct SwatchView: View {
    let hsl: HSL?
    let label: String

    private var swatchColor: Color {
        guard let h = hsl else { return Color(uiColor: .systemGray5) }
        let (r, g, b) = hsl2rgb(h.h, h.s, h.l)
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(swatchColor)
                if let h = hsl {
                    VStack(spacing: 2) {
                        Text(colorName(h)).font(.footnote.weight(.semibold))
                        Text(h.hex).font(.caption2.monospaced())
                    }
                    .foregroundStyle(h.l > 0.55 ? Color.black : Color.white)
                } else {
                    Text("未识别").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ScoreRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color(uiColor: .systemGray4), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, value / 100))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value))").font(.headline)
        }
        .frame(width: 64, height: 64)
        .animation(.linear(duration: 0.15), value: value)
    }
}

// MARK: - 相机
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
