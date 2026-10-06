import AppKit

struct LocalLaunchPlan: Equatable {
    var executable: String
    var arguments: [String]
    static func make(_ target: LocalTarget) -> LocalLaunchPlan? {
        switch target.kind {
        case .application, .document: return nil
        case .jar: return .init(executable: "/usr/bin/java", arguments: ["-jar", target.path] + target.arguments)
        case .python: return .init(executable: "/usr/bin/env", arguments: ["python3", target.path] + target.arguments)
        case .javascript: return .init(executable: "/usr/bin/env", arguments: ["node", target.path] + target.arguments)
        case .executable: return .init(executable: target.path, arguments: target.arguments)
        case .shell, .command:
            // Respect the interpreter without putting user paths or arguments into shell source.
            if let handle = FileHandle(forReadingAtPath: target.path) {
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 4096)) ?? Data()
                let firstLine = String(decoding: data, as: UTF8.self).split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                if firstLine.hasPrefix("#!") {
                    let parts = firstLine.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                    if let runner = parts.first, runner.hasPrefix("/") {
                        return .init(executable: runner, arguments: Array(parts.dropFirst()) + [target.path] + target.arguments)
                    }
                }
            }
            return .init(executable: "/bin/zsh", arguments: [target.path] + target.arguments)
        }
    }
}

@MainActor final class LocalLauncher {
    static let shared = LocalLauncher()
    private var processes: [UUID: Process] = [:]
    static func logURL(for id: String) -> URL { AppFiles.directory.appendingPathComponent("LaunchLogs/\(id).log") }
    func launch(_ game: Game, completion: @escaping @MainActor (String?) -> Void) throws {
        guard let target = game.localTarget, FileManager.default.fileExists(atPath: target.path) else {
            throw NSError(domain: "LocalLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到原文件，请恢复文件或重新添加入口。"])
        }
        let url = URL(fileURLWithPath: target.path)
        if target.kind == .application {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = target.arguments
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                Task { @MainActor in completion(error?.localizedDescription) }
            }
        } else if let plan = LocalLaunchPlan.make(target) {
            let log = Self.logURL(for: game.id)
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: log, options: .atomic)
            let output = try FileHandle(forWritingTo: log)
            let process = Process(), token = UUID()
            process.executableURL = URL(fileURLWithPath: plan.executable)
            process.arguments = plan.arguments
            process.currentDirectoryURL = url.deletingLastPathComponent()
            process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                try? output.close()
                Task { @MainActor in
                    self?.processes.removeValue(forKey: token)
                    completion(process.terminationStatus == 0 ? nil : "\(game.name) 以状态 \(process.terminationStatus) 退出。可在详情页查看运行日志；Java、Python 或 Node.js 文件需要相应运行环境。")
                }
            }
            do { try process.run(); processes[token] = process }
            catch { try? output.close(); throw error }
        } else if !NSWorkspace.shared.open(url) {
            throw NSError(domain: "LocalLauncher", code: 2, userInfo: [NSLocalizedDescriptionKey: "没有可以打开此文件的应用。"])
        }
    }
}
