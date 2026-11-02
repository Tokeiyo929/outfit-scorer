import Foundation
import CoreLocation

struct WeatherPos {
    var lat: Double
    var lon: Double
    var city: String
}

struct WeatherNow {
    var icon: String
    var text: String
    var city: String
    var temp: Int
    var feels: Int
    var humidity: Int
    var wind: Int
    var hint: String
}

/// 单次定位：授权弹窗 + requestLocation，8 秒超时兜底走 IP 定位
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<WeatherPos?, Never>?
    private var done = false

    static func request(timeout: TimeInterval) async -> WeatherPos? {
        await withCheckedContinuation { cont in
            let locator = OneShotLocator()
            locator.cont = cont
            locator.mgr.delegate = locator
            locator.mgr.desiredAccuracy = kCLLocationAccuracyKilometer
            locator.mgr.requestWhenInUseAuthorization()
            locator.mgr.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                locator.finish(nil)
            }
        }
    }

    private func finish(_ pos: WeatherPos?) {
        DispatchQueue.main.async { [self] in
            guard !done else { return }
            done = true
            cont?.resume(returning: pos)
            cont = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return finish(nil) }
        finish(WeatherPos(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, city: ""))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(nil) }

    /* 授权刚批下来第一次 requestLocation 会先报错，状态变了再补一次 */
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if (s == .authorizedWhenInUse || s == .authorizedAlways) && !done {
            manager.requestLocation()
        }
    }
}

enum WeatherService {
    static func fetchJson(_ url: String, timeout: TimeInterval) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    /* 定位链：系统 GPS → IP 定位兜底 */
    static func ipLocate() async -> WeatherPos? {
        guard let d = try? await fetchJson("https://ipapi.co/json/", timeout: 6),
              let lat = d["latitude"] as? Double, let lon = d["longitude"] as? Double else { return nil }
        let city = (d["city"] as? String) ?? (d["region"] as? String) ?? ""
        return WeatherPos(lat: lat, lon: lon, city: city)
    }

    static func geoLocate() async -> WeatherPos? {
        if let got = await OneShotLocator.request(timeout: 8) { return got }
        return await ipLocate()
    }

    static func cityToPos(_ name: String) async throws -> WeatherPos {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let d = try await fetchJson("https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=zh", timeout: 8)
        guard let results = d["results"] as? [[String: Any]], let r = results.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
            throw NSError(domain: "weather", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到城市"])
        }
        return WeatherPos(lat: lat, lon: lon, city: (r["name"] as? String) ?? name)
    }

    static let wmoText: [Int: String] = [
        0: "☀️ 晴", 1: "🌤 基本晴", 2: "⛅ 多云", 3: "☁️ 阴",
        45: "🌫 有雾", 48: "🌫 冻雾",
        51: "🌦 毛毛雨", 53: "🌦 毛毛雨", 55: "🌧 密毛毛雨", 56: "🌧 冻毛毛雨", 57: "🌧 冻毛毛雨",
        61: "🌦 小雨", 63: "🌧 中雨", 65: "🌧 大雨", 66: "🌧 冻雨", 67: "🌧 冻雨",
        71: "🌨 小雪", 73: "🌨 中雪", 75: "❄️ 大雪", 77: "🌨 米雪",
        80: "🌦 阵雨", 81: "🌧 强阵雨", 82: "⛈ 暴雨", 85: "🌨 阵雪", 86: "❄️ 强阵雪",
        95: "⛈ 雷阵雨", 96: "⛈ 雷雨冰雹", 99: "⛈ 雷雨冰雹",
    ]

    static func wmo(_ code: Int) -> (String, String) {
        let s = wmoText[code] ?? "🌤 未知"
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let icon = String(parts[0])
        let text = parts.count > 1 ? String(parts[1]) : ""
        return (icon, text)
    }

    static func dressHint(_ temp: Double, _ code: Int) -> String {
        var h = temp < 0 ? "严寒：厚羽绒服、保暖内搭"
            : temp < 8 ? "冷：大衣或厚外套"
            : temp < 15 ? "凉：夹克、薄外套"
            : temp < 22 ? "舒适：长袖或薄外套"
            : temp < 28 ? "暖：短袖或薄长袖"
            : "热：透气短袖"
        if (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95 { h += " · 有雨记得带伞" }
        else if (code >= 71 && code <= 77) || code == 85 || code == 86 { h += " · 有雪注意防滑" }
        return h
    }

    enum WeatherOutcome {
        case success(WeatherNow)
        case failure(String)
    }

    /// 每次打开自动获取：手动城市优先，否则 GPS→IP
    static func loadWeather(cityName: String?) async -> WeatherOutcome {
        let isManual = !(cityName ?? "").isEmpty
        do {
            let pos: WeatherPos
            if let name = cityName, !name.isEmpty {
                pos = try await cityToPos(name)
            } else {
                guard let p = await geoLocate() else {
                    throw NSError(domain: "weather", code: 2, userInfo: [NSLocalizedDescriptionKey: "定位失败"])
                }
                pos = p
            }
            var city = pos.city
            if city.isEmpty {
                if let r = try? await fetchJson("https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=\(pos.lat)&longitude=\(pos.lon)&localityLanguage=zh", timeout: 6) {
                    city = (r["city"] as? String) ?? (r["locality"] as? String) ?? (r["principalSubdivision"] as? String) ?? ""
                }
            }
            let w = try await fetchJson("https://api.open-meteo.com/v1/forecast?latitude=\(pos.lat)&longitude=\(pos.lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=auto", timeout: 8)
            guard let cur = w["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double,
                  let code = cur["weather_code"] as? Int else {
                throw NSError(domain: "weather", code: 3, userInfo: [NSLocalizedDescriptionKey: "天气数据异常"])
            }
            let feels = (cur["apparent_temperature"] as? Double) ?? temp
            let hum = (cur["relative_humidity_2m"] as? Double).map { Int($0.rounded()) } ?? 0
            let wind = (cur["wind_speed_10m"] as? Double) ?? 0
            let (icon, text) = wmo(code)
            return .success(WeatherNow(
                icon: icon, text: text, city: city,
                temp: Int(temp.rounded()), feels: Int(feels.rounded()),
                humidity: hum, wind: Int(wind.rounded()),
                hint: dressHint(feels, code)))
        } catch {
            let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
            return .failure(msg ?? (isManual ? "找不到城市，换个名字试试" : "定位失败，手动输城市查询"))
        }
    }
}
