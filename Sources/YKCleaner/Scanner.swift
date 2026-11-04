import Foundation

enum Scanner {
    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    static func scan(_ category: CleanCategory) -> CategoryResult {
        var result = CategoryResult()
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(category.minAgeDays) * 86_400)

        for root in category.roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey],
                    options: [])
            } catch {
                result.accessDenied = true
                continue
            }

            for child in children {
                if category.minAgeDays > 0 {
                    let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    if modified > cutoff { continue }
                }
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                result.items.append(ScanItem(url: child, root: root, size: size(of: child), isDirectory: isDir))
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    /// Disk space used by a file or folder (does not follow symlinks).
    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey,
                                                       .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        if values?.isSymbolicLink == true { return 0 }
        if values?.isDirectory != true {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(sizeKeys), options: [],
            errorHandler: { _, _ in true }) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in e {
            guard let v = try? file.resourceValues(forKeys: sizeKeys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
