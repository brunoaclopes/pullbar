import Foundation

struct GHCLIProfile: Identifiable, Hashable {
    let host: String
    let login: String
    let active: Bool
    let state: String

    var id: String { "\(host)::\(login)" }
}

struct GHCLIImportResult {
    let host: String
    let login: String
    let token: String
}

enum GHCLIImportError: LocalizedError {
    case ghNotInstalled
    case invalidStatusPayload
    case noAuthenticatedHost
    case tokenMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI is not installed. Install it and run `gh auth login` first."
        case .invalidStatusPayload:
            return "Unable to read authentication state from GitHub CLI."
        case .noAuthenticatedHost:
            return "No authenticated GitHub host found in GitHub CLI."
        case .tokenMissing:
            return "GitHub CLI did not return a token for the selected account."
        case .commandFailed(let message):
            return message
        }
    }
}

struct GHCLIImporter {
    func listProfiles() throws -> [GHCLIProfile] {
        guard commandExists("gh") else {
            throw GHCLIImportError.ghNotInstalled
        }

        let statusData = try runGh(arguments: ["auth", "status", "--json", "hosts"])
        let entries = try parseProfiles(data: statusData)
        let successful = entries.filter { $0.state == "success" }
        if successful.isEmpty {
            throw GHCLIImportError.noAuthenticatedHost
        }

        return successful.sorted {
            if $0.host == $1.host {
                if $0.active == $1.active {
                    return $0.login < $1.login
                }
                return $0.active && !$1.active
            }
            if $0.host == "github.com" { return true }
            if $1.host == "github.com" { return false }
            return $0.host < $1.host
        }
    }

    func switchActiveProfile(host: String, login: String) throws {
        guard commandExists("gh") else {
            throw GHCLIImportError.ghNotInstalled
        }

        _ = try runGh(arguments: ["auth", "switch", "--hostname", host, "--user", login])
    }

    func importProfile(host: String, login: String) throws -> GHCLIImportResult {
        guard commandExists("gh") else {
            throw GHCLIImportError.ghNotInstalled
        }

        let tokenData = try runGh(arguments: ["auth", "token", "--hostname", host, "--user", login])
        let token = String(decoding: tokenData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GHCLIImportError.tokenMissing
        }

        return GHCLIImportResult(host: host, login: login, token: token)
    }

    func importActiveAuth() throws -> GHCLIImportResult {
        guard commandExists("gh") else {
            throw GHCLIImportError.ghNotInstalled
        }

        let statusData = try runGh(arguments: ["auth", "status", "--json", "hosts"])
        let parsed = try parseActiveHost(data: statusData)

        return try importProfile(host: parsed.host, login: parsed.login)
    }

    private func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runGh(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            throw GHCLIImportError.ghNotInstalled
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty {
                throw GHCLIImportError.commandFailed("GitHub CLI command failed.")
            }
            throw GHCLIImportError.commandFailed(stderr)
        }

        return out.fileHandleForReading.readDataToEndOfFile()
    }

    private func parseActiveHost(data: Data) throws -> (host: String, login: String) {
        let successful = try parseProfiles(data: data).filter { $0.state == "success" }

        if let githubActive = successful.first(where: { $0.host == "github.com" && $0.active }) {
            return (githubActive.host, githubActive.login)
        }

        if let anyActive = successful.first(where: { $0.active }) {
            return (anyActive.host, anyActive.login)
        }

        if let first = successful.first {
            return (first.host, first.login)
        }

        throw GHCLIImportError.noAuthenticatedHost
    }

    private func parseProfiles(data: Data) throws -> [GHCLIProfile] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hosts = json["hosts"] as? [String: Any]
        else {
            throw GHCLIImportError.invalidStatusPayload
        }

        var parsed: [GHCLIProfile] = []

        for (host, value) in hosts {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard
                    let login = entry["login"] as? String,
                    let active = entry["active"] as? Bool,
                    let state = entry["state"] as? String
                else {
                    continue
                }
                parsed.append(GHCLIProfile(host: host, login: login, active: active, state: state))
            }
        }

        return parsed
    }
}