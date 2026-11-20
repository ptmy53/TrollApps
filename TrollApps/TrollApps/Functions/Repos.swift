//
//  Repos.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-15.
//

import Foundation
import Combine

func reposEncode(reposUrl: [String]) -> String {
    let repoUrlString = reposUrl.map { ($0) }.joined(separator: ",")
    
    if let data = repoUrlString.data(using: .utf8) {
        return "repo[" + data.base64EncodedString() + "]"
    }
    
    return ""
}

func compareVersions(_ version1: String, _ version2: String) -> Bool {
    let components1 = version1.components(separatedBy: CharacterSet(charactersIn: "."))
    let components2 = version2.components(separatedBy: CharacterSet(charactersIn: "."))
    
    for (component1, component2) in zip(components1, components2) {
        if let number1 = Int(component1), let number2 = Int(component2) {
            if number1 != number2 {
                return number1 > number2
            }
        } else {
            if component1 < component2 {
                return false
            } else if component1 > component2 {
                return true
            }
        }
    }
    
    return components1.count >= components2.count
}

// Cihazin su an calistigi iOS surumunu "major.minor.patch" biciminde dondurur.
func currentOSVersionString() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

// Iki surum dizesini ayni bilesen sayisina getirir (eksikleri 0 ile doldurur),
// boylece compareVersions'in "esit uzunluk" varsayimi bozulmaz.
private func paddedVersion(_ version: String, componentCount: Int) -> String {
    var components = version.components(separatedBy: CharacterSet(charactersIn: "."))
    while components.count < componentCount {
        components.append("0")
    }
    return components.joined(separator: ".")
}

