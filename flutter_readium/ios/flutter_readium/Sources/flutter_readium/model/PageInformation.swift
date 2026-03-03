import Foundation

final class PageInformation {

    let pageIndex: Int64?
    let totalPages: Int64?
    let physicalPageIndex: String?

    init(pageIndex: Int64?, totalPages: Int64?, physicalPageIndex: String?) {
        self.pageIndex = pageIndex
        self.totalPages = totalPages
        self.physicalPageIndex = physicalPageIndex
    }

    var otherLocations: [String: Any] {
        var res: [String: Any] = [:]

        if let pageIndex, let totalPages {
            res["currentPage"] = pageIndex
            res["totalPages"] = totalPages
        }

        if let physicalPageIndex,
           !physicalPageIndex.isEmpty {
            res["physicalPage"] = physicalPageIndex
        }

        return res
    }

    static func fromJson(_ jsonString: String) throws -> PageInformation {
        let data = Data(jsonString.utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return fromJson(object)
    }

    static func fromJson(_ json: [String: Any]) -> PageInformation {
        let pageIndex = json["pageIndex"] as? NSNumber
        let totalPages = json["totalPages"] as? NSNumber
        let physicalPageIndex = json["physicalPageIndex"] as? String

        return PageInformation(
            pageIndex: pageIndex?.int64Value,
            totalPages: totalPages?.int64Value,
            physicalPageIndex: physicalPageIndex
        )
    }
}
