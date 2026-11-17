//
//  InstallManager.swift
//  TrollApps
//
//  Created by Cleopatra on 2023-12-18.
//

import Combine
import ZIPFoundation

// Indirilen IPA'nin Info.plist'inden MinimumOSVersion degerini okur.
// Okunamayan / beklenmeyen yerlesimde nil doner, boylece kurulum eskisi gibi devam eder.
func minimumOSVersionInIPA(_ ipaPath: String) -> String? {
    guard let archive = try? Archive(url: URL(fileURLWithPath: ipaPath), accessMode: .read) else { return nil }

    for entry in archive {
        let path = entry.path
        guard path.hasPrefix("Payload/"), path.hasSuffix(".app/Info.plist") else { continue }
        // Payload/App.app/Info.plist disindaki (or. uzantilar) girdileri atla.
        guard path.filter({ $0 == "/" }).count == 2 else { continue }

        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plistDictionary = plist as? [String: Any] else { return nil }

        return plistDictionary["MinimumOSVersion"] as? String
    }

    return nil
}

func InstallIPA(_ itemID: UUID, queueManager: QueueManager, completion: @escaping (FunctionStatus) -> Void) {
        
    let destinationFolderURL = URL(fileURLWithPath: "/var/mobile/.TrollApps/tmp/")
    let IPAPathURL = destinationFolderURL
        .appendingPathComponent(itemID.uuidString)
        .appendingPathExtension(".ipa")
        
    if !FileManager.default.fileExists(atPath: IPAPathURL.path) {
        completion(FunctionStatus(error: true, message: ErrorMessage(title: "FNF \(IPAPathURL.path)", body: "File does not exist")))
        return
    } else if let ipaMinOS = minimumOSVersionInIPA(IPAPathURL.path),
              !ipaMinOS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isVersionCompatible(minOSVersion: ipaMinOS, maxOSVersion: nil) {
        // IPA'nin istedigi minimum iOS surumu cihazdan yeni: kurmayi reddet ve dosyayi temizle.
        try? FileManager.default.removeItem(atPath: IPAPathURL.path)
        completion(FunctionStatus(error: true, message: ErrorMessage(title: "IOS_VERSION_TOO_LOW", body: ipaMinOS)))
        return
    } else if let trollStoreApp = SBFApplication(applicationBundleIdentifier: "com.opa334.TrollStore") {
        let trollstoreHelperPath = trollStoreApp.bundleURL.path + "/trollstorehelper"
        let returnCode = spawnRoot(trollstoreHelperPath, ["install", IPAPathURL.path])
        
        if(returnCode != 0) {
            completion(FunctionStatus(error: true, message: ErrorMessage(title: "FAILED_TO_INSTALL", body: "INSTALLATION_RETURNED_ERROR \(returnCode)")))
            return
        } else {
            NotificationCenter.default.post(name: Notification.Name("ApplicationsChanged"), object: nil)
            PassthroughSubject<Void, Never>().send()
            
            if FileManager.default.fileExists(atPath: IPAPathURL.path) {
                do {
                    try FileManager.default.removeItem(atPath: IPAPathURL.path)
                    completion(FunctionStatus(error: false))
                    return
                } catch {
                    completion(FunctionStatus(error: true, message: ErrorMessage(title: "ERROR_REMOVING_IPA_FILE_AFTER_INSTALL", body: "LIKELY_A_PERMS_ISSUE")))
                    return
                }
            } else {
                completion(FunctionStatus(error: true, message: ErrorMessage(title: "MISSING_DOWNLOADED_IPA", body: "")))
                return
            }
        }
    } else {
        completion(FunctionStatus(error: true, message: ErrorMessage(title: "TROLLSTORE_NOT_FOUND", body: "TROLLSTORE_IS_REQUIRED")))
        return
    }
}

func DeleteIPA(_ itemID: UUID) -> Bool {
    let destinationFolderURL = URL(fileURLWithPath: "/var/mobile/.TrollApps/tmp/")
    let IPAPathURL = destinationFolderURL
        .appendingPathComponent(itemID.uuidString)
        .appendingPathExtension(".ipa")
    
    if !FileManager.default.fileExists(atPath: IPAPathURL.path) {
        return false
    } else {
        do {
            try FileManager.default.removeItem(atPath: IPAPathURL.path)
            return true
        } catch {
            return false
        }
    }
}