// Cihazin iOS surumu verilen min/max araligina uyuyor mu?
// nil veya bos degerler "kisitlama yok" olarak kabul edilir.
func isVersionCompatible(minOSVersion: String?, maxOSVersion: String?, deviceVersion: String = currentOSVersionString()) -> Bool {
    let minVersion = (minOSVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let maxVersion = (maxOSVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let device = deviceVersion.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !device.isEmpty else { return true }

    let componentCount = [minVersion, maxVersion, device].reduce(3) { max($0, $1.components(separatedBy: CharacterSet(charactersIn: ".")).count) }

    // Cihaz surumu min'den kucuk olmamali.
    if !minVersion.isEmpty {
        if !compareVersions(paddedVersion(device, componentCount: componentCount), paddedVersion(minVersion, componentCount: componentCount)) {
            return false
        }
    }

    // Max varsa cihaz surumu max'i asmamali.
    if !maxVersion.isEmpty {
        if !compareVersions(paddedVersion(maxVersion, componentCount: componentCount), paddedVersion(device, componentCount: componentCount)) {
            return false
        }
    }

    return true
}

// Bos/nil sinir "kisitlama yok" demektir.
private func hasOSBound(_ value: String?) -> Bool {
    return !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// Bir surumun iOS sinirlarinin cozulmus halini dondurur. Oncelik sirasi:
// 1) surumun kendi sinirlari, 2) versions icinde ayni "version" dizesine sahip ve
// en az bir dolu siniri olan ilk kayit (repolarin uygulama duzeyinde ekledigi kopya),
// 3) uygulama duzeyindeki sinirlar, 4) hicbir kisitlama yok.
func resolvedOSBounds(for version: Version, in versions: [Version]?, appMinOSVersion: String?, appMaxOSVersion: String?) -> (minOSVersion: String?, maxOSVersion: String?) {
    if hasOSBound(version.minOSVersion) || hasOSBound(version.maxOSVersion) {
        return (version.minOSVersion, version.maxOSVersion)
    }

    if let twin = versions?.first(where: { $0.version == version.version && (hasOSBound($0.minOSVersion) || hasOSBound($0.maxOSVersion)) }) {
        return (twin.minOSVersion, twin.maxOSVersion)
    }

    if hasOSBound(appMinOSVersion) || hasOSBound(appMaxOSVersion) {
        return (appMinOSVersion, appMaxOSVersion)
    }

    return (nil, nil)
}

// Tek bir surumun, cozulmus sinirlarina gore cihazin iOS surumuyle uyumlu olup olmadigi.
func isVersionCompatible(version: Version, in versions: [Version]?, appMinOSVersion: String?, appMaxOSVersion: String?, deviceVersion: String = currentOSVersionString()) -> Bool {
    let bounds = resolvedOSBounds(for: version, in: versions, appMinOSVersion: appMinOSVersion, appMaxOSVersion: appMaxOSVersion)
    return isVersionCompatible(minOSVersion: bounds.minOSVersion, maxOSVersion: bounds.maxOSVersion, deviceVersion: deviceVersion)
}

// Yeniden eskiye sirali surum listesinde (dizi en yeni once) cihazin iOS surumuyle
// uyumlu ilk (yani en yeni) surumun indeksini dondurur. Uyumlu surum yoksa nil.
// Uygulama duzeyindeki sinirlar, kendi siniri olmayan surumler icin yedektir.
func compatibleVersionIndex(_ versions: [Version]?, appMinOSVersion: String? = nil, appMaxOSVersion: String? = nil, deviceVersion: String = currentOSVersionString()) -> Int? {
    guard let versions = versions else { return nil }

    for (index, version) in versions.enumerated() {
        if isVersionCompatible(version: version, in: versions, appMinOSVersion: appMinOSVersion, appMaxOSVersion: appMaxOSVersion, deviceVersion: deviceVersion) {
            return index
        }
    }

    return nil
}

// App Store'un minimum iOS degeri, repo o surum icin hicbir sinir bildirmediginde ve
// surum listenin en yenisi seciliyken dikkate alinir. Repo bir sinir bildiriyorsa
// (ya da uyumlu daha eski bir surume dusulduyse) repo verisi kesindir.
func shouldCheckStoreCompatibility(for version: Version, in versions: [Version]?, selectedIndex: Int, appMinOSVersion: String?, appMaxOSVersion: String?) -> Bool {
    guard selectedIndex == 0 else { return false }

    let bounds = resolvedOSBounds(for: version, in: versions, appMinOSVersion: appMinOSVersion, appMaxOSVersion: appMaxOSVersion)
    return !hasOSBound(bounds.minOSVersion) && !hasOSBound(bounds.maxOSVersion)
}

// MARK: - Gizlenen uygulamalar (isim + bundle id)
// Kayitlar isim ve bundle id ciftini birlikte tutar. Guncelleme uygulamanin
// adini degistirse bile bundle id sayesinde gizli kalir; ayni isme sahip tum
// kopyalar birlikte gizlenir. Eski surumun yalnizca isim tutan
// "hiddenAppNames" kayitlari ilk acilista otomatik olarak tasinir.
struct HiddenAppEntry: Codable, Equatable {
    let name: String
    let bundleId: String?
}

final class HiddenAppsManager: ObservableObject {
    static let shared = HiddenAppsManager()

    private static let entriesKey = "hiddenAppEntries"
    private static let legacyNamesKey = "hiddenAppNames"

    @Published private(set) var entries: [HiddenAppEntry]

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: HiddenAppsManager.entriesKey),
           let decoded = try? JSONDecoder().decode([HiddenAppEntry].self, from: data) {
            entries = decoded
        } else {
            // Eski surumden (yalnizca isim) tasima.
            let legacy = defaults.stringArray(forKey: HiddenAppsManager.legacyNamesKey) ?? []
            entries = legacy.map { HiddenAppEntry(name: $0, bundleId: nil) }
            if !legacy.isEmpty {
                persist()
            }
        }
    }

    // Gizli ekraninda gosterilecek tekil isimler (kayit sirasi korunur).
    var names: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries where !seen.contains(entry.name) {
            seen.insert(entry.name)
            result.append(entry.name)
        }
        return result
    }

    // Isim eslesirse veya bundle id eslesirse uygulama gizlidir.
    func isHidden(_ name: String, bundleId: String? = nil) -> Bool {
        let id = (bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.contains { entry in
            if entry.name == name { return true }
            if !id.isEmpty, let stored = entry.bundleId, stored == id { return true }
            return false
        }
    }

    func hide(name: String, bundleId: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = (bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Ayni isim zaten gizliyse yalnizca bundle id kaydini tamamla; ayni
        // isimli baska kopyalar icin ek kayit tut.
        if entries.contains(where: { $0.name == trimmed }) {
            if !id.isEmpty, !entries.contains(where: { $0.name == trimmed && $0.bundleId == id }) {
                entries.append(HiddenAppEntry(name: trimmed, bundleId: id))
                persist()
            }
            return
        }

        entries.append(HiddenAppEntry(name: trimmed, bundleId: id.isEmpty ? nil : id))
        persist()
    }

    // Repo iceriginden gizli isimlerin bundle id'lerini ogrenir. Boylece
    // uygulama guncellemeyle adini degistirse bile gizli kalir. Eski surumden
    // tasinan isim-only kayitlar ilk taramada tamamlanir.
    func learnBundleIds(from apps: [Application]) {
        let missingNames = Set(entries.filter { $0.bundleId == nil }.map { $0.name })
        guard !missingNames.isEmpty else { return }

        var changed = false
        for name in missingNames {
            for app in apps where app.name == name {
                guard let id = app.bundleIdentifier, !id.isEmpty else { continue }
                if entries.contains(where: { $0.name == name && $0.bundleId == id }) { continue }

                if let index = entries.firstIndex(where: { $0.name == name && $0.bundleId == nil }) {
                    entries[index] = HiddenAppEntry(name: name, bundleId: id)
                } else {
                    entries.append(HiddenAppEntry(name: name, bundleId: id))
                }
                changed = true
            }
        }

        if changed {
            persist()
        }
    }

    // Bu isimdeki tum kayitlari (ve varsa bundle id kopyalarini) geri getirir.
    func unhide(name: String) {
        let before = entries.count
        entries.removeAll { $0.name == name }
        if entries.count != before {
            persist()
        }
    }

    func unhideAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: HiddenAppsManager.entriesKey)
        }
        // Eski anahtar da guncel tutulur (geriye uyumluluk).
        UserDefaults.standard.set(names, forKey: HiddenAppsManager.legacyNamesKey)
    }
}

// MARK: - Yenilikler akisi (olay kaydi)
// Her tarama, paketlerin surumunu onceki taramanin surumuyle karsilastirir.
// Surumu degisenler "guncellendi", ilk kez gorulenler "eklendi" olayi olarak
// kaydedilir. Ilk tarama yalnizca baz (baseline) olusturur; boylece ilk
// kurulumda butun repolar "yeni" gibi listelenmez. Olayin zaman damgasi
// tarama anidir; Yenilikler ekrani bu damgaya gore saat gruplari olusturur
// (en yeni grup en ustte, onceki gruplar altinda).
struct NewsEvent: Codable, Identifiable {
    let bundleId: String
    let version: String
    let name: String
    let repoName: String
    // Olayin bulundugu taramanin zamani. Ayni taramadaki olaylar ayni degeri
    // tasir; ekran bunlari tek bir saat grubunda toplar.
    let scanEpoch: Double
    // "updated" veya "added".
    let kind: String

    var id: String { bundleId + "|" + String(scanEpoch) + "|" + version }
    var isUpdate: Bool { kind == "updated" }
}

final class NewAppsManager: ObservableObject {
    static let shared = NewAppsManager()

    private static let versionsKey = "newAppVersions"
    private static let eventsKey = "newsEvents"
    private static let lastScanKey = "newsLastScan"
    private static let maxEvents = 500
    private static let maxVersions = 8000

    // Surum karsilastirmasi icin son gorulen surumler (bundle id -> surum).
    private var versions: [String: String] = [:]

    // Taranan degisikliklerin kalici kaydi; ekran bunlari gruplar.
    @Published private(set) var events: [NewsEvent]

