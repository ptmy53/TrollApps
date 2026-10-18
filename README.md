<p align="center">
    <img src="./assets/ResonanceStoreIcon.png" alt="Logo" width="70" height="70"></img>
</p>


<h1 align="center">TrollApps</h1>
<h6 align="center">An App Store alternative for TrollStore.</h6><p align="center">
  <b>⭐ This fork adds an <i>Updates</i> section to the Browse screen</b><br>
  <a href="https://github.com/ptmy53/TrollApps/releases/latest"><b>⬇️ Download the latest build (TrollApps-updates.ipa)</b></a><br>
  <sub>Unofficial personal build · GPL-3.0 · details at the bottom of this page</sub>
</p>


# What is TrollApps?
TrollApps is an alternative to the iOS App Store for TrollStore users. TrollApps allows users to download apps from repositories and install them directly in TrollStore. **TrollApps works on iOS 14.0 and up; make sure to be on the latest version of TrollStore.**

# Requirements
You require a TrollStore 1.0 / 2.0 compatible device, and TrollStore must be installed to use this application. It is also required that you enable schema urls within TrollStore.

#

<p align="center">
    <img width=256 height=auto src="./assets/Screenshot-1.png"></img>
    <img width=256 height=auto src="./assets/Screenshot-2.png"></img>
    <img width=256 height=auto src="./assets/Screenshot-3.png"></img>
</p>

# Check out our documentation!
Information on TrollApps sources and our URL Scheme can be found <a href="https://github.com/TheResonanceTeam/TrollApps/blob/main/assets/Docs/DOCUMENTATION.md">here</a>

#

# Found a bug / want to send feedback? 
<h3>Join our <a href="https://discord.gg/PrF6XqpGgX">Discord</a>!</h3>

---

# ✨ Updates section (this fork)

This is a **personal fork** of [TheResonanceTeam/TrollApps](https://github.com/TheResonanceTeam/TrollApps) with one single change: the **Browse** screen is now split into two sections.

| Section | What it shows |
| --- | --- |
| **Updates** | apps whose repositories offer a newer version than the one installed on your device |
| **All Apps** | everything else — the normal Get / Open / older-versions entries |

Update detection reuses the app's own logic (`IsAppInstalled(bundleId)` + `showUpdateButton(version1:bundleID:)`), so a row lands under **Updates** exactly when it would show the UPDATE state. Both headers are always visible; when nothing needs updating, the Updates section shows *No updates available*. Nothing else in the UI or the behaviour was touched.

## ⬇️ Download

| Build | Link |
| --- | --- |
| **Latest** (TrollApps 2.3 + Updates section) | **[TrollApps-updates.ipa](https://github.com/ptmy53/TrollApps/releases/latest)** |
| All builds | **[Releases](https://github.com/ptmy53/TrollApps/releases)** |

## 📲 Install (TrollStore)

1. Open the download link on your iPhone / iPad with Safari.
2. Open **TrollStore → +** and pick the downloaded `TrollApps-updates.ipa`.
3. Done. The bundle id is the same as in the original app (`org.resonance.store`), so it installs **over** your existing TrollApps — your repositories and settings are kept.

The IPA is built from source in this repository and signed with the same privileged entitlements as the original app (`platform-application`, `no-sandbox`, `container-manager`, `persona-mgmt`, `MobileContainerManager.allowed`, `files.absolute-path.read-write`), after which TrollStore re-signs it during install. Installing and updating apps from your repos keeps working exactly like before.

## 🔧 Build it yourself

Everything needed is in this repo:

- **[`updates-section.patch`](https://github.com/ptmy53/TrollApps/blob/main/updates-section.patch)** — the complete source change (2 files: `TrollApps/Views/BrowseView.swift` and `TrollApps/Resources/en.lproj/Localizable.strings`).
- **[`.github/workflows/build-ipa.yml`](https://github.com/ptmy53/TrollApps/blob/main/.github/workflows/build-ipa.yml)** — clones the upstream project, applies the patch, builds it with Xcode on a macOS runner, signs it with `ldid` and publishes the IPA as a release.

Just run **Actions → Build TrollApps IPA (Updates section) → Run workflow**; the finished IPA shows up under **Releases**.

## 📝 Notes

- The version number stays **2.3** (the upstream release this is based on).
- The new localization keys (`UPDATES`, `ALL_APPS`, `NO_UPDATES`) are added for English only; other languages simply fall back to those keys.
- **Unofficial personal build** — all credit for TrollApps goes to [TheResonanceTeam](https://github.com/TheResonanceTeam/TrollApps). Licensed under **GPL-3.0**, same as upstream; this fork keeps its source public so the modification can be rebuilt and audited.

---

## 🇹🇷 Türkçe

Bu depo, TrollApps 2.3 üzerine yapılmış **kişisel** bir fork. Tek değişiklik: **Browse** ekranı artık iki bölüme ayrılıyor.

- **Updates** → cihazında kurulu sürümden yenisi olan uygulamalar (üstte).
- **All Apps** → geri kalan tüm uygulamalar (altta; Get / Open / eski sürümler).

Güncelleme tespiti, uygulamanın kendi mantığını kullanıyor; yani bir satır UPDATE gösterecekse Updates bölümünde çıkıyor. Başka hiçbir şey değiştirilmedi.

**İndirme:** [Son derlenmiş IPA](https://github.com/ptmy53/TrollApps/releases/latest) → **TrollStore → + → indirilen `TrollApps-updates.ipa`** seçilerek kurulur. Aynı bundle id kullanıldığı için mevcut TrollApps uygulamasının üzerine kurulur; repo ve ayarların silinmez.

Kendin derlemek istersen: **Actions → Build TrollApps IPA (Updates section) → Run workflow**.
