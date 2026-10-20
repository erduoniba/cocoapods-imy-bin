import Foundation

public struct GitBranchInfo: Equatable, Sendable {
    public let currentBranch: String?
    public let localBranches: [String]
    public let remoteBranches: [String]

    public init(currentBranch: String?, localBranches: [String], remoteBranches: [String]) {
        self.currentBranch = currentBranch
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
    }
}

public enum GitBranchManager {
    public static func branches(in repoURL: URL) -> GitBranchInfo {
        let current = runGit(in: repoURL, args: ["rev-parse", "--abbrev-ref", "HEAD"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var locals: [String] = []
        if let out = runGit(in: repoURL, args: ["branch", "--list"]) {
            locals = out.components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        var remotes: [String] = []
        if let out = runGit(in: repoURL, args: ["branch", "-r", "--list"]) {
            remotes = out.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.contains("->") }
                .map { line in
                    line.hasPrefix("origin/") ? String(line.dropFirst("origin/".count)) : line
                }
        }

        return GitBranchInfo(
            currentBranch: current,
            localBranches: locals.sorted(),
            remoteBranches: Array(Set(remotes)).sorted()
        )
    }

    public static func checkout(branch: String, in repoURL: URL) throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let (code, output) = runGitWithExitCode(in: repoURL, args: ["checkout", trimmed])
        if code != 0 {
            // Try checkout -b if tracking remote
            let (trackCode, trackOut) = runGitWithExitCode(in: repoURL, args: ["checkout", "-b", trimmed, "--track", "origin/\(trimmed)"])
            if trackCode != 0 {
                throw GitError.commandFailed("git checkout \(trimmed) 失败：\(output.isEmpty ? trackOut : output)")
            }
        }
    }

    public static func pull(in repoURL: URL) throws {
        let (code, output) = runGitWithExitCode(in: repoURL, args: ["pull"])
        if code != 0 {
            throw GitError.commandFailed("git pull 失败：\(output)")
        }
    }

    public static func remoteHeads(for gitURL: String) -> [String] {
        let trimmed = gitURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-remote", "--heads", trimmed]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            var branches: [String] = []
            for line in text.components(separatedBy: .newlines) {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if let range = trimmedLine.range(of: "refs/heads/") {
                    let branchName = String(trimmedLine[range.upperBound...])
                    if !branchName.isEmpty {
                        branches.append(branchName)
                    }
                }
            }
            return branches.sorted()
        } catch {
            return []
        }
    }

    private static func runGit(in directoryURL: URL, args: [String]) -> String? {
        let (code, out) = runGitWithExitCode(in: directoryURL, args: args)
        return code == 0 ? out : nil
    }

    private static func runGitWithExitCode(in directoryURL: URL, args: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directoryURL.path] + args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    public enum GitError: LocalizedError {
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .commandFailed(let msg): msg
            }
        }
    }
}
