//
//  AppCell.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-16.
//

import SwiftUI
import Foundation
import Kingfisher

struct AppCell: View {
    let app : Application
    let showFullMode: Bool
    
    var body: some View {
        let compatibleIndex = compatibleVersionIndex(app.versions, appMinOSVersion: app.minOSVersion, appMaxOSVersion: app.maxOSVersion)
        // Gosterilecek surum: uyumlu surum varsa o, yoksa (bos/nil liste guvenli) 0.
        let displayIndex = compatibleIndex ?? 0
        let hasDisplayVersion = app.versions?.indices.contains(displayIndex) ?? false
        let version = (hasDisplayVersion ? (app.versions?[displayIndex].version ?? "") : "")
        let devName = (app.developerName != nil && app.developerName != "" ? (app.developerName ?? "") : "")
        
        VStack(alignment: .leading) {
            HStack {
                if(app.iconURL != "") {
                    KFImage(URL(string: app.iconURL))
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.trailing, 7)
                    
                } else {
                    Image("MissingApp")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.trailing, 7)
                }
                
                VStack(alignment: .leading) {
                    Text(app.name)
                        .font(.body.bold())
                    CollapsibleText(text: devName , isExpanded: .constant(false), maxLines: 1)
                        .font(.caption)
                        .foregroundColor(.gray)
                    CollapsibleText(text: version , isExpanded: .constant(false), maxLines: 1)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                DynamicInstallButton(appDetails: app, selectedVersionIndex: compatibleIndex ?? 0, buttonStyle: "Main")
            }
            
            if showFullMode {
                let screenshots = app.screenshotURLs ?? []
                if(screenshots.count > 0 ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(screenshots.indices, id: \.self) { index in
                                KFImage(URL(string: screenshots[index]))
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.init(top: 10, leading: 15, bottom: 10, trailing: 15))
        // Modern kart gorunumu: yuvarlak, surekli (continuous) kose; sistem
        // arka plan rengiyle acik/koyu temaya uyum saglar.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .contextMenu {
            // Not: Button(role:) iOS 15+ oldugu icin (deployment target 14.0)
            // rol kullanilmiyor; menu ogesi sade Button olarak ekleniyor.
            Button(action: {
                // Isim bazli gizleme: ayni isme sahip tum uygulamalar birlikte
                // listeden kaldirilir. Kayitlar kullanicinin actigi gizli
                // listesinden tek tek geri alinabilir.
                HiddenAppsManager.shared.hide(name: app.name)
            }) {
                Label("HIDE_APP", systemImage: "eye.slash")
            }
        }
        .background(
            NavigationLink("", destination: AppDetailsView(appDetails: app))
                .opacity(0)
        )
    }
}
