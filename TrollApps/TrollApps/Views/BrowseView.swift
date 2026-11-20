//
//  BrowseView.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-09.
//

import SwiftUI

struct AppListView: View {
    var apps: [Application]
    var showFullMode: Bool

    @EnvironmentObject var repoManager: RepositoryManager

    // Gizleme kayitlari degisince liste aninda yenilensin.
    @ObservedObject private var hiddenApps = HiddenAppsManager.shared
    @State private var showHiddenApps = false

    // Liste bolunmesi (guncelleme / diger) her govde degerlendirmesinde yeniden
    // hesaplanmamasi icin bellekte tutulur; yukaridaki onChange tetikleyicileri
    // yalnizca gerektiginde yeniler.
    @State private var updateApps: [Application] = []
    @State private var otherApps: [Application] = []

    var body: some View {
        List {
            Section(header: Text("UPDATES")
                .font(.caption.bold())
                .foregroundColor(Color("AccentColor"))) {
                if updateApps.isEmpty {
                    Text("NO_UPDATES")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    ForEach(updateApps, id: \.self) { app in
                        AppCell(app: app, showFullMode: showFullMode)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }

            Section(header: Text("ALL_APPS")
                .font(.caption.bold())
                .foregroundColor(Color("AccentColor"))) {
                ForEach(otherApps, id: \.self) { app in
                    AppCell(app: app, showFullMode: showFullMode)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(PlainListStyle())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showHiddenApps = true
                }) {
                    Image(systemName: "eye.slash")
                }
            }
        }
        .sheet(isPresented: $showHiddenApps) {
            HiddenAppsView()
        }
        .onAppear {
            recomputeLists(apps)
        }
        .onChange(of: apps) { newValue in
            recomputeLists(newValue)
        }
        // Uygulama Sirasi her degistiginde (Guncelleme eklenmesi vs.) tum liste
        // yeniden hesaplanip arayuz donuyordu; hiz icin bolunme yalnizca bu
        // tetikleyicilerde bir kez yapilir.
        .onChange(of: repoManager.storeMinimumOS) { _ in
            recomputeLists(apps)
        }
        .onChange(of: hiddenApps.entries) { _ in
            recomputeLists(apps)
        }
    }

    // Guncellemesi olan ve diger uygulamalar; bir kez hesaplanir, liste
    // degistikce ya da iOS/App Store siniri degistikce yenilenir.
    private func recomputeLists(_ allApps: [Application]) {
        updateApps = allApps
            .filter { !hiddenApps.isHidden($0.name, bundleId: $0.bundleIdentifier) && isUpdateAvailable($0) }
            .sorted { $0.name < $1.name }
        otherApps = allApps
            .filter { !hiddenApps.isHidden($0.name, bundleId: $0.bundleIdentifier) && !isUpdateAvailable($0) }
            .sorted { $0.name < $1.name }
    }

    /// Kurulu surumden daha yeni, cihazin iOS surumuyle uyumlu bir surum repoda varsa true.
    private func isUpdateAvailable(_ app: Application) -> Bool {
        guard let bundleId = app.bundleIdentifier, !bundleId.isEmpty,
              repoManager.IsAppInstalled(bundleId) else { return false }

        let latestVersion: String
        if let versions = app.versions, !versions.isEmpty {
            // En yeni surum cihazin iOS surumuyle uyumlu degilse, o uygulama Updates'e girmez.
            guard let compatibleIndex = compatibleVersionIndex(versions, appMinOSVersion: app.minOSVersion, appMaxOSVersion: app.maxOSVersion) else { return false }

            // Repo o surum icin sinir bildiriyorsa (ya da uyumlu daha eski bir surume dusulduyse)
            // repo verisi kesindir; App Store degeri o zaman guncellemeyi gizlemez.
            if shouldCheckStoreCompatibility(for: versions[compatibleIndex], in: versions, selectedIndex: compatibleIndex, appMinOSVersion: app.minOSVersion, appMaxOSVersion: app.maxOSVersion),
               isStoreVersionIncompatible(bundleId) {
                return false
            }

            latestVersion = versions[compatibleIndex].version
        } else {
            // Surum listesi yoksa (bazi repolarda olmuyor) eski davranisa dus: asla gizleme.
            if isStoreVersionIncompatible(bundleId) { return false }
            latestVersion = app.version ?? ""
        }

        guard !latestVersion.isEmpty else { return false }

        return repoManager.showUpdateButton(version1: latestVersion, BundleID: bundleId) == 1
    }

    /// App Store'un bildirdigi minimum iOS surumu cihaza uymuyorsa true.
    private func isStoreVersionIncompatible(_ bundleId: String) -> Bool {
        guard let storeMinOS = repoManager.storeMinimumOS[bundleId], !storeMinOS.isEmpty else { return false }
        return !isVersionCompatible(minOSVersion: storeMinOS, maxOSVersion: nil)
    }
}

struct BrowseView: View {
    @State private var searchText = ""
    @State private var showFullMode: Bool = false
    @State private var apps: [Application] = []
    @EnvironmentObject var repoManager: RepositoryManager

    var body: some View {
        NavigationView {
            VStack {
                if #available(iOS 15.0, *) {
                    AppListView(apps: filteredApps, showFullMode: showFullMode)
                        .searchable(text: $searchText)
                } else {
                    SearchBar(searchText: $searchText)
                    AppListView(apps: filteredApps, showFullMode: showFullMode)
                }
            }
            .navigationTitle("BROWSE")
            .navigationViewStyle(.stack)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: {
                        showFullMode.toggle()
                    }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .onAppear {
                loadApps()
            }
            .onChange(of: repoManager.hasFinishedFetchingRepos) { _ in
                loadApps()
            }
        }
        .navigationViewStyle(.stack)
    }

    // Repolardaki uygulamalari yukler ve kurulu olanlar icin App Store iOS sinirini tazeler.
    private func loadApps() {
        let loadedApps = repoManager.ReposData.flatMap { $0.data.apps }
        apps = loadedApps

        let bundleIDs = loadedApps.compactMap { $0.bundleIdentifier }.filter { repoManager.IsAppInstalled($0) }
        repoManager.refreshStoreMinimumOS(for: bundleIDs)
    }

    var filteredApps: [Application] {
        if searchText.isEmpty {
            return apps
        } else {
            return apps.filter { app in
                app.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// Gizlenen isimleri listeler. Bir satira dokunmak o isimdeki TUM uygulamalari
// geri getirir; boylece ayni isimli kopyalar tek tek ugrasmadan acilir.
struct HiddenAppsView: View {
    @ObservedObject private var hiddenApps = HiddenAppsManager.shared
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                if hiddenApps.names.isEmpty {
                    Text("NO_HIDDEN_APPS")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Section(footer: Text("HIDDEN_APPS_TOOLTIP")) {
                        ForEach(hiddenApps.names, id: \.self) { name in
                            Button(action: {
                                hiddenApps.unhide(name: name)
                            }) {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("UNHIDE_APP")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("HIDDEN_APPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
