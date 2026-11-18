import Foundation

/// What a session browser's address field takes: a web address, with or without its scheme, or a
/// file on this Mac by its path or its `file://` URL.
public enum BrowserAddress {
    /// The page or file the text names, or nil when it names neither. Whether the file exists is
    /// the caller's question.
    public static func url(from text: String, home: String = NSHomeDirectory()) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text).standardizedFileURL }
        if text == "~" || text.hasPrefix("~/") { return URL(fileURLWithPath: home + text.dropFirst()).standardizedFileURL }
        if text.range(of: "file:", options: [.anchored, .caseInsensitive]) != nil {
            // A path pasted after file:// may keep its spaces as they are.
            let parsed = URL(string: text) ?? text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
            guard let parsed, parsed.isFileURL, parsed.path(percentEncoded: false).hasPrefix("/") else { return nil }
            let file = URL(fileURLWithPath: parsed.path(percentEncoded: false)).standardizedFileURL
            guard let fragment = parsed.fragment(percentEncoded: true) else { return file }
            return URL(string: "#\(fragment)", relativeTo: file)?.absoluteURL ?? file
        }
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate), url.host()?.isEmpty == false else { return nil }
        return url
    }
}
