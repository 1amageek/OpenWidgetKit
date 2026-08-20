import OpenFoundation
import OpenWidgetRuntime

package struct OpenWidgetProviderConfiguration: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let build: WindowsWidgetBuildConfiguration
    package let provider: WindowsWidgetProviderIdentity
    package let definitions: [WindowsWidgetDefinitionConfiguration]
    package let resources: [WindowsWidgetResourceConfiguration]

    package init(
        schemaVersion: Int,
        build: WindowsWidgetBuildConfiguration,
        provider: WindowsWidgetProviderIdentity,
        definitions: [WindowsWidgetDefinitionConfiguration],
        resources: [WindowsWidgetResourceConfiguration]
    ) {
        self.schemaVersion = schemaVersion
        self.build = build
        self.provider = provider
        self.definitions = definitions
        self.resources = resources
    }

    package static func load(from URL: URL) throws -> Self {
        let data: Data
        do {
            data = try Data(contentsOf: URL)
        } catch {
            throw WindowsWidgetHostError.configurationReadFailed(
                "Unable to read '\(URL.path)': \(error)"
            )
        }
        do {
            try OpenWidgetConfigurationKeyValidator.validate(data)
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as WindowsWidgetHostError {
            throw error
        } catch {
            throw WindowsWidgetHostError.invalidConfiguration(
                "OpenWidgetProvider.json is not valid: \(error)"
            )
        }
    }

    package func validateMetadata() throws {
        guard schemaVersion == 4 else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Unsupported provider configuration schema '\(schemaVersion)'."
            )
        }
        try build.validate()
        try provider.validate()
        guard !definitions.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "At least one widget definition is required."
            )
        }
        var kinds: Set<String> = []
        for definition in definitions {
            try definition.validate()
            guard kinds.insert(definition.kind).inserted else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "Duplicate widget kind '\(definition.kind)'."
                )
            }
        }
        var resourceNames: Set<String> = []
        var resourcePaths: Set<String> = []
        for resource in resources {
            try resource.validate()
            guard resourceNames.insert(resource.name).inserted else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "Duplicate resource name '\(resource.name)'."
                )
            }
            guard resourcePaths.insert(resource.path).inserted else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "Duplicate resource path '\(resource.path)'."
                )
            }
        }
    }

    package func validate(packageRoot: URL) throws {
        try validateMetadata()
        for path in [
            provider.executable,
            provider.bridgeDLL,
            provider.square44Logo,
            provider.square150Logo,
            provider.storeLogo
        ] {
            try Self.validateFile(path, packageRoot: packageRoot)
        }
        for definition in definitions {
            try Self.validateFile(definition.icon, packageRoot: packageRoot)
            try Self.validateFile(definition.screenshot, packageRoot: packageRoot)
        }
        for resource in resources {
            try Self.validateFile(resource.path, packageRoot: packageRoot)
        }
    }

    @MainActor
    package func validate(
        registry: RuntimeWidgetRegistry,
        packageRoot: URL
    ) throws {
        try validate(packageRoot: packageRoot)
        let configuredKinds = Set(definitions.map(\.kind))
        let runtimeKinds = Set(registry.definitions.map(\.kind))
        guard runtimeKinds == configuredKinds else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Runtime widget kinds and manifest widget kinds differ."
            )
        }
        for runtimeDefinition in registry.definitions {
            guard let configured = definitions.first(where: {
                $0.kind == runtimeDefinition.kind
            }) else { continue }
            let configuredFamilies = Set(
                try configured.families.map { try $0.runtimeFamily() }
            )
            guard configuredFamilies == Set(runtimeDefinition.supportedFamilies) else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "Families for '\(runtimeDefinition.kind)' differ between runtime and manifest metadata."
                )
            }
        }
    }

    package func definition(
        kind: String
    ) -> WindowsWidgetDefinitionConfiguration? {
        definitions.first { $0.kind == kind }
    }

    package func resource(named name: String) -> WindowsWidgetResourceConfiguration? {
        resources.first { $0.name == name }
    }

    private static func validateFile(_ path: String, packageRoot: URL) throws {
        let resolvedRoot = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = resolvedRoot
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootComponents = resolvedRoot.pathComponents
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        )
        guard Array(fileURL.pathComponents.prefix(rootComponents.count))
                == rootComponents,
              exists,
              !isDirectory.boolValue else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Package file '\(path)' is missing or escapes the package root."
            )
        }
    }
}

