// import Foundation
// import ReadiumShared

// private let TAG = "LinkAsset"

// class LinkAsset : PublicationAsset {
//     // overrides PublicationAsset::name
//     let name: String
//     let _headers: [String: String]?
//     let _mediaType: MediaType

//     init(href: String, headers: [String: String]?, mediaType: MediaType) {
//         name = href
//         _headers = headers
//         _mediaType = mediaType
//     }

//     // overrides PublicationAsset::makeFetcher
//     public func makeFetcher(using dependencies: PublicationAssetDependencies, credentials: String?, completion: @escaping (CancellableResult<Fetcher, Publication.OpeningError>) -> Void) {
//         print("\(TAG)::makeFetcher, name=\(name), mediaType=\(_mediaType)")
//         //completion(.success(LinkFetcher(href: name)))
//         completion(.success(HTTPFetcher(client: DefaultHTTPClient(additionalHeaders: _headers), baseURL: URL(string: name))))
//     }

//     // overrides PublicationAsset::mediaType
//     public func mediaType() -> MediaType? {
//         return _mediaType
//     }
// }
