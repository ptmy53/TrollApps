//
//  NewsView.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-15.
//  Sileo'nun "Yenilikler" sekmesinden esinlenen akis: repolar her tarandiginda
//  surumu degisen / ilk kez gorulen paketler olay olarak kaydedilir. Ekran bu
//  olaylari tarama saatine gore gruplar; en yeni tarama en ustte, onceki
//  taramalar altinda listelenir. Asagi cekince repolar yeniden taranir.
//

import SwiftUI
import Kingfisher

// Bir gruptaki tek satir: guncel uygulama bilgisi + olayin surumu.
private struct NewsItem: Identifiable {
    let app: Application
    let event: NewsEvent
    var id: String { event.id }
}

// Ayni taramada bulunan olaylarin grubu ("18 KASIM 2026 21:15" gibi).
private struct NewsGroup: Identifiable {
    let epoch: Double
    let title: String
    let items: [NewsItem]
    var id: Double { epoch }
}

struct NewsView: View {
    // Olay kaydi degisince akis aninda yenilensin.
    @ObservedObject private var news = NewAppsManager.shared
    @EnvironmentObject var repoManager: RepositoryManager
    // Gizlenen uygulamalar Yenilikler akisinda da gorunmesin.
    @ObservedObject private var hiddenApps = HiddenAppsManager.shared

    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            content
                .navigationTitle("WHATS_NEW")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: refreshNow) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    }
                }
                .onChange(of: news.lastScan) { _ in
                    isRefreshing = false
                }
        }
        .navigationViewStyle(.stack)
    }

    // Asagi cekerek yenileme iOS 15+; iOS 14'te araç çubuğundaki buton.
    @ViewBuilder
    private var content: some View {
        if #available(iOS 15.0, *) {
            newsList.refreshable { await performRefresh() }
        } else {
            newsList
        }
    }

    private var newsList: some View {
        List {
            if groups.isEmpty {
                Text("NO_NEW_APPS")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(groups) { group in
                    Section(header: header(for: group)) {
                        ForEach(group.items) { item in
                            NewsRow(app: item.app, event: item.event)
                        }
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }

    // Sileo'daki gibi gri yuvarlak tarih rozeti + kac degisiklik oldugu.
    private func header(for group: NewsGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.title)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.systemGray5))
                )

            Text(String(format: NSLocalizedString("NEWS_GROUP_COUNT", comment: ""), group.items.count))
                .font(.caption2)
                .foregroundColor(.gray)

            Spacer()
        }
        .textCase(nil)
    }

    // Araç çubuğundan yenileme (iOS 14 dahil her sürümde).
    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        repoManager.fetchRepos()
        // Tarama 20 saniye içinde bitmezse göstergeyi kapat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            isRefreshing = false
        }
    }

    // Aşağı çekerek yenileme: tarama bitene kadar bekle.
    @available(iOS 15.0, *)
    private func performRefresh() async {
        let before = news.lastScan
        isRefreshing = true
        repoManager.fetchRepos()

        var waited = 0
        while news.lastScan <= before && waited < 40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }

        await MainActor.run {
            isRefreshing = false
        }
    }

    // Olaylari tarama saatine gore gruplar. En yeni grup ustte; son 30 gunun
    // kayitlari, en fazla 20 grup gosterilir.
    private var groups: [NewsGroup] {
        guard !news.events.isEmpty else { return [] }

        // bundle id -> guncel uygulama (detay sayfasi ve ikon icin).
        var appsById: [String: Application] = [:]
        for repo in repoManager.ReposData {
            for app in repo.data.apps {
                if let id = app.bundleIdentifier, appsById[id] == nil {
                    appsById[id] = app
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM y HH:mm"
        formatter.locale = Locale.current

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970

        var byEpoch: [Double: [NewsEvent]] = [:]
        for event in news.events where event.scanEpoch >= cutoff {
            byEpoch[event.scanEpoch, default: []].append(event)
        }

        var result: [NewsGroup] = []
        for (epoch, events) in byEpoch.sorted(by: { $0.key > $1.key }).prefix(20) {
            let items = events.compactMap { event -> NewsItem? in
                guard let app = appsById[event.bundleId],
                      !hiddenApps.isHidden(app.name, bundleId: app.bundleIdentifier) else { return nil }
                return NewsItem(app: app, event: event)
            }.sorted {
                $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
            }

            guard !items.isEmpty else { continue }

            result.append(NewsGroup(
                epoch: epoch,
                title: formatter.string(from: Date(timeIntervalSince1970: epoch))
                    .uppercased(with: Locale.current),
                items: items
            ))
        }

        return result
    }
}

// Sileo tarzi satir: ikon + vurgu renginde nokta ve ad, "gelistirici • surum •
// depo" satiri, aciklama. Satirdaki surum, guncellemenin geldigi surumdur.
// Satira dokununca uygulama detay sayfasi acilir.
private struct NewsRow: View {
    let app: Application
    let event: NewsEvent

    var body: some View {
        NavigationLink(destination: AppDetailsView(appDetails: app)) {
            HStack(alignment: .top) {
                if app.iconURL != "" {
                    KFImage(URL(string: app.iconURL))
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.trailing, 10)
                } else {
                    Image("MissingApp")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.trailing, 10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color("AccentColor"))
                            .frame(width: 8, height: 8)

                        Text(app.name)
                            .font(.body.bold())
                            .foregroundColor(Color("AccentColor"))

                        Spacer(minLength: 4)

                        Text(event.isUpdate ? "NEWS_UPDATED" : "NEWS_ADDED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color("AccentColor").opacity(0.18))
                            )
                            .foregroundColor(Color("AccentColor"))
                    }

                    let devName = (app.developerName ?? "").isEmpty ? "" : app.developerName! + " • "
                    let version = event.version.isEmpty ? "" : event.version + " • "
                    Text(devName + version + event.repoName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    if let description = app.localizedDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.init(top: 6, leading: 15, bottom: 6, trailing: 15))
        }
    }
}
