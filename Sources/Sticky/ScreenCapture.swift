import AppKit

final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()
    private var onDone: ((NSImage) -> Void)?

    /// 系统选区截图 → 自动创建待办
    func start(completion: @escaping (NSImage) -> Void) {
        onDone = completion

        let tmp = NSTemporaryDirectory() + "sticky_cap_\(Int(Date().timeIntervalSince1970)).png"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-x", tmp]  // -i 交互选区, -x 无声
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: tmp),
                      let image = NSImage(contentsOfFile: tmp) else { return }
                try? FileManager.default.removeItem(atPath: tmp)
                self?.onDone?(image)
            }
        }
        do {
            try proc.run()
        } catch {
            NSLog("[Capture] launch failed: \(error)")
        }
    }
}
