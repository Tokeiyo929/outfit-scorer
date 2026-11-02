import SwiftUI

enum Stage {
    case pick      // 选拍照/相册
    case crop      // 裁剪
    case preview   // 识别前：拖分界线
    case result    // 识别后：点照片取色
}

enum PickSide {
    case top, bottom
}

@MainActor
final class AppState: ObservableObject {
    // 天气
    @Published var weather: WeatherNow?
    @Published var weatherBusy = false
    @Published var weatherError: String?
    @Published var manualCity = ""

    // 照片流程
    @Published var sourceImg: UIImage?
    @Published var loadedImg: UIImage?
    @Published var stage: Stage = .pick
    @Published var boundary: Double = 0.52
    @Published var topHSL: HSL?
    @Published var bottomHSL: HSL?
    @Published var topPos: CGPoint?
    @Published var bottomPos: CGPoint?
    @Published var pickMode: PickSide = .top
    @Published var topBad = false
    @Published var bottomBad = false
    @Published var score: Double = 70
    @Published var comment = ""

    // 保存
    @Published var saveBusy = false
    @Published var saveState: String = ""   // 空 / "已保存" / 失败原因

    // 历史
    @Published var records: [OutfitRecord] = []
    @Published var historyBusy = false
    @Published var historyError: String?

    private(set) var sample: PixelData?

    // MARK: - 天气（每次打开自动获取）
    func loadWeather(cityName: String? = nil) {
        guard !weatherBusy else { return }
        weatherBusy = true
        weatherError = nil
        Task {
            let outcome = await WeatherService.loadWeather(cityName: cityName)
            weatherBusy = false
            switch outcome {
            case .success(let w):
                weather = w
            case .failure(let msg):
                weatherError = msg
            }
        }
    }

    func queryManualCity() {
        let name = manualCity.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        loadWeather(cityName: name)
    }

    // MARK: - 照片流程
    func startNewPhoto(_ img: UIImage) {
        sourceImg = Analyzer.normalized(img)
        stage = .crop
    }

    func cropDone(_ cropped: UIImage) {
        loadedImg = cropped
        sample = Analyzer.pixelData(cropped, maxEdge: 260)
        boundary = 0.52
        resetResult()
        stage = .preview
    }

    func resetResult() {
        topHSL = nil
        bottomHSL = nil
        topPos = nil
        bottomPos = nil
        pickMode = .top
        topBad = false
        bottomBad = false
        score = 70
        comment = ""
        saveState = ""
    }

    func reCrop() {
        stage = .crop
    }

    func cancelPhoto() {
        sourceImg = nil
        loadedImg = nil
        sample = nil
        resetResult()
        stage = .pick
    }

    func analyze() {
        guard let img = loadedImg else { return }
        let result = Analyzer.analyzeImage(img, boundary: boundary)
        topHSL = result.top.hsl
        bottomHSL = result.bottom.hsl
        stage = .result
    }

    /// 照片上点一下取色：先给上衣，再给裤子，来回切换
    func pickColor(at point: CGPoint) {
        guard let sample else { return }
        guard let (hsl, pos) = Analyzer.pickColor(sample, fx: point.x, fy: point.y) else { return }
        if pickMode == .top {
            topHSL = hsl
            topPos = pos
            pickMode = .bottom
        } else {
            bottomHSL = hsl
            bottomPos = pos
            pickMode = .top
        }
    }

    var canSave: Bool { loadedImg != nil && topHSL != nil }

    func save() {
        guard canSave, !saveBusy else { return }
        saveBusy = true
        saveState = ""
        let payload = SaveRecordPayload(
            top: GarmentInfo(name: colorName(topHSL!), hex: topHSL!.hex, hsl: topHSL!.hslStr),
            bottom: GarmentInfo(
                name: bottomHSL != nil ? colorName(bottomHSL!) : "",
                hex: bottomHSL?.hex ?? "",
                hsl: bottomHSL?.hslStr ?? ""),
            boundary: boundary,
            score: Int(score.rounded()),
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            topBad: topBad,
            bottomBad: bottomBad)
        let photo = Analyzer.compressToDataUrl(loadedImg!)
        Task {
            do {
                _ = try await APIClient.save(photo: photo, record: payload)
                saveBusy = false
                saveState = "已保存"
                loadHistory()
            } catch {
                saveBusy = false
                saveState = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 历史
    func loadHistory(force: Bool = false) {
        guard !historyBusy else { return }
        if !force && !records.isEmpty { return }
        historyBusy = true
        historyError = nil
        Task {
            do {
                let resp = try await APIClient.list(limit: 30)
                records = resp.records
                historyBusy = false
            } catch {
                historyBusy = false
                historyError = "记录加载失败，检查网络后重试"
            }
        }
    }

    func deleteRecord(_ rec: OutfitRecord) {
        Task {
            do {
                try await APIClient.delete(id: rec.id)
                records.removeAll { $0.id == rec.id }
            } catch {}
        }
    }
}

@main
struct OutfitScorerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .tabItem { Label("打分", systemImage: "camera.viewfinder") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            }
            .environmentObject(state)
            .tint(.orange)
        }
    }
}
