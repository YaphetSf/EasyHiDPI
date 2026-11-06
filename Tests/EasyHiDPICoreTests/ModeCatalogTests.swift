import EasyHiDPICore
import Testing

private func size(_ width: Int, _ height: Int) -> DisplaySize {
    DisplaySize(width: width, height: height)
}

private func hidpi(_ id: Int32, _ width: Int, _ height: Int, hz: Double, native: Bool = false) -> DisplayModeInfo {
    DisplayModeInfo(id: id, size: size(width, height), pixels: size(width * 2, height * 2), refreshRate: hz, isNative: native)
}

private func lodpi(_ id: Int32, _ width: Int, _ height: Int, hz: Double, native: Bool = false) -> DisplayModeInfo {
    DisplayModeInfo(id: id, size: size(width, height), pixels: size(width, height), refreshRate: hz, isNative: native)
}

// Trimmed from the real mode list of an ASUS VG27A with an override installed.
private let vg27aModes: [DisplayModeInfo] = [
    hidpi(23, 1024, 576, hz: 144),
    hidpi(44, 1280, 720, hz: 144, native: true),
    hidpi(45, 1280, 720, hz: 144, native: true),
    lodpi(43, 1280, 720, hz: 144),
    hidpi(53, 1280, 720, hz: 60, native: true),
    hidpi(73, 1440, 810, hz: 144),
    hidpi(74, 1440, 810, hz: 144),
    lodpi(80, 1600, 900, hz: 144),
    hidpi(82, 1600, 900, hz: 144),
    hidpi(83, 1600, 900, hz: 144),
    hidpi(88, 1600, 900, hz: 60),
    lodpi(90, 1600, 1200, hz: 144),
    lodpi(95, 1920, 1080, hz: 144),
    hidpi(97, 1920, 1080, hz: 144),
    hidpi(98, 1920, 1080, hz: 144),
    hidpi(105, 1920, 1080, hz: 60),
    lodpi(112, 2560, 1440, hz: 144, native: true)
]

// Trimmed from the real mode list of a Philips 243B1JH rotated to portrait.
private let philipsModes: [DisplayModeInfo] = [
    hidpi(11, 540, 960, hz: 60, native: true),
    hidpi(20, 576, 1024, hz: 75),
    hidpi(49, 900, 1600, hz: 75),
    hidpi(50, 900, 1600, hz: 60),
    hidpi(55, 945, 1680, hz: 75),
    lodpi(62, 1080, 1920, hz: 75, native: true),
    lodpi(63, 1080, 1920, hz: 60, native: true),
    hidpi(70, 600, 800, hz: 75)
]

// Trimmed from the real mode list of a MacBook Pro built-in panel.
private let builtInModes: [DisplayModeInfo] = [
    hidpi(54, 1512, 982, hz: 120, native: true),
    hidpi(55, 1512, 982, hz: 60, native: true),
    hidpi(56, 1512, 982, hz: 59.93998718261719, native: true),
    hidpi(57, 1512, 982, hz: 50, native: true),
    hidpi(58, 1512, 982, hz: 48, native: true),
    hidpi(59, 1512, 982, hz: 47.94999694824219, native: true)
]

