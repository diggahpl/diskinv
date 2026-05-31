//
//  TestFixtures.swift
//  Disk Inventory XTests
//
//  Generates a known directory tree (files sized 2 MB down, nested in folders)
//  used by the scanning tests. Sizes are 4 KB-block-aligned so the file's
//  logical and physical (allocated) sizes match. The tree is written once to a
//  gitignored TestFixtures/ dir at the repo root (regenerated only if missing
//  or wrong-sized), so it persists across runs and is inspectable.
//
//  GPL v3
//

import Foundation

enum TestFixtures {

    // (relative path, exact byte count). All sizes are multiples of 4096.
    static let files: [(path: String, bytes: Int)] = [
        ("level0_2mb.dixfix",                 2 * 1024 * 1024),
        ("folderA/level1_1mb.dixfix",         1 * 1024 * 1024),
        ("folderA/level1_512k.dixfix",        512 * 1024),
        ("folderA/folderA1/level2_256k.dixfix", 256 * 1024),
        ("folderB/level1_128k.dixfix",        128 * 1024),
        ("folderB/level1_64k.dixfix",         64 * 1024),
    ]

    // folders that exist but contain no files
    static let emptyFolders = ["emptyFolder"]

    static var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }
    static var fileCount: Int { files.count }
    // folderA, folderA/folderA1, folderB, emptyFolder
    static var folderCount: Int { 4 }
    // top-level: level0_2mb.dixfix + folderA + folderB + emptyFolder
    static var topLevelChildCount: Int { 4 }

    // The fixtures live at <repo>/TestFixtures, derived from this source file's
    // location (src/Tests/TestFixtures.swift -> up 3 -> repo root).
    static var root: URL {
        URL(fileURLWithPath: #filePath)        // .../src/Tests/TestFixtures.swift
            .deletingLastPathComponent()       // .../src/Tests
            .deletingLastPathComponent()       // .../src
            .deletingLastPathComponent()       // .../<repo>
            .appendingPathComponent("TestFixtures")
    }

    // Creates the tree if any file is missing or the wrong size. Returns the root.
    @discardableResult
    static func ensure() throws -> URL {
        let fm = FileManager.default
        let root = self.root

        for (relPath, bytes) in files {
            let url = root.appendingPathComponent(relPath)
            let existingSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if existingSize == bytes { continue }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)   // exactly `bytes` zero bytes
        }

        for folder in emptyFolders {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }

        return root
    }
}
