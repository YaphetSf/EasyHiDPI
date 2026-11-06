/// Shell commands that run as root after the system password prompt. Paths are always quoted and
/// removal only touches one display's file, so other overrides and files are never at risk.
public enum OverrideCommands {
    public static func install(source: String, for id: DisplayIdentity) -> String {
        [
            "/usr/bin/install -d -o root -g wheel -m 755 \(shellQuoted(OverrideLocation.vendorDirectory(for: id)))",
            "/usr/bin/install -o root -g wheel -m 644 \(shellQuoted(source)) \(shellQuoted(OverrideLocation.file(for: id)))",
            "/usr/bin/defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool YES"
        ].joined(separator: " && ")
    }

    public static func remove(for id: DisplayIdentity) -> String {
        let file = shellQuoted(OverrideLocation.file(for: id))
        let directory = shellQuoted(OverrideLocation.vendorDirectory(for: id))
        return "/bin/rm -f \(file) && { /bin/rmdir \(directory) 2>/dev/null || true; }"
    }

    public static func appleScript(running shell: String) -> String {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    static func shellQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
