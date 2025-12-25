import Foundation
import AppKit

/// 日志级别
enum LogLevel: String {
    case debug = "🔧 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️  WARNING"
    case error = "❌ ERROR"
    case success = "✅ SUCCESS"
}

/// 全局日志管理器
/// 同时输出到控制台和文件
class Logger {
    static let shared = Logger()

    private let logDirectory: URL
    private let logFileName = "app.log"
    private var logFileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.stillmusicwhenback.logger", qos: .utility)

    // 配置
    private let maxLogFileSize: Int = 10 * 1024 * 1024 // 10 MB
    private let maxLogFiles = 5 // 保留最多 5 个历史日志文件

    private init() {
        // 日志目录: ~/Library/Logs/StillMusicWhenBack/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logDirectory = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("StillMusicWhenBack")

        setupLogDirectory()
        setupLogFile()
    }

    deinit {
        try? logFileHandle?.close()
    }

    // MARK: - Setup

    private func setupLogDirectory() {
        do {
            if !FileManager.default.fileExists(atPath: logDirectory.path) {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        } catch {
            print("❌ 无法创建日志目录: \(error)")
        }
    }

    private func setupLogFile() {
        let logFilePath = logDirectory.appendingPathComponent(logFileName)

        // 如果文件不存在，创建它
        if !FileManager.default.fileExists(atPath: logFilePath.path) {
            FileManager.default.createFile(atPath: logFilePath.path, contents: nil, attributes: nil)
        }

        // 打开文件句柄
        do {
            logFileHandle = try FileHandle(forWritingTo: logFilePath)
            logFileHandle?.seekToEndOfFile()

            // 写入启动标记
            let startupMessage = "\n\n========================================\n" +
                                "应用启动 - \(currentTimestamp())\n" +
                                "========================================\n\n"
            writeToFile(startupMessage)
        } catch {
            print("❌ 无法打开日志文件: \(error)")
        }
    }

    // MARK: - 公共日志方法

    func debug(_ message: String, module: String = "") {
        log(message, level: .debug, module: module)
    }

    func info(_ message: String, module: String = "") {
        log(message, level: .info, module: module)
    }

    func warning(_ message: String, module: String = "") {
        log(message, level: .warning, module: module)
    }

    func error(_ message: String, module: String = "") {
        log(message, level: .error, module: module)
    }

    func success(_ message: String, module: String = "") {
        log(message, level: .success, module: module)
    }

    // MARK: - 核心日志方法

    private func log(_ message: String, level: LogLevel, module: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = self.currentTimestamp()
            let moduleTag = module.isEmpty ? "" : "[\(module)] "
            let formattedMessage = "[\(timestamp)] \(level.rawValue) \(moduleTag)\(message)"

            // 输出到控制台
            print(formattedMessage)

            // 输出到文件
            self.writeToFile(formattedMessage + "\n")

            // 检查是否需要轮转日志
            self.rotateLogFileIfNeeded()
        }
    }

    // MARK: - 文件操作

    private func writeToFile(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        logFileHandle?.write(data)
    }

    private func rotateLogFileIfNeeded() {
        let logFilePath = logDirectory.appendingPathComponent(logFileName)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFilePath.path),
              let fileSize = attributes[.size] as? Int,
              fileSize >= maxLogFileSize else {
            return
        }

        // 关闭当前文件
        try? logFileHandle?.close()

        // 轮转日志文件
        rotateLogFiles()

        // 创建新的日志文件
        setupLogFile()
    }

    private func rotateLogFiles() {
        let logFilePath = logDirectory.appendingPathComponent(logFileName)

        // 删除最老的日志文件（如果存在）
        let oldestLogPath = logDirectory.appendingPathComponent("app.log.\(maxLogFiles)")
        try? FileManager.default.removeItem(at: oldestLogPath)

        // 重命名现有的日志文件
        for i in (1..<maxLogFiles).reversed() {
            let oldPath = logDirectory.appendingPathComponent("app.log.\(i)")
            let newPath = logDirectory.appendingPathComponent("app.log.\(i + 1)")
            try? FileManager.default.moveItem(at: oldPath, to: newPath)
        }

        // 重命名当前日志文件
        let archivedPath = logDirectory.appendingPathComponent("app.log.1")
        try? FileManager.default.moveItem(at: logFilePath, to: archivedPath)
    }

    // MARK: - 工具方法

    private func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    // MARK: - 公共工具方法

    /// 获取日志文件路径
    func getLogFilePath() -> String {
        return logDirectory.appendingPathComponent(logFileName).path
    }

    /// 获取日志目录路径
    func getLogDirectoryPath() -> String {
        return logDirectory.path
    }

    /// 打开日志目录
    func openLogDirectory() {
        NSWorkspace.shared.open(logDirectory)
    }

    /// 清空所有日志
    func clearAllLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 关闭当前文件
            try? self.logFileHandle?.close()

            // 删除所有日志文件
            let logFilePath = self.logDirectory.appendingPathComponent(self.logFileName)
            try? FileManager.default.removeItem(at: logFilePath)

            for i in 1...self.maxLogFiles {
                let archivedPath = self.logDirectory.appendingPathComponent("app.log.\(i)")
                try? FileManager.default.removeItem(at: archivedPath)
            }

            // 重新创建日志文件
            self.setupLogFile()
        }
    }
}

// MARK: - 便捷访问

/// 全局日志函数（更简洁的调用方式）
func logDebug(_ message: String, module: String = "") {
    Logger.shared.debug(message, module: module)
}

func logInfo(_ message: String, module: String = "") {
    Logger.shared.info(message, module: module)
}

func logWarning(_ message: String, module: String = "") {
    Logger.shared.warning(message, module: module)
}

func logError(_ message: String, module: String = "") {
    Logger.shared.error(message, module: module)
}

func logSuccess(_ message: String, module: String = "") {
    Logger.shared.success(message, module: module)
}
