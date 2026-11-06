import EasyHiDPICore
import IOKit

enum DisplayLinks {
    static func all() -> [DisplayLink] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOPortTransportStateDisplayPort")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var links: [DisplayLink] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let link = DisplayLink(properties: dictionary) else { continue }
            links.append(link)
        }
        return links
    }
}
