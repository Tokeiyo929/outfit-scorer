import SwiftUI

/// 裁剪：拖动调位置、滑块放大缩小，确定后按可见交集输出（最长边 1600）
struct CropView: View {
    @EnvironmentObject private var state: AppState
    @State private var boxW: Double = 0
    @State private var boxH: Double = 0
    @State private var contain: Double = 1
    @State private var cover: Double = 1
    @State private var scale: Double = 1
    @State private var ox: Double = 0
    @State private var oy: Double = 0
    @State private var slider: Double = 0
    @State private var lastDrag: CGPoint?

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let srcW = state.sourceImg?.size.width ?? 1
                let srcH = state.sourceImg?.size.height ?? 1
                let drawnW = srcW * scale
                let drawnH = srcH * scale
                ZStack {
                    Color(red: 0.11, green: 0.106, blue: 0.098)
                    if let img = state.sourceImg {
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: drawnW, height: drawnH)
                            .position(x: ox + drawnW / 2, y: oy + drawnH / 2)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onAppear { initCropView(width: geo.size.width, height: geo.size.height, srcW: srcW, srcH: srcH) }
            }
            .aspectRatio(1 / 1.25, contentMode: .fit)

            HStack {
                Image(systemName: "magnifyingglass")
                Slider(value: Binding(get: { slider }, set: { zoom(to: $0) }), in: 0...100)
            }

            HStack(spacing: 12) {
                Button("重选照片") { state.cancelPhoto() }
                    .buttonStyle(.bordered)
                Button("确定，去识别") { done() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if let last = lastDrag {
                    ox += v.location.x - last.x
                    oy += v.location.y - last.y
                    clampPan()
                }
                lastDrag = v.location
            }
            .onEnded { _ in lastDrag = nil }
    }

    private func initCropView(width: Double, height: Double, srcW: Double, srcH: Double) {
        guard boxW == 0, let img = state.sourceImg else { return }
        boxW = width
        boxH = height
        contain = min(width / srcW, height / srcH)
        cover = max(width / srcW, height / srcH)
        scale = contain
        ox = (width - img.size.width * contain) / 2
        oy = (height - img.size.height * contain) / 2
        slider = 0
    }

    private func zoom(to v: Double) {
        guard boxW > 0 else { return }
        slider = v
        let minS = contain, maxS = cover * 4
        let old = scale
        let cxPt = (boxW / 2 - ox) / old
        let cyPt = (boxH / 2 - oy) / old
        scale = minS * pow(maxS / minS, v / 100)
        ox = boxW / 2 - cxPt * scale
        oy = boxH / 2 - cyPt * scale
        clampPan()
    }

    private func clampPan() {
        let drawnW = (state.sourceImg?.size.width ?? 0) * scale
        let drawnH = (state.sourceImg?.size.height ?? 0) * scale
        ox = drawnW <= boxW ? (boxW - drawnW) / 2 : min(0, max(boxW - drawnW, ox))
        oy = drawnH <= boxH ? (boxH - drawnH) / 2 : min(0, max(boxH - drawnH, oy))
    }

    private func done() {
        guard let img = state.sourceImg, boxW > 0 else { return }
        state.cropDone(Analyzer.cropOutput(
            source: img, viewW: boxW, viewH: boxH, scale: scale, ox: ox, oy: oy))
    }
}
