import Foundation
import Darwin

final class AppInstanceLock {
    private var descriptor: Int32 = -1
    func acquire(directory: URL) throws -> Bool {
        guard descriptor < 0 else { return true }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("instance.lock")
        descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        close(descriptor); descriptor = -1
        return false
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
