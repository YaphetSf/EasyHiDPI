import EasyHiDPICore
import Foundation
import Testing

private let vg27a = DisplayIdentity(vendor: 1715, product: 10115)

private func plistDictionary(_ data: Data) throws -> NSDictionary {
    try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
}

private func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/VG27A-override", withExtension: "plist"))
    return try Data(contentsOf: url)
}

struct OverrideFileTests {
    // The fixture is the override confirmed working on a real VG27A on macOS 27.2.
    @Test func generatedFileMatchesTheOneConfirmedWorking() throws {
        var file = OverrideFile(id: vg27a)
        for size in [DisplaySize(width: 1280, height: 720), DisplaySize(width: 1920, height: 1080),
                     DisplaySize(width: 1440, height: 810), DisplaySize(width: 1600, height: 900)] {
            file.add(size)
        }
        #expect(try plistDictionary(file.encoded()) == plistDictionary(fixture()))
    }

    @Test func readsSizesFromTheConfirmedFile() throws {
        let file = try OverrideFile(plistData: fixture())
        #expect(file.sizes == [
            DisplaySize(width: 1920, height: 1080), DisplaySize(width: 1600, height: 900),
            DisplaySize(width: 1440, height: 810), DisplaySize(width: 1280, height: 720)
        ])
    }

    @Test func addIsIdempotentAndKeepsLargestFirst() throws {
        var file = try OverrideFile(plistData: fixture())
        file.add(DisplaySize(width: 1680, height: 945))
        file.add(DisplaySize(width: 1680, height: 945))
        #expect(file.sizes == [
            DisplaySize(width: 1920, height: 1080), DisplaySize(width: 1680, height: 945),
            DisplaySize(width: 1600, height: 900), DisplaySize(width: 1440, height: 810),
            DisplaySize(width: 1280, height: 720)
        ])
    }

    @Test func removeDropsEveryFormOfThatSizeOnly() throws {
        var file = try OverrideFile(plistData: fixture())
        file.remove(DisplaySize(width: 1600, height: 900))
        #expect(file.sizes == [
            DisplaySize(width: 1920, height: 1080), DisplaySize(width: 1440, height: 810),
            DisplaySize(width: 1280, height: 720)
        ])
        let reloaded = try OverrideFile(plistData: file.encoded())
        #expect(reloaded.sizes == file.sizes)
    }

    @Test func editingKeepsKeysItDoesNotManageAndEntriesItDidNotWrite() throws {
        let original: [String: Any] = [
            "DisplayProductName": "Someone Else's Tool",
            "IODisplayEDID": Data([1, 2, 3]),
            "scale-resolutions": [Data([0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x05, 0xA0])]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        var file = try OverrideFile(plistData: data)
        file.add(DisplaySize(width: 1920, height: 1080))

        let edited = try plistDictionary(file.encoded())
        #expect(edited["DisplayProductName"] as? String == "Someone Else's Tool")
        #expect(edited["IODisplayEDID"] as? Data == Data([1, 2, 3]))
        #expect(file.sizes == [DisplaySize(width: 1920, height: 1080), DisplaySize(width: 1280, height: 720)])
    }

    @Test func rejectsPlistsThatAreNotDictionaries() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["not", "a", "dictionary"], format: .xml, options: 0)
        #expect(throws: OverrideFileError.notADictionary) { try OverrideFile(plistData: data) }
    }
}

struct OverrideLocationTests {
    @Test func usesUnpaddedLowercaseHexLikeApple() {
        #expect(OverrideLocation.file(for: vg27a)
            == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3/DisplayProductID-2783")
        #expect(OverrideLocation.file(for: DisplayIdentity(vendor: 16652, product: 2404))
            == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-964")
    }
}

struct OverrideCommandsTests {
    @Test func installCreatesTheVendorFolderThenTheFileThenEnablesScaledModes() {
        #expect(OverrideCommands.install(source: "/tmp/a b.plist", for: vg27a) == [
            "/usr/bin/install -d -o root -g wheel -m 755 '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3'",
            "/usr/bin/install -o root -g wheel -m 644 '/tmp/a b.plist' '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3/DisplayProductID-2783'",
            "/usr/bin/defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool YES"
        ].joined(separator: " && "))
    }

    @Test func removeOnlyEverTouchesOneFileAndAnEmptyFolder() {
        let command = OverrideCommands.remove(for: vg27a)
        #expect(command == "/bin/rm -f '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3/DisplayProductID-2783' && { /bin/rmdir '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3' 2>/dev/null || true; }")
        #expect(!command.contains("-rf"))
    }

    @Test func quotesAwkwardPathsForTheShellAndAppleScript() {
        let shell = OverrideCommands.install(source: "/tmp/it's.plist", for: vg27a)
        #expect(shell.contains("'/tmp/it'\\''s.plist'"))

        let script = OverrideCommands.appleScript(running: "echo \"a\\b\"")
        #expect(script == "do shell script \"echo \\\"a\\\\b\\\"\" with administrator privileges")
    }
}
