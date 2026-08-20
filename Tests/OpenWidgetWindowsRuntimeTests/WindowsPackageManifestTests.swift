import OpenFoundation
@testable import OpenWidgetWindowsRuntime
import Testing

struct WindowsPackageManifestTests {
    @Test
    func generatesCOMAndWidgetRegistrationFromOneConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OpenWidgetManifest-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Assets"),
            withIntermediateDirectories: true
        )
        defer { removeFixture(at: root) }
        for name in ["44.png", "150.png", "store.png", "icon.png", "shot.png"] {
            FileManager.default.createFile(
                atPath: root.appendingPathComponent("Assets/\(name)").path,
                contents: Data()
            )
        }
        for name in ["Provider.exe", "OpenWidgetWindowsBridge.dll"] {
            FileManager.default.createFile(
                atPath: root.appendingPathComponent(name).path,
                contents: Data()
            )
        }
        let configuration = fixtureConfiguration()
        try configuration.validate(packageRoot: root)

        let manifest = WindowsPackageManifestGenerator().generate(
            configuration: configuration
        )

        #expect(manifest.contains(#"<com:Class Id="E7B2A965-16F5-49D8-9F30-3541DAA57131""#))
        #expect(manifest.contains(#"<CreateInstance ClassId="E7B2A965-16F5-49D8-9F30-3541DAA57131""#))
        #expect(manifest.contains(#"<Definition Id="fixture""#))
        #expect(manifest.contains(#"<Size Name="small" />"#))
        #expect(manifest.contains(#"<Size Name="medium" />"#))
        #expect(
            manifest.components(separatedBy: "<Capability>").count - 1 == 2
        )
        #expect(manifest.contains(#"ProcessorArchitecture="x64""#))
        #expect(manifest.contains(#"PackageDependency Name="Microsoft.WindowsAppRuntime.2""#))
        #expect(manifest.contains(#"MinVersion="2.3.1.0""#))
        #expect(manifest.contains(#"IgnorableNamespaces="uap uap3 com rescap""#))
        #expect(configuration.resources.first?.uri == "ms-appx:///Assets/icon.png")
    }

    @Test
    func escapesUntrustedDisplayMetadata() {
        var configuration = fixtureConfiguration()
        configuration = OpenWidgetProviderConfiguration(
            schemaVersion: configuration.schemaVersion,
            build: configuration.build,
            provider: configuration.provider,
            definitions: [
                WindowsWidgetDefinitionConfiguration(
                    kind: "fixture",
                    displayName: "A & B",
                    description: "<unsafe>",
                    icon: "Assets/icon.png",
                    screenshot: "Assets/shot.png",
                    families: configuration.definitions[0].families
                )
            ],
            resources: [
                WindowsWidgetResourceConfiguration(
                    name: "fixture-icon",
                    path: "Assets/icon.png"
                )
            ]
        )

        let manifest = WindowsPackageManifestGenerator().generate(
            configuration: configuration
        )

        #expect(manifest.contains("A &amp; B"))
        #expect(manifest.contains("&lt;unsafe&gt;"))
        #expect(!manifest.contains("<unsafe>"))
    }

    @Test
    func rejectsResourcePathsWhoseIdentityChangesDuringURINormalization() {
        let resource = WindowsWidgetResourceConfiguration(
            name: "unsafe",
            path: "Assets/%2e%2e/secret.png"
        )

        #expect(throws: WindowsWidgetHostError.self) {
            try resource.validate()
        }
    }

    @Test
    func rejectsWindowsAppRuntimeDependencyVersionDrift() {
        let build = WindowsWidgetBuildConfiguration(
            swiftSnapshot: "snapshot",
            swiftToolchainIdentifier: "toolchain",
            windowsAppSDKVersion: "2.3.1",
            widgetsPackageVersion: "2.0.5",
            cppWinRTVersion: "2.0.230706.1",
            wixToolsetSDKVersion: "4.0.5",
            windowsAppRuntimePackageName: "Microsoft.WindowsAppRuntime.2",
            windowsAppRuntimePublisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
            windowsAppRuntimeMinVersion: "2.3.0.0",
            visualCToolset: "v145",
            windowsSDKVersion: "10.0.26100.0",
            foundationLinkMode: "dynamic"
        )

        #expect(throws: WindowsWidgetHostError.self) {
            try build.validate()
        }
    }

    private func fixtureConfiguration() -> OpenWidgetProviderConfiguration {
        OpenWidgetProviderConfiguration(
            schemaVersion: 5,
            build: WindowsWidgetBuildConfiguration(
                swiftSnapshot: "snapshot",
                swiftToolchainIdentifier: "toolchain",
                windowsAppSDKVersion: "2.3.1",
                widgetsPackageVersion: "2.0.5",
                cppWinRTVersion: "2.0.230706.1",
                wixToolsetSDKVersion: "4.0.5",
                windowsAppRuntimePackageName: "Microsoft.WindowsAppRuntime.2",
                windowsAppRuntimePublisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
                windowsAppRuntimeMinVersion: "2.3.1.0",
                visualCToolset: "v145",
                windowsSDKVersion: "10.0.26100.0",
                foundationLinkMode: "dynamic"
            ),
            provider: WindowsWidgetProviderIdentity(
                packageName: "OpenWidgetKit.Fixture",
                publisher: "CN=Fixture",
                version: "1.0.0.0",
                architecture: "x64",
                applicationID: "Provider",
                executable: "Provider.exe",
                bridgeDLL: "OpenWidgetWindowsBridge.dll",
                classID: "{E7B2A965-16F5-49D8-9F30-3541DAA57131}",
                extensionID: "ProviderExtension",
                displayName: "Fixture",
                square44Logo: "Assets/44.png",
                square150Logo: "Assets/150.png",
                storeLogo: "Assets/store.png"
            ),
            definitions: [
                WindowsWidgetDefinitionConfiguration(
                    kind: "fixture",
                    displayName: "Fixture",
                    description: "Fixture description",
                    icon: "Assets/icon.png",
                    screenshot: "Assets/shot.png",
                    families: [
                        WindowsWidgetFamilyConfiguration(
                            name: "small",
                            displayWidth: 158,
                            displayHeight: 158,
                            displayScale: 1
                        ),
                        WindowsWidgetFamilyConfiguration(
                            name: "medium",
                            displayWidth: 338,
                            displayHeight: 158,
                            displayScale: 1
                        )
                    ]
                )
            ],
            resources: [
                WindowsWidgetResourceConfiguration(
                    name: "fixture-icon",
                    path: "Assets/icon.png"
                )
            ]
        )
    }

    private func removeFixture(at URL: URL) {
        do {
            try FileManager.default.removeItem(at: URL)
        } catch {
            Issue.record("Unable to remove manifest fixture: \(error)")
        }
    }
}
