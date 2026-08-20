package struct WindowsPackageManifestGenerator: Sendable {
    package init() {}

    package func generate(
        configuration: OpenWidgetProviderConfiguration
    ) -> String {
        let provider = configuration.provider
        let build = configuration.build
        let classID = provider.classID.dropFirst().dropLast()
        let definitions = configuration.definitions.map { definition in
            let capabilities = definition.families.map { family in
                """
                              <Capability>
                                <Size Name="\(xml(family.name))" />
                              </Capability>
                """
            }.joined(separator: "\n")
            return """
                      <Definition Id="\(xml(definition.kind))" DisplayName="\(xml(definition.displayName))" Description="\(xml(definition.description))">
                        <Capabilities>
            \(capabilities)
                        </Capabilities>
                        <ThemeResources>
                          <Icons>
                            <Icon Path="\(xml(windowsPath(definition.icon)))" />
                          </Icons>
                          <Screenshots>
                            <Screenshot Path="\(xml(windowsPath(definition.screenshot)))" DisplayAltText="\(xml(definition.description))" />
                          </Screenshots>
                        </ThemeResources>
                      </Definition>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Package
          xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
          xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
          xmlns:uap3="http://schemas.microsoft.com/appx/manifest/uap/windows10/3"
          xmlns:com="http://schemas.microsoft.com/appx/manifest/com/windows10"
          xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
          IgnorableNamespaces="uap uap3 com rescap">
          <Identity Name="\(xml(provider.packageName))" Publisher="\(xml(provider.publisher))" Version="\(xml(provider.version))" ProcessorArchitecture="\(xml(provider.architecture))" />
          <Properties>
            <DisplayName>\(xml(provider.displayName))</DisplayName>
            <PublisherDisplayName>\(xml(provider.displayName))</PublisherDisplayName>
            <Logo>\(xml(windowsPath(provider.storeLogo)))</Logo>
          </Properties>
          <Dependencies>
            <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22000.0" MaxVersionTested="10.0.26100.0" />
            <PackageDependency Name="\(xml(build.windowsAppRuntimePackageName))" Publisher="\(xml(build.windowsAppRuntimePublisher))" MinVersion="\(xml(build.windowsAppRuntimeMinVersion))" />
          </Dependencies>
          <Resources>
            <Resource Language="x-generate" />
          </Resources>
          <Applications>
            <Application Id="\(xml(provider.applicationID))" Executable="\(xml(windowsPath(provider.executable)))" EntryPoint="Windows.FullTrustApplication">
              <uap:VisualElements DisplayName="\(xml(provider.displayName))" Description="\(xml(provider.displayName))" BackgroundColor="transparent" Square150x150Logo="\(xml(windowsPath(provider.square150Logo)))" Square44x44Logo="\(xml(windowsPath(provider.square44Logo)))" AppListEntry="none" />
              <Extensions>
                <com:Extension Category="windows.comServer">
                  <com:ComServer>
                    <com:ExeServer Executable="\(xml(windowsPath(provider.executable)))" DisplayName="\(xml(provider.displayName))">
                      <com:Class Id="\(xml(String(classID)))" DisplayName="\(xml(provider.displayName))" />
                    </com:ExeServer>
                  </com:ComServer>
                </com:Extension>
                <uap3:Extension Category="windows.appExtension">
                  <uap3:AppExtension Name="com.microsoft.windows.widgets" DisplayName="\(xml(provider.displayName))" Id="\(xml(provider.extensionID))" PublicFolder="Public">
                    <uap3:Properties>
                      <WidgetProvider>
                        <ProviderIcons>
                          <Icon Path="\(xml(windowsPath(provider.storeLogo)))" />
                        </ProviderIcons>
                        <Activation>
                          <CreateInstance ClassId="\(xml(String(classID)))" />
                        </Activation>
                        <Definitions>
        \(definitions)
                        </Definitions>
                      </WidgetProvider>
                    </uap3:Properties>
                  </uap3:AppExtension>
                </uap3:Extension>
              </Extensions>
            </Application>
          </Applications>
          <Capabilities>
            <rescap:Capability Name="runFullTrust" />
          </Capabilities>
        </Package>
        """
    }

    private func windowsPath(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "\\")
    }

    private func xml(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&apos;")
            default: result.append(character)
            }
        }
        return result
    }
}
