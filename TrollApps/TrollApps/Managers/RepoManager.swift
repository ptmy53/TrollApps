//
//  RepoManager.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-02.
//

import SwiftUI

// https://medium.com/swlh/decoding-a-json-field-that-could-be-string-or-double-with-swift-f6ea6a2babf8
enum StringOrDouble: Decodable, Encodable, Equatable {
    case string(String)
    case double(Double)

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            if let double = try? container.decode(Double.self) {
                self = .double(double)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                throw Error.couldNotFindStringOrDouble
            }
        } catch {
            throw Error.couldNotFindStringOrDouble
        }
    }

    enum Error: Swift.Error {
        case couldNotFindStringOrDouble
    }
    
    func toString() -> String {
        switch self {
        case .string(let stringValue):
            return stringValue
        case .double(let doubleValue):
            return String(doubleValue)
        }
    }
}

struct Repo: Decodable, Equatable, Hashable {
    var name: String?
    var website: String?
    var iconURL: String?
    var headerURL: String?
    var featuredApps: [String]?
    var tintColor: String?
    var apps: [Application]
    var news: [News]?

    enum CodingKeys: String, CodingKey {
        case name, iconURL, headerURL, featuredApps, tintColor, apps, news
    }
}
struct RepoMemory: Identifiable {
    let id = UUID()
    var url: String
    var data: Repo
}

struct BadRepoMemory: Identifiable {
    let id = UUID()
    var url: String
}

struct ErrorMemory: Identifiable {
    let id = UUID()
    var url: String
    var data: Repo
}

struct Version: Codable, Equatable {
    var absoluteVersion: String?
    var version: String
    var date: String
    var localizedDescription: String?
    var downloadURL: String
    var size: StringOrDouble?
    var minOSVersion: String?
    var maxOSVersion: String?
}

struct News: Codable, Hashable {
    var title : String?
    var caption: String?
    var date: String?
    var tintColor: String?
    var imageURL: String?
    var url: String?
    var appID: String?
}

