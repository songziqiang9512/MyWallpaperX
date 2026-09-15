import Foundation

extension SteamWorkshopService {
    /// Public Steam links remain user-visible destinations after the HTML data
    /// producer is retired; they are never consumed as product data sources.
    nonisolated static func makeDetailURL(id: String) -> URL {
        var components = URLComponents(string: Constants.detailBase)!
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }

    nonisolated static func normalizedAuthorWorkshopURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let absoluteURL = url.absoluteURL
        guard absoluteURL.path.contains("/myworkshopfiles") else { return absoluteURL }
        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            return absoluteURL
        }
        var queryItems = (components.queryItems ?? []).filter { $0.name != "appid" }
        queryItems.append(URLQueryItem(name: "appid", value: Constants.workshopAppID))
        components.queryItems = queryItems
        return components.url ?? absoluteURL
    }

    nonisolated static func resolvedAuthorWorkshopURL(
        for item: SteamWorkshopBrowserItem
    ) -> URL? {
        if let authorWorkshopURL = normalizedAuthorWorkshopURL(item.authorWorkshopURL) {
            return authorWorkshopURL
        }
        guard let authorProfileURL = item.authorProfileURL else { return nil }
        if authorProfileURL.path.contains("/myworkshopfiles") {
            return normalizedAuthorWorkshopURL(authorProfileURL) ?? authorProfileURL
        }
        guard var components = URLComponents(
            url: authorProfileURL.appendingPathComponent("myworkshopfiles"),
            resolvingAgainstBaseURL: false
        ) else {
            return authorProfileURL
        }
        components.queryItems = [URLQueryItem(name: "appid", value: Constants.workshopAppID)]
        return components.url ?? authorProfileURL
    }
}
