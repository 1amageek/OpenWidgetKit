import OpenFoundation
import OpenWidgetWindowsRuntime

@main
struct OpenWidgetPackager {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { throw usageError() }
        switch arguments[1] {
        case "validate-metadata":
            guard arguments.count == 3 else { throw usageError() }
            let configuration = try OpenWidgetProviderConfiguration.load(
                from: URL(fileURLWithPath: arguments[2])
            )
            try configuration.validateMetadata()
        case "generate":
            guard arguments.count == 5 else { throw usageError() }
            let configuration = try OpenWidgetProviderConfiguration.load(
                from: URL(fileURLWithPath: arguments[2])
            )
            try generate(
                configuration: configuration,
                packageRoot: URL(
                    fileURLWithPath: arguments[3],
                    isDirectory: true
                ),
                outputURL: URL(fileURLWithPath: arguments[4])
            )
        default:
            throw usageError()
        }
    }

    private static func generate(
        configuration: OpenWidgetProviderConfiguration,
        packageRoot: URL,
        outputURL: URL
    ) throws {
        try configuration.validate(packageRoot: packageRoot)
        let manifest = WindowsPackageManifestGenerator().generate(
            configuration: configuration
        )
        do {
            try manifest.write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw WindowsWidgetHostError.packagingFailed(
                "Unable to write '\(outputURL.path)': \(error)"
            )
        }
    }

    private static func usageError() -> WindowsWidgetHostError {
        .packagingFailed(
            "Usage: openwidget-packager validate-metadata <configuration> | generate <configuration> <package-root> <output-manifest>"
        )
    }
}
