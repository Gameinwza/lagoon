import AppKit
import Security
import os

/// Checks GitHub Releases for a newer Lagoon and installs it in place.
/// A downloaded app is installed only if it passes the running app's own designated requirement
/// (same bundle id, same signing certificate), so a tampered or foreign zip is refused.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle, checking, upToDate
        case available(version: String, zip: URL)
        case installing
        case failed(String)
    }
    @Published private(set) var phase: Phase = .idle

    static let releasesPage = URL(string: "https://github.com/Gameinwza/lagoon/releases/latest")!
    private let api = URL(string: "https://api.github.com/repos/Gameinwza/lagoon/releases/latest")!
    private let log = Logger(subsystem: "com.gameinwza.lagoon", category: "update")
    private var timer: Timer?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var available: String? { if case .available(let v, _) = phase { v } else { nil } }

    /// Checks shortly after launch, then once a day (one HTTPS request, no polling cost).
    /// Turning the setting off stops the timer; the manual "check" button still works.
    func applyAutoCheck() {
        assert(Self.isNewer("1.10.0", than: "1.9.9") && Self.isNewer("2.0", than: "1.99.1")
               && !Self.isNewer("1.2", than: "1.2.0") && !Self.isNewer("1.1.1", than: "1.1.2"))  // debug self-check
        timer?.invalidate(); timer = nil
        guard Pref.bool(Pref.autoUpdate) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if Pref.bool(Pref.autoUpdate) { self?.check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.check() }
        }
        timer?.tolerance = 3600
    }

    func check() {
        if phase == .checking || phase == .installing { return }
        phase = .checking
        Task {
            do {
                var req = URLRequest(url: api, timeoutInterval: 20)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Fail("GitHub ตอบกลับผิดปกติ") }
                let rel = try JSONDecoder().decode(Release.self, from: data)
                let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(latest, than: current),
                   let zip = rel.assets.first(where: { $0.name.hasSuffix(".zip") })?.browser_download_url {
                    phase = .available(version: latest, zip: zip)
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LAGOON_TEST_INSTALL"] != nil { install() }  // end-to-end test hook
                    #endif
                } else {
                    phase = .upToDate
                }
            } catch {
                log.error("check failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed("ตรวจหาอัปเดตไม่ได้")
            }
        }
    }

    func install() {
        guard case .available(let version, let zip) = phase else { return }
        phase = .installing
        Task {
            do {
                // Unzipping and signature checks are slow-ish; keep them off the main thread.
                let app = try await Task.detached { try await Self.download(zip) }.value
                try await Task.detached { try Self.verify(app, version: version) }.value
                try replaceAndRelaunch(with: app)
            } catch {
                log.error("install failed: \(String(describing: error), privacy: .public)")
                phase = .failed((error as? Fail)?.message ?? "ติดตั้งไม่สำเร็จ")
                // Manual route still works: the Releases page.
                NSWorkspace.shared.open(Self.releasesPage)
            }
        }
    }

    // MARK: steps

    nonisolated private static func download(_ url: URL) async throws -> URL {
        let (file, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Fail("ดาวน์โหลดไม่สำเร็จ") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lagoon-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", file.path, dir.path])  // ditto keeps the signature intact
        let app = dir.appendingPathComponent("Lagoon.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw Fail("ไฟล์อัปเดตไม่ถูกต้อง") }
        return app
    }

    /// The new app must satisfy this app's designated requirement (bundle id + signing certificate)
    /// and carry the version the release promised.
    nonisolated private static func verify(_ app: URL, version: String) throws {
        var me: SecCode?, meStatic: SecStaticCode?, req: SecRequirement?, new: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &req) == errSecSuccess, let req,
              SecStaticCodeCreateWithPath(app as CFURL, [], &new) == errSecSuccess, let new
        else { throw Fail("ตรวจลายเซ็นไม่ได้") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(new, flags, req) == errSecSuccess else { throw Fail("ลายเซ็นของไฟล์อัปเดตไม่ตรงกับแอปนี้") }
        let info = Bundle(url: app)?.infoDictionary
        guard info?["CFBundleShortVersionString"] as? String == version else { throw Fail("เวอร์ชันในไฟล์อัปเดตไม่ตรง") }
    }

    private func replaceAndRelaunch(with app: URL) throws {
        let target = Bundle.main.bundleURL
        // Read-only locations (e.g. a translocated copy run from Downloads) can't be updated in place.
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw Fail("ย้าย Lagoon ไปไว้ในโฟลเดอร์ Applications ก่อน แล้วลองอัปเดตอีกครั้ง")
        }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: app)
        // Relaunch once this process has exited; a running app would just be re-activated.
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", target.path]
        try p.run()
        NSApp.terminate(nil)
    }

    // MARK: helpers

    /// Numeric compare per component, so 1.10.0 > 1.9.9 and 1.2 == 1.2.0.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Fail("แตกไฟล์อัปเดตไม่ได้") }
    }

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
    }
    fileprivate struct Fail: Error { let message: String; init(_ m: String) { message = m } }
}
