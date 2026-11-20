//
//  FeaturedView.swift
//  TrollApps
//
//  Created by Анохин Юрий on 21.11.2022.
//

import SwiftUI

struct FeaturedView: View {
    
    @State private var showFullVersion: Bool = false
    
    @State private var repos: [RepoMemory] = []
    @EnvironmentObject var repoManager: RepositoryManager
    // Gizlenen uygulamalar O ne Cikanlar'da da gorunmesin.
    @ObservedObject private var hiddenApps = HiddenAppsManager.shared

    var body: some View {
        NavigationView {
            List {
                ForEach(repos.sorted(by: { $0.data.name ?? "UNNAMED_REPO" < $1.data.name ?? "UNNAMED_REPO" })) { repo in
                    let featured = visibleFeaturedApps(for: repo)
                    if !featured.isEmpty {
                        Section(header: Text(repo.data.name ?? "UNNAMED_REPO")
                            .font(.subheadline.bold())
                            .foregroundColor(Color("AccentColor"))) {
                            ForEach(featured, id: \.self) { app in
                                AppCell(app: app, showFullMode: false)
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("FEATURED")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            repos = repoManager.ReposData
        }
        .onChange(of: repoManager.hasFinishedFetchingRepos) { _ in
            repos = repoManager.ReposData
        }
    }

    // O ne Cikanlar listesindeki uygulamalar; gizlenenler cikarilir.
    private func visibleFeaturedApps(for repo: RepoMemory) -> [Application] {
        (repo.data.featuredApps ?? [])
            .flatMap { repoManager.fetchAppsInRepo(repoInput: repo.data, bundleIdInput: $0) }
            .filter { !hiddenApps.isHidden($0.name, bundleId: $0.bundleIdentifier) }
    }
}
