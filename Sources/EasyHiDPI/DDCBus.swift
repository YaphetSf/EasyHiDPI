import CoreGraphics
import EasyHiDPICore
import Foundation
import IOKit

/// IOAVService is private API: it is the only DDC path on Apple Silicon, so it is resolved at
/// runtime and a missing symbol just means no brightness controls.
private struct IOAVFunctions {
    typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias TransferI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias CopyEDID = @convention(c) (CFTypeRef, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn

    let create: Create
    let read: TransferI2C
    let write: TransferI2C
    let copyEDID: CopyEDID

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let read = dlsym(handle, "IOAVServiceReadI2C"),
              let write = dlsym(handle, "IOAVServiceWriteI2C"),
              let copyEDID = dlsym(handle, "IOAVServiceCopyEDID") else { return nil }
        self.create = unsafeBitCast(create, to: Create.self)
        self.read = unsafeBitCast(read, to: TransferI2C.self)
        self.write = unsafeBitCast(write, to: TransferI2C.self)
        self.copyEDID = unsafeBitCast(copyEDID, to: CopyEDID.self)
    }
}

/// All I2C traffic and all mutable state stay on one serial queue.
final class DDCBus: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dz.easyhidpi.ddc")
    private let functions = IOAVFunctions()
    private var services: [CGDirectDisplayID: CFTypeRef] = [:]
    private var pendingWrites: [CGDirectDisplayID: Int] = [:]
    private var isDraining = false

    func rebind(_ displays: [(id: CGDirectDisplayID, identity: EDIDIdentity)]) -> Set<CGDirectDisplayID> {
        queue.sync {
            let endpoints = externalEndpoints()
            services = matchEndpoints(displays: displays, endpoints: endpoints)
            return Set(services.keys)
        }
    }

    func rebind(
        _ displays: [(id: CGDirectDisplayID, identity: EDIDIdentity)],
        completion: @escaping @MainActor @Sendable (Set<CGDirectDisplayID>) -> Void
    ) {
        let displays = UncheckedBox(displays)
        queue.async { [self] in
            let endpoints = externalEndpoints()
            services = matchEndpoints(displays: displays.value, endpoints: endpoints)
            let bound = Set(services.keys)
            Task { @MainActor in completion(bound) }
        }
    }

    func readBrightness(_ id: CGDirectDisplayID) -> DDCReading? {
        queue.sync { readNow(id) }
    }

    func readBrightness(
        _ id: CGDirectDisplayID,
        completion: @escaping @MainActor @Sendable (DDCReading) -> Void
    ) {
        queue.async { [self] in
            guard pendingWrites[id] == nil, let reading = readNow(id) else { return }
            Task { @MainActor in completion(reading) }
        }
    }

    /// Sliders fire faster than displays can take, so only the newest value per display is sent.
    func setBrightness(_ id: CGDirectDisplayID, to value: Int) {
        queue.async { [self] in
            pendingWrites[id] = value
            guard !isDraining else { return }
            isDraining = true
            drainWrites()
        }
    }

    private func drainWrites() {
        guard let (id, value) = pendingWrites.first else {
            isDraining = false
            return
        }
        pendingWrites[id] = nil
        if let functions, let service = services[id] {
            _ = send(DDC.writeRequest(code: DDC.brightnessCode, value: value), to: service, with: functions)
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in drainWrites() }
    }

    /// Every message goes out twice: a Samsung S32B80P answers a lone read request with a null message.
    private func send(_ message: [UInt8], to service: CFTypeRef, with functions: IOAVFunctions) -> Bool {
        var message = message
        var status = kIOReturnSuccess
        for _ in 0..<2 {
            status = functions.write(service, DDC.chipAddress, DDC.dataAddress, &message, UInt32(message.count))
            usleep(10_000)
        }
        return status == kIOReturnSuccess
    }

    private func readNow(_ id: CGDirectDisplayID) -> DDCReading? {
        guard let functions, let service = services[id] else { return nil }
        for _ in 0..<4 {
            guard send(DDC.readRequest(code: DDC.brightnessCode), to: service, with: functions) else {
                usleep(60_000)
                continue
            }
            usleep(60_000)
            // Never read more than one reply at a time: a long read makes a Samsung S32B80P return garbage until power cycled.
            var reply = [UInt8](repeating: 0, count: DDC.replyLength)
            let status = functions.read(service, DDC.chipAddress, DDC.dataAddress, &reply, UInt32(reply.count))
            if status == kIOReturnSuccess, let reading = DDC.parseReply(reply, code: DDC.brightnessCode) {
                return reading
            }
            usleep(60_000)
        }
        return nil
    }

    private func externalEndpoints() -> [(identity: EDIDIdentity, endpoint: CFTypeRef)] {
        guard let functions else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var endpoints: [(identity: EDIDIdentity, endpoint: CFTypeRef)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External",
                  let service = functions.create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var edid: Unmanaged<CFData>?
            guard functions.copyEDID(service, &edid) == kIOReturnSuccess,
                  let data = edid?.takeRetainedValue() as Data?,
                  let identity = EDIDIdentity(edid: [UInt8](data)) else { continue }
            endpoints.append((identity, service))
        }
        return endpoints
    }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
