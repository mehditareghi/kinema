#if os(tvOS)
import TVServices

/// tvOS Top Shelf placeholder provider.
final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let section = TVTopShelfItemCollection(items: [])
        section.title = "Kinema"
        return section
    }
}
#endif