struct ModeCatalogTests {
    @Test func ratesAreTheCurrentSizesFastestFirst() {
        let current = vg27aModes.first { $0.id == 98 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])
        #expect(catalog.rates == [144, 60])
    }

    @Test func nearIdenticalRatesCountAsOne() {
        let catalog = ModeCatalog(modes: builtInModes, current: builtInModes[0], overrideSizes: [])
        #expect(catalog.rates == [120, 60, 50, 48])
    }

    @Test func lowResolutionModeOnlyOffersItsOwnRates() {
        let current = vg27aModes.first { $0.id == 95 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])
        #expect(catalog.rates == [144])
    }

    @Test func eachRowListsItsOwnRates() {
        let current = philipsModes.first { $0.id == 49 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [])
        let row = catalog.rows.first { $0.size == size(576, 1024) }!
        #expect(catalog.rates(for: row) == [75])
    }

    @Test func changingRateKeepsTheSizeAndPositionAmongIdenticalModes() {
        let second = vg27aModes.first { $0.id == 83 }!
        #expect(ModeCatalog(modes: vg27aModes, current: second, overrideSizes: []).target(forRate: 60)?.id == 88)

        let sixty = vg27aModes.first { $0.id == 88 }!
        #expect(ModeCatalog(modes: vg27aModes, current: sixty, overrideSizes: []).target(forRate: 144)?.id == 82)
    }

    @Test func changingRateCannotLeaveLowResolution() {
        let current = vg27aModes.first { $0.id == 95 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])
        #expect(catalog.target(forRate: 60) == nil)
    }

    @Test func choosingTheRateInUseStaysOnTheCurrentMode() {
        let current = builtInModes.first { $0.id == 56 }!
        let catalog = ModeCatalog(modes: builtInModes, current: current, overrideSizes: [])
        #expect(catalog.target(forRate: 60)?.id == 56)
    }

    @Test func rateLabelRoundsFractionalRates() {
        #expect(ModeCatalog.rateLabel(59.93998718261719) == "60Hz")
        #expect(ModeCatalog.rateLabel(47.94999694824219) == "48Hz")
    }

    @Test func rowsAreHiDPIOnlyWithNativeAspectDownToHalfNative() {
        let current = vg27aModes.first { $0.id == 83 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])

        #expect(catalog.rows.map(\.size) == [size(1920, 1080), size(1600, 900), size(1440, 810), size(1280, 720)])
        #expect(catalog.rows.filter(\.isCurrent).map(\.size) == [size(1600, 900)])
    }

    @Test func portraitDisplayUsesPortraitSizes() {
        let current = philipsModes.first { $0.id == 49 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [])

        #expect(catalog.rows.map(\.size) == [size(945, 1680), size(900, 1600), size(576, 1024), size(540, 960)])
    }

    @Test func overrideSizeTheSystemHasNotOfferedIsPending() {
        let current = philipsModes.first { $0.id == 49 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [size(810, 1440), size(900, 1600)])

        #expect(catalog.rows.filter(\.isPending).map(\.size) == [size(810, 1440)])
    }

    @Test func overrideSizeAtNativeThatIsNeverOfferedStaysHidden() {
        let current = philipsModes.first { $0.id == 49 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [size(1080, 1920)])

        #expect(catalog.rows.filter { $0.size == size(1080, 1920) }.isEmpty)
    }

    @Test func currentLowResolutionModeIsNotListedAndNothingIsTicked() {
        let current = vg27aModes.first { $0.id == 95 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])

        #expect(catalog.rows.filter { $0.size == size(1920, 1080) }.count == 1)
        #expect(catalog.rows.filter(\.isCurrent).isEmpty)
    }

    @Test func currentHiDPIModeOutsideTheUsualRangeStaysListed() {
        let current = philipsModes.first { $0.id == 70 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [])

        #expect(catalog.rows.filter(\.isCurrent).map(\.size) == [size(600, 800)])
    }

    @Test func switchingKeepsRefreshRateAndPositionAmongIdenticalModes() {
        let second = vg27aModes.first { $0.id == 83 }!
        let fromSecond = ModeCatalog(modes: vg27aModes, current: second, overrideSizes: [])
        let row = fromSecond.rows.first { $0.size == size(1920, 1080) }!
        #expect(fromSecond.target(for: row)?.id == 98)

        let first = vg27aModes.first { $0.id == 82 }!
        let fromFirst = ModeCatalog(modes: vg27aModes, current: first, overrideSizes: [])
        #expect(fromFirst.target(for: row)?.id == 97)
    }

    @Test func switchingFromSixtyHertzStaysAtSixtyHertz() {
        let current = vg27aModes.first { $0.id == 88 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])
        let row = catalog.rows.first { $0.size == size(1920, 1080) }!
        #expect(catalog.target(for: row)?.id == 105)
    }

    @Test func targetNeverPicksALowResolutionTwin() {
        let current = vg27aModes.first { $0.id == 83 }!
        let catalog = ModeCatalog(modes: vg27aModes, current: current, overrideSizes: [])
        for row in catalog.rows {
            #expect(catalog.target(for: row)?.isHiDPI == true)
        }
    }

    @Test func missingRefreshRateFallsBackToTheFastest() {
        let current = philipsModes.first { $0.id == 50 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [])
        let row = catalog.rows.first { $0.size == size(576, 1024) }!
        #expect(catalog.target(for: row)?.id == 20)
    }

    @Test func pendingRowHasNoTarget() {
        let current = philipsModes.first { $0.id == 49 }!
        let catalog = ModeCatalog(modes: philipsModes, current: current, overrideSizes: [size(810, 1440)])
        let row = catalog.rows.first { $0.isPending }!
        #expect(catalog.target(for: row) == nil)
    }
}