package struct WindowsWidgetBuildConfiguration: Codable, Equatable, Sendable {
    package let swiftSnapshot: String
    package let swiftToolchainIdentifier: String
    package let windowsAppSDKVersion: String
    package let widgetsPackageVersion: String
    package let cppWinRTVersion: String
    package let windowsAppRuntimePackageName: String
    package let windowsAppRuntimePublisher: String
    package let windowsAppRuntimeMinVersion: String
    package let visualCToolset: String
    package let windowsSDKVersion: String
    package let foundationLinkMode: String

    package func validate() throws {
        guard Self.isBuildToken(swiftSnapshot),
              Self.isBuildToken(swiftToolchainIdentifier) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Swift build identifiers contain unsupported characters."
            )
        }
        guard Self.isDottedVersion(windowsAppSDKVersion, componentCount: 3),
              Self.isDottedVersion(widgetsPackageVersion, componentCount: 3),
              Self.isDottedVersion(cppWinRTVersion, componentCount: 4),
              Self.isDottedVersion(windowsAppRuntimeMinVersion, componentCount: 4),
              Self.isDottedVersion(windowsSDKVersion, componentCount: 4) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Windows SDK and NuGet pins must use fixed numeric versions."
            )
        }
        guard Self.isBuildToken(windowsAppRuntimePackageName),
              !windowsAppRuntimePublisher.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "The Windows App Runtime dependency identity is invalid."
            )
        }
        let appRuntimeMajor = windowsAppSDKVersion.split(separator: ".")[0]
        guard windowsAppRuntimePackageName == "Microsoft.WindowsAppRuntime.\(appRuntimeMajor)",
              windowsAppRuntimePublisher == "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
              windowsAppRuntimeMinVersion == "\(windowsAppSDKVersion).0" else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "The Windows App Runtime dependency must match the Windows App SDK pin."
            )
        }
        guard visualCToolset.first == "v",
              !visualCToolset.dropFirst().isEmpty,
              visualCToolset.dropFirst().unicodeScalars.allSatisfy({
                  (48...57).contains($0.value)
              }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "The Visual C++ toolset must use a fixed vNNN identifier."
            )
        }
        guard foundationLinkMode == "dynamic" || foundationLinkMode == "static" else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "foundationLinkMode must be either 'dynamic' or 'static'."
            )
        }
    }

    private static func isBuildToken(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || ".-_".unicodeScalars.contains($0)
        }
    }

    private static func isDottedVersion(
        _ value: String,
        componentCount: Int
    ) -> Bool {
        let components = value.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        return components.count == componentCount
            && components.allSatisfy {
                !$0.isEmpty && $0.unicodeScalars.allSatisfy {
                    (48...57).contains($0.value)
                }
            }
    }
}

package struct WindowsWidgetProviderIdentity: Codable, Equatable, Sendable {
    package let packageName: String
    package let publisher: String
    package let version: String
    package let architecture: String
    package let applicationID: String
    package let executable: String
    package let bridgeDLL: String
    package let classID: String
    package let extensionID: String
    package let displayName: String
    package let square44Logo: String
    package let square150Logo: String
    package let storeLogo: String

    package func validate() throws {
        let identifiers = [packageName, applicationID, extensionID]
        guard identifiers.allSatisfy({ Self.isIdentifier($0) }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Package, application, and extension identifiers may contain only letters, digits, '.', '-', and '_'."
            )
        }
        guard Self.isGUID(classID) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Provider classID must be a braced GUID."
            )
        }
        guard !publisher.isEmpty, !displayName.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Publisher and display name must be nonempty."
            )
        }
        for path in [
            executable,
            bridgeDLL,
            square44Logo,
            square150Logo,
            storeLogo
        ] {
            try Self.validateRelativePackagePath(path)
        }
        let versionParts = version.split(separator: ".")
        guard versionParts.count == 4,
              versionParts.allSatisfy({ UInt16($0) != nil }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Package version must contain four UInt16 components."
            )
        }
        guard architecture == "x64" || architecture == "arm64" else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Provider architecture must be x64 or arm64."
            )
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || ".-_".unicodeScalars.contains($0)
        }
    }

    private static func isGUID(_ value: String) -> Bool {
        guard value.count == 38,
              value.first == "{",
              value.last == "}" else { return false }
        let body = value.dropFirst().dropLast()
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return parts.joined().unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102: true
            default: false
            }
        }
    }

    fileprivate static func validateRelativePackagePath(_ path: String) throws {
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "'\(path)' is not a normalized relative package path."
            )
        }
    }
}