    // Son taramanin zamani. Ayni anda yeniden tarama yapilirken bekleme
    // gostergesinin ne zaman kapanacagini anlamak icin kullanilir.
    @Published private(set) var lastScan: Double

    private init() {
        let defaults = UserDefaults.standard
        versions = defaults.dictionary(forKey: NewAppsManager.versionsKey) as? [String: String] ?? [:]
        lastScan = defaults.double(forKey: NewAppsManager.lastScanKey)

        if let data = defaults.data(forKey: NewAppsManager.eventsKey),
           let decoded = try? JSONDecoder().decode([NewsEvent].self, from: data) {
            events = decoded
        } else {
            events = []
        }
    }

    // Repolari tarar. Ilk tarama yalnizca baz olusturur; sonraki taramalarda
    // surumu degisen her paket bir "guncellendi", ilk kez gorulen her paket
    // bir "eklendi" olayi uretir. Degisiklik yoksa olay yazilmaz.
    func scan(_ repos: [RepoMemory]) {
        let now = Date().timeIntervalSince1970
        // Baz henuz kurulmadiysa (ilk tarama) olay uretme.
        let isBaseline = versions.isEmpty

        var nextVersions = versions
        var nextEvents = events
        var versionsChanged = false

        // Ayni paket birden fazla depoda bulunabilir. Paket basina tek kayit
        // tutulur (ilk tanim esastir); aksi halde depolardaki farkli surumler
        // her taramada sahte "guncellendi" olayi uretirdi.
        var discovered: [String: (name: String, repoName: String, version: String)] = [:]
        for repo in repos {
            let repoName = repo.data.name ?? "UNNAMED_REPO"
            for app in repo.data.apps {
                guard let id = app.bundleIdentifier, !id.isEmpty else { continue }
                let version = app.version ?? ""
                if let existing = discovered[id] {
                    if existing.version.isEmpty && !version.isEmpty {
                        discovered[id] = (name: app.name, repoName: repoName, version: version)
                    }
                } else {
                    discovered[id] = (name: app.name, repoName: repoName, version: version)
                }
            }
        }

        let seenIds = Set(discovered.keys)

        for (id, info) in discovered {
            let version = info.version

            if let previous = nextVersions[id] {
                // Surum ayni: yeni bir sey yok.
                guard !version.isEmpty, version != previous else { continue }
                nextVersions[id] = version
                versionsChanged = true
                if !isBaseline {
                    nextEvents.append(NewsEvent(bundleId: id,
                                                version: version,
                                                name: info.name,
                                                repoName: info.repoName,
                                                scanEpoch: now,
                                                kind: "updated"))
                }
            } else {
                // Bu paket ilk kez goruluyor.
                nextVersions[id] = version
                versionsChanged = true
                if !isBaseline {
                    nextEvents.append(NewsEvent(bundleId: id,
                                                version: version,
                                                name: info.name,
                                                repoName: info.repoName,
                                                scanEpoch: now,
                                                kind: "added"))
                }
            }
        }

        lastScan = now
        UserDefaults.standard.set(now, forKey: NewAppsManager.lastScanKey)

        // Surum sozlugu asiri buyumesin: son taramada gorulenler oncelikli.
        if nextVersions.count > NewAppsManager.maxVersions {
            nextVersions = nextVersions.filter { seenIds.contains($0.key) }
        }

        if versionsChanged {
            versions = nextVersions
            UserDefaults.standard.set(versions, forKey: NewAppsManager.versionsKey)
        }

        guard nextEvents.count != events.count else { return }

        // Olay gecmisi buyumesin: en yeni kayitlari tut.
        if nextEvents.count > NewAppsManager.maxEvents {
            nextEvents = Array(nextEvents.suffix(NewAppsManager.maxEvents))
        }

        events = nextEvents
        if let data = try? JSONEncoder().encode(nextEvents) {
            UserDefaults.standard.set(data, forKey: NewAppsManager.eventsKey)
        }
    }
}
