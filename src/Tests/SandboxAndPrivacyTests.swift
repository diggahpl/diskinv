//
//  SandboxAndPrivacyTests.swift
//  Disk Inventory XTests
//
//  Guards the privacy manifest, the Info.plist keys and the open panel that stands in for
//  opening a volume by path when the app runs in the App Sandbox.
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class SandboxAndPrivacyTests: XCTestCase {

    private func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testPrivacyManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is not a resource of the app")
        let manifest = try plist(at: url)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)

        // the required-reason APIs the app uses, each with a reason
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for api in apis {
            let type = try XCTUnwrap(api["NSPrivacyAccessedAPIType"] as? String)
            reasons[type] = api["NSPrivacyAccessedAPITypeReasons"] as? [String]
        }
        for category in ["NSPrivacyAccessedAPICategoryFileTimestamp",
                         "NSPrivacyAccessedAPICategoryDiskSpace",
                         "NSPrivacyAccessedAPICategorySystemBootTime",
                         "NSPrivacyAccessedAPICategoryUserDefaults"] {
            XCTAssertFalse(reasons[category]?.isEmpty ?? true, "no reason declared for \(category)")
        }
    }

    func testInfoPlistKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(info["LSApplicationCategoryType"] as? String, "public.app-category.utilities")
        XCTAssertEqual(info["LSMinimumSystemVersion"] as? String, "26.0")
        XCTAssertNotNil(info["CFBundleShortVersionString"] as? String)
        XCTAssertNotNil(info["CFBundleVersion"] as? String)
    }

    // In the sandbox a volume can only be reached through an open panel that opens inside it.
    func testVolumeAccessPanelOpensInsideTheVolumeAndChoosesFolders() {
        let volume = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let panel = AppSandbox.makeAccessPanel(for: volume, name: "Backup")
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.treatsFilePackagesAsDirectories)
        XCTAssertEqual(panel.directoryURL?.path, volume.path)
        XCTAssertTrue(panel.message.contains("Backup"))
        XCTAssertFalse(panel.prompt.isEmpty)
    }

    func testTestsRunOutsideTheSandbox() {
        // the unit tests host the unsandboxed Debug/Release app; a sandboxed process sets the variable
        XCTAssertEqual(AppSandbox.isActive, ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }

    func testProtectedFoldersAreTheRealOnes() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protected = FileManager.default.localPrivacyProtectedFolders().map { $0.path }
        for name in ["Documents", "Desktop", "Downloads", "Library/Calendars", "Library/Application Support/AddressBook"] {
            XCTAssertTrue(protected.contains("\(home)/\(name)"), "\(name) is missing from \(protected)")
        }
    }
}