struct Application: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subtitle: String?
    var bundleIdentifier: String?
    var version: String?
    var versionDate: String?
    var size: StringOrDouble?
    var downloadURL: String?
    var developerName: String?
    var localizedDescription: String?
    var tintColor: String?
    var iconURL: String
    var screenshotURLs: [String]?
    var versions: [Version]?
    var minOSVersion: String?
    var maxOSVersion: String?

    enum CodingKeys: String, CodingKey {
        case name, subtitle, bundleIdentifier, version, versionDate, size, downloadURL, developerName, localizedDescription, tintColor, iconURL, screenshotURLs, versions, minOSVersion, maxOSVersion
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

let decoder = JSONDecoder()

class RepositoryManager: ObservableObject {
    @AppStorage("repos") var RepoList: [String] = [
        "https://raw.githubusercontent.com/TheResonanceTeam/.default-sources/main/haxi0_2.0.json",
        "https://raw.githubusercontent.com/TheResonanceTeam/.default-sources/main/BonnieRepo_2.0.json",
        "https://raw.githubusercontent.com/TheResonanceTeam/.default-sources/main/ResonanceTeamRepo.json"
    ]
    @Published var ReposData: [RepoMemory] = []
    @Published var BadRepos: [BadRepoMemory] = []
    @Published var InstalledApps = GetApps()
    
    @Published var hasFetchedRepos: Bool = false
    @Published var hasFinishedFetchingRepos: Bool = false
    
    @Published var isInstallingApp = false
    @Published var isDownloadingApp = false
    
    // bundleID -> App Store'daki minimum iOS surumu (bos deger: App Store'da bulunamadi).
    @Published var storeMinimumOS: [String: String] = [:]
    
    private let storeCacheKey = "storeMinimumOSCache"
    private let storeCacheTTL: TimeInterval = 24 * 60 * 60
    private var storeLookupsInFlight: Set<String> = []
    
    
    func fetchRepos() {
        self.hasFetchedRepos = true
        fetchRepos(RepoList) { fetchedResults, errors in
            self.ReposData = fetchedResults
            self.BadRepos = errors
            
            // Yenilikler akisi: repoda ilk kez gorulen paketleri kaydet.
            NewAppsManager.shared.scan(fetchedResults)
            
            let bundleIDs = fetchedResults.flatMap { $0.data.apps }.compactMap { $0.bundleIdentifier }.filter { self.IsAppInstalled($0) }
            self.refreshStoreMinimumOS(for: bundleIDs)
            
            self.hasFinishedFetchingRepos = true
        }
    }
    
    // Kurulu uygulamalarin App Store'daki minimum iOS surumunu toplu halde tazeler.
    // Onbellekte taze kaydi olanlar tekrar sorulmaz; ag hatasi onbellege yazilmaz.
    func refreshStoreMinimumOS(for bundleIDs: [String]) {
        var pending: [String] = []
        var seen: Set<String> = []
        let cache = loadStoreCache()
        
        for bundleID in bundleIDs {
            let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            
            if isStoreCacheEntryStale(cache[id]) {
                pending.append(id)
            } else {
                let cachedMinOS = cachedStoreMinimumOS(cache[id])
                if !cachedMinOS.isEmpty {
                    DispatchQueue.main.async {
                        self.storeMinimumOS[id] = cachedMinOS
                    }
                }
            }
        }
        
        // Ayni anda calisan cagrilar ayni kimligi ikinci kez sorgulamasin.
        let idsToFetch = pending.filter { !self.storeLookupsInFlight.contains($0) }
        guard !idsToFetch.isEmpty else { return }
        self.storeLookupsInFlight.formUnion(idsToFetch)
        
        let region: String
        if #available(iOS 16.0, *) {
            region = Locale.current.region?.identifier ?? "US"
        } else {
            region = Locale.current.regionCode ?? "US"
        }
        
        // Apple lookup ucnoktasi tek istekte sinirli sayida kimlik kabul ediyor: 20'lik parcalar.
        for chunkStart in stride(from: 0, to: idsToFetch.count, by: 20) {
            let chunk = Array(idsToFetch[chunkStart..<min(chunkStart + 20, idsToFetch.count)])
            let bundleIdParameter = chunk.joined(separator: ",")
            
            guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdParameter)&country=\(region.lowercased())&entity=software") else {
                self.storeLookupsInFlight.subtract(chunk)
                continue
            }
            
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard error == nil, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    // Ag/ayristirma hatasi: onbellege yazma, sonraki denemede tekrar sor.
                    DispatchQueue.main.async {
                        self.storeLookupsInFlight.subtract(chunk)
                    }
                    return
                }
                
                var found: [String: String] = [:]
                for result in results {
                    if let bundleID = result["bundleId"] as? String,
                       let minimumOSVersion = result["minimumOsVersion"] as? String {
                        found[bundleID] = minimumOSVersion
                    }
                }
                
                DispatchQueue.main.async {
                    var updatedCache = self.loadStoreCache()
                    let epoch = Int(Date().timeIntervalSince1970)
                    
                    for bundleID in chunk {
                        let minimumOSVersion = found[bundleID] ?? ""
                        updatedCache[bundleID] = "\(minimumOSVersion)|\(epoch)"
                        
                        if !minimumOSVersion.isEmpty {
                            self.storeMinimumOS[bundleID] = minimumOSVersion
                        }
                    }
                    
                    self.saveStoreCache(updatedCache)
                    self.storeLookupsInFlight.subtract(chunk)
                }
            }.resume()
        }
    }
    
    // UserDefaults'taki "minOS|epoch" bicimli onbellegi okur.
    private func loadStoreCache() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: storeCacheKey) as? [String: String] ?? [:]
    }
    
    private func saveStoreCache(_ cache: [String: String]) {
        UserDefaults.standard.set(cache, forKey: storeCacheKey)
    }
    
    // Onbellek kaydindan minimum iOS surumunu cikarir (bos dize: App Store'da yok).
    private func cachedStoreMinimumOS(_ entry: String?) -> String {
        guard let entry = entry else { return "" }
        return entry.components(separatedBy: "|").first ?? ""
    }
    
    // Kaydin yasi TTL'i gectiyse (veya kayit bozuksa) tazeleme gerekir.
    private func isStoreCacheEntryStale(_ entry: String?) -> Bool {
        guard let entry = entry,
              let epochString = entry.components(separatedBy: "|").dropFirst().first,
              let epoch = Double(epochString) else { return true }
        return Date().timeIntervalSince1970 - epoch > storeCacheTTL
    }
    
    func addRepo(_ repoURL: String, alertManager: AlertManager, completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()
        
        if !RepoList.contains(repoURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            dispatchGroup.enter()
            
            let regex = try! NSRegularExpression(pattern: #"^repo\[[A-Za-z0-9+/]+={0,2}\]$"#, options: .caseInsensitive)
            
            let range = NSRange(location: 0, length: repoURL.utf16.count)
            let isMatch = regex.firstMatch(in: repoURL, options: [], range: range) != nil
            
            if isMatch {
                if let base64String = repoURL.components(separatedBy: "[").last?.components(separatedBy: "]").first,
                   let data = Data(base64Encoded: base64String),
                   let decodedString = String(data: data, encoding: .utf8) {
                    var urlArray = decodedString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    urlArray = urlArray.filter { !self.RepoList.contains($0) }
                    
                    fetchRepos(urlArray) { fetchedResults, errors in
                        self.ReposData = self.ReposData + fetchedResults
                        self.BadRepos = self.BadRepos + errors
                        self.RepoList = self.RepoList + urlArray
                        
                        dispatchGroup.leave()
                    }
                } else {
                    alertManager.showAlert(
                        title: Text(LocalizedStringKey("ERROR_DECODING_BASE64_STRING")),
                        body: Text(LocalizedStringKey("PLEASE_VERIFY_VALID_REPO_STRING"))
                    )
                }
            } else {
                fetchRepos([repoURL]) { fetchedResults, errors in
                    self.ReposData = self.ReposData + fetchedResults
                    self.BadRepos = self.BadRepos + errors
                    self.RepoList = self.RepoList + [repoURL.trimmingCharacters(in: .whitespacesAndNewlines)]
                    
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                completion()
            }
        } else {
            completion()
        }
    }
    
    func removeRepos(repoIds: Set<UUID>) {
        for repoId in repoIds {
            if let reposIndex = ReposData.firstIndex(where: { $0.id == repoId }) {
                if let repoListIndex = RepoList.firstIndex(of: ReposData[reposIndex].url) {
                    RepoList.remove(at: repoListIndex)
                }
                ReposData.remove(at: reposIndex)
            }
        }
    }
    
    func removeBadRepos(repoIds: Set<UUID>) {
        for repoId in repoIds {
            if let badReposIndex = BadRepos.firstIndex(where: { $0.id == repoId }) {
                if let repoListIndex = RepoList.firstIndex(of: BadRepos[badReposIndex].url) {
                    RepoList.remove(at: repoListIndex)
                }
                BadRepos.remove(at: badReposIndex)
            }
        }
    }
    
    func fetchRepo(_ repoURL: String, completion: @escaping (Result<Repo, Error>) -> Void) {
        
        var modifiedRepoURL = repoURL
        
        if !repoURL.contains("://") {
            modifiedRepoURL = "https://\(repoURL)"
        }
        
        guard let url = URL(string: modifiedRepoURL) else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.unknown)))
                return
            }
            
            do {
                var decodedRepo = try decoder.decode(Repo.self, from: data)
                
                for index in decodedRepo.apps.indices {
                    let app = decodedRepo.apps[index]
                    
                    if app.downloadURL != nil {
                        let builtVersion = Version(
                            version: app.version ?? "",
                            date: app.versionDate ?? "",
                            localizedDescription: app.localizedDescription ?? "",
                            downloadURL: app.downloadURL ?? "",
                            size: app.size ?? nil
                        )
                        
                        if app.versions == nil {
                            decodedRepo.apps[index].versions = []
                        }
                        
                        decodedRepo.apps[index].versions?.insert(builtVersion, at: 0)
                    }
                }
                
                completion(.success(decodedRepo))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchRepo(_ repoURL: String, completion: @escaping (Repo?) -> Void) {
        fetchRepo(repoURL) { result in
            switch result {
            case .success(let repo):
                completion(repo)
            case .failure(let error):
                print("Oopsie: \(error)")
                completion(nil)
            }
        }
    }
    
    func fetchRepo(_ repoURL: String) -> Repo? {
        var result: Repo?
        let semaphore = DispatchSemaphore(value: 0)
        
        fetchRepo(repoURL) { repo in
            result = repo
            semaphore.signal()
        }
        
        semaphore.wait()
        
        
        return result
    }
    
    func fetchRepos(_ repoURLs: [String], completion: @escaping ([RepoMemory], [BadRepoMemory]) -> Void) {
        let dispatchGroup = DispatchGroup()
        var results: [RepoMemory] = []
        var errors: [BadRepoMemory] = []
        
        for repoURL in repoURLs {
            dispatchGroup.enter()
            
            fetchRepo(repoURL.trimmingCharacters(in: .whitespacesAndNewlines)) { result in
                if let unwrappedResult = result {
                    let outputRepoMemory = RepoMemory(
                        url: repoURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        data: unwrappedResult
                    )
                    results.append(outputRepoMemory)
                } else {
                    let outputBadRepoMemory = BadRepoMemory(
                        url: repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    errors.append(outputBadRepoMemory)
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(results, errors)
        }
    }
    
    func IsAppInstalled(_ BundleID: String) -> Bool {
        let installedApps = InstalledApps
        return installedApps.contains { $0.id == BundleID }
    }
        
    func IsTrollStoreManaged(_ BundleID: String) -> Bool {
        let installedApps = InstalledApps
        if let installedApp = installedApps.first(where: { $0.id == BundleID }) {
            return installedApp.isTrollStore
        } else {
            return false
        }
    }
    
    func showUpdateButton(version1: String, BundleID: String) -> Int32 {
        let installedApps = InstalledApps
        if let installedApp = installedApps.first(where: { $0.id == BundleID }) {
            if (installedApp.version == version1) {
                return 0
            } else {
                return compareVersions(version1, installedApp.version) ? 1 : 2
            }
        } else {
            return 0
        }
    }
    
    func fetchAppsInRepo(repoInput: Repo, bundleIdInput: String) -> [Application] {
        return repoInput.apps.filter { $0.bundleIdentifier == bundleIdInput }
    }
}
