import Foundation

/// Explore references published on GitHub Pages, so new curated photos ship
/// without an app update. The app's only network call: a plain GET for a
/// public JSON manifest and the photos it lists. Nothing about the user or
/// device is sent (no cookies, no identifiers, no analytics), so App Privacy
/// stays "Data Not Collected".
///
/// Publishing: add photos with `explore-feed/add-reference.sh`, then
/// `explore-feed/publish.sh` (see `explore-feed/README.md`).
enum RemoteReferenceFeed {
    static let manifestURL = URL(string: "https://anikam13.github.io/frameshift-explore/manifest.json")!

    /// Highest manifest `version` this build understands. Bump the manifest's
    /// version only for breaking format changes; older apps then ignore it.
    static let supportedVersion = 1

    /// Curated key prefix stored in `ReferencePhoto.bundledAssetName`.
    static let keyPrefix = "remote:"

    static func key(for id: String) -> String { keyPrefix + id }
    static func isRemoteKey(_ key: String) -> Bool { key.hasPrefix(keyPrefix) }

    private static let maxImageBytes = 15 * 1024 * 1024
    private static let maxManifestBytes = 1024 * 1024

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false   // respect Low Data Mode
        return URLSession(configuration: config)
    }()

    // MARK: Manifest

    /// Last good manifest, so Explore chips (tags / Women–Men) work offline.
    static func loadCachedManifest() -> RemoteReferenceManifest? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(RemoteReferenceManifest.self, from: data)
    }

    /// Downloads and validates the manifest, then caches it. Throws on any
    /// network / format problem; callers treat that as "no update".
    static func fetchManifest() async throws -> RemoteReferenceManifest {
        let data = try await get(manifestURL, limit: maxManifestBytes)
        let manifest = try JSONDecoder().decode(RemoteReferenceManifest.self, from: data)
        guard manifest.version <= supportedVersion else { throw FeedError.unsupportedVersion }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
        return manifest
    }

    static func fetchImageData(for entry: RemoteReferenceManifest.Entry) async throws -> Data {
        // Photos must live beside the manifest (same host, https).
        guard let url = URL(string: entry.image, relativeTo: manifestURL)?.absoluteURL,
              url.scheme == "https", url.host == manifestURL.host
        else { throw FeedError.badImageURL }
        return try await get(url, limit: maxImageBytes)
    }

    // MARK: Private

    enum FeedError: Error { case badStatus, tooLarge, unsupportedVersion, badImageURL }

    private static func get(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("FrameShift", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FeedError.badStatus
        }
        guard data.count <= limit else { throw FeedError.tooLarge }
        return data
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RemoteExplore/manifest.json")
    }
}

/// `manifest.json` on the Explore feed site.
struct RemoteReferenceManifest: Codable {
    struct Entry: Codable, Hashable {
        /// Stable, unique, never reused. Removing an entry retires the photo
        /// from Explore (unless the user favorited it).
        let id: String
        /// Path relative to the manifest, e.g. "images/rooftop-lean.jpg".
        let image: String
        /// "women" | "men" — Explore's Women / Men toggle.
        let subject: String?
        /// Any of "fullBody", "portraits", "seated", "couples", "groups".
        let tags: [String]?
    }

    let version: Int
    let references: [Entry]
}

/// Explore metadata for every curated key: bundled asset names
/// (`SampleReferencePack`) and remote feed ids (`RemoteReferenceFeed`).
enum CuratedCatalog {
    private static let lock = NSLock()
    private static var remoteTags: [String: Set<CompositionFilter>] = [:]
    private static var remoteSubjects: [String: SampleReferencePack.Subject] = [:]

    static func tags(for key: String) -> Set<CompositionFilter>? {
        if let bundled = SampleReferencePack.tags[key] { return bundled }
        lock.lock(); defer { lock.unlock() }
        return remoteTags[key]
    }

    static func subject(for key: String) -> SampleReferencePack.Subject? {
        if let bundled = SampleReferencePack.subjects[key] { return bundled }
        lock.lock(); defer { lock.unlock() }
        return remoteSubjects[key]
    }

    static func setRemote(_ manifest: RemoteReferenceManifest) {
        var tags: [String: Set<CompositionFilter>] = [:]
        var subjects: [String: SampleReferencePack.Subject] = [:]
        for entry in manifest.references {
            let key = RemoteReferenceFeed.key(for: entry.id)
            // Untagged entries fall back to Vision framing for the chips.
            let parsed = Set((entry.tags ?? []).compactMap(CompositionFilter.init(feedTag:)))
            if !parsed.isEmpty { tags[key] = parsed }
            switch entry.subject?.lowercased() {
            case "women": subjects[key] = .women
            case "men":   subjects[key] = .men
            default:      break
            }
        }
        lock.lock(); defer { lock.unlock() }
        remoteTags = tags
        remoteSubjects = subjects
    }
}

extension CompositionFilter {
    init?(feedTag: String) {
        switch feedTag.lowercased() {
        case "fullbody", "full_body", "full-body": self = .fullBody
        case "portraits", "portrait":              self = .portraits
        case "seated":                             self = .seated
        case "couples", "couple":                  self = .couples
        case "groups", "group":                    self = .groups
        default:                                   return nil
        }
    }
}