package struct WindowsWidgetDefinitionConfiguration: Codable, Equatable, Sendable {
    package let kind: String
    package let displayName: String
    package let description: String
    package let icon: String
    package let screenshot: String
    package let families: [WindowsWidgetFamilyConfiguration]

    package func validate() throws {
        guard !kind.isEmpty, !displayName.isEmpty, !description.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Widget kind and display metadata must be nonempty."
            )
        }
        try WindowsWidgetProviderIdentity.validateRelativePackagePath(icon)
        try WindowsWidgetProviderIdentity.validateRelativePackagePath(screenshot)
        guard !families.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Widget '\(kind)' must support at least one family."
            )
        }
        var seen: Set<String> = []
        for family in families {
            try family.validate()
            guard seen.insert(family.name).inserted else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "Widget '\(kind)' repeats family '\(family.name)'."
                )
            }
        }
    }

    package func family(
        _ runtimeFamily: RuntimeWidgetFamily
    ) throws -> WindowsWidgetFamilyConfiguration {
        guard let value = try families.first(where: {
            try $0.runtimeFamily() == runtimeFamily
        }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Widget '\(kind)' does not configure the requested family."
            )
        }
        return value
    }
}

package struct WindowsWidgetFamilyConfiguration: Codable, Equatable, Sendable {
    package let name: String
    package let displayWidth: Double
    package let displayHeight: Double
    package let displayScale: Double

    package func validate() throws {
        _ = try runtimeFamily()
        guard displayWidth.isFinite, displayWidth > 0,
              displayHeight.isFinite, displayHeight > 0,
              displayScale.isFinite, displayScale > 0 else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Family '\(name)' metrics must be finite and positive."
            )
        }
    }

    package func runtimeFamily() throws -> RuntimeWidgetFamily {
        switch name {
        case "small": .systemSmall
        case "medium": .systemMedium
        case "large": .systemLarge
        default:
            throw WindowsWidgetHostError.invalidConfiguration(
                "Unsupported widget family '\(name)'."
            )
        }
    }
}

package struct WindowsWidgetResourceConfiguration: Codable, Equatable, Sendable {
    package let name: String
    package let path: String

    package var uri: String {
        "ms-appx:///\(path)"
    }

    package func validate() throws {
        guard !name.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Resource names must be nonempty."
            )
        }
        try WindowsWidgetProviderIdentity.validateRelativePackagePath(path)
        guard path.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 45, 46, 47, 48...57, 65...90, 95, 97...122, 126:
                true
            default:
                false
            }
        }) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Resource '\(name)' must use an ASCII URI-safe package path."
            )
        }
    }
}

private enum OpenWidgetConfigurationKeyValidator {
    static func validate(_ data: Data) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let root = value as? [String: Any] else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "The provider configuration root must be an object."
            )
        }
        try requireKeys(
            root,
            allowed: ["schemaVersion", "build", "provider", "definitions", "resources"],
            path: "$"
        )
        try validateObject(
            root["build"],
            allowed: [
                "swiftSnapshot", "swiftToolchainIdentifier", "windowsAppSDKVersion",
                "widgetsPackageVersion", "cppWinRTVersion", "visualCToolset",
                "windowsAppRuntimePackageName", "windowsAppRuntimePublisher",
                "windowsAppRuntimeMinVersion", "windowsSDKVersion",
                "foundationLinkMode"
            ],
            path: "$.build"
        )
        try validateObject(
            root["provider"],
            allowed: [
                "packageName", "publisher", "version", "architecture",
                "applicationID", "executable", "bridgeDLL", "classID",
                "extensionID", "displayName", "square44Logo", "square150Logo",
                "storeLogo"
            ],
            path: "$.provider"
        )
        try validateArray(root["definitions"], path: "$.definitions") { value, path in
            guard let object = value as? [String: Any] else {
                throw WindowsWidgetHostError.invalidConfiguration(
                    "\(path) must be an object."
                )
            }
            try requireKeys(
                object,
                allowed: ["kind", "displayName", "description", "icon", "screenshot", "families"],
                path: path
            )
            try validateArray(object["families"], path: "\(path).families") {
                family, familyPath in
                try validateObject(
                    family,
                    allowed: ["name", "displayWidth", "displayHeight", "displayScale"],
                    path: familyPath
                )
            }
        }
        try validateArray(root["resources"], path: "$.resources") { value, path in
            try validateObject(
                value,
                allowed: ["name", "path"],
                path: path
            )
        }
    }

    private static func validateObject(
        _ value: Any?,
        allowed: Set<String>,
        path: String
    ) throws {
        guard let object = value as? [String: Any] else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "\(path) must be an object."
            )
        }
        try requireKeys(object, allowed: allowed, path: path)
    }

    private static func validateArray(
        _ value: Any?,
        path: String,
        element: (Any, String) throws -> Void
    ) throws {
        guard let array = value as? [Any] else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "\(path) must be an array."
            )
        }
        for (index, value) in array.enumerated() {
            try element(value, "\(path)[\(index)]")
        }
    }

    private static func requireKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "\(path) contains unknown keys: \(unknown.sorted().joined(separator: ", "))."
            )
        }
        let missing = allowed.subtracting(object.keys)
        guard missing.isEmpty else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "\(path) is missing keys: \(missing.sorted().joined(separator: ", "))."
            )
        }
    }
}
