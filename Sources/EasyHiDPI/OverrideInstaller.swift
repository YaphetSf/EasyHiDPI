import EasyHiDPICore
import Foundation

enum OverrideInstallerResult: Sendable {
    case success
    case cancelled
    case failure(String)
}

enum OverrideInstaller {
    static func load(_ id: DisplayIdentity) throws -> OverrideFile? {
        let path = OverrideLocation.file(for: id)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try OverrideFile(plistData: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    static func install(
        _ file: OverrideFile,
        for id: DisplayIdentity,
        completion: @escaping @MainActor @Sendable (OverrideInstallerResult) -> Void
    ) {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyHiDPI-\(UUID().uuidString).plist")
        do {
            try file.encoded().write(to: source)
        } catch {
            Task { @MainActor in completion(.failure(error.localizedDescription)) }
            return
        }
        runAsAdministrator(OverrideCommands.install(source: source.path, for: id)) { result in
            try? FileManager.default.removeItem(at: source)
            completion(result)
        }
    }

    static func remove(
        for id: DisplayIdentity,
        completion: @escaping @MainActor @Sendable (OverrideInstallerResult) -> Void
    ) {
        runAsAdministrator(OverrideCommands.remove(for: id), completion: completion)
    }

    /// osascript runs out of process so the password prompt never blocks the menu bar app.
    private static func runAsAdministrator(
        _ shell: String,
        completion: @escaping @MainActor @Sendable (OverrideInstallerResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", OverrideCommands.appleScript(running: shell)]
            let errors = Pipe()
            process.standardError = errors

            let result: OverrideInstallerResult
            do {
                try process.run()
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    result = .success
                } else if message.contains("-128") {
                    result = .cancelled
                } else {
                    result = .failure(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch {
                result = .failure(error.localizedDescription)
            }
            Task { @MainActor in completion(result) }
        }
    }
}
