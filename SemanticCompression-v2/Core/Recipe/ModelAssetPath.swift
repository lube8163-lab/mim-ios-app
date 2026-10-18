import Foundation

nonisolated enum ModelAssetPath {
    static func relativePath(_ file: URL, root: URL) throws -> String {
        // iOS can return /private/var URLs while the original sandbox URL starts
        // with /var. Removing a character count from the unnormalized path leaks
        // the sandbox prefix into recipes shared with other devices.
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = file.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(base), path.count > base.count else { throw RecipeError.modelMismatch }
        return String(path.dropFirst(base.count))
    }
}
