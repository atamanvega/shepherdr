import Foundation
import Testing
@testable import ShepherdrCore

struct ExternalLinksTests {
    private func isExternal(_ link: String) -> Bool { ExternalLinks.contains(URL(string: link)!) }

    @Test func slackLinksGoToMacOS() {
        #expect(isExternal("https://acme.slack.com/archives/C0123456789/p1793187827378989"))
        #expect(isExternal("https://app.slack.com/client/T0123456/C0123456"))
        #expect(isExternal("https://slack.com/"))
        #expect(isExternal("http://Acme.Slack.com/archives/C0123456789"))
        #expect(isExternal("https://files.slack.com/files-pri/T0123-F0456/report.pdf"))
    }

    @Test func slackSignInStaysInTheSessionsBrowser() {
        #expect(!isExternal("https://slack.com/oauth/v2/authorize?client_id=1&scope=chat:write"))
        #expect(!isExternal("https://slack.com/openid/connect/authorize?client_id=1"))
        #expect(!isExternal("https://acme.slack.com/oauth/authorize?client_id=1"))
    }

    @Test func otherLinksStay() {
        #expect(!isExternal("https://github.com/theam/shepherdr/pull/25"))
        #expect(!isExternal("https://notslack.com/archives/C0123"))
        #expect(!isExternal("https://slack.com.example.org/archives/C0123"))
        #expect(!isExternal("https://example.org/slack.com"))
        #expect(!isExternal("file:///Users/me/slack.com/notes.md"))
    }
}

struct BrowserAddressTests {
    private func address(_ text: String) -> String? { BrowserAddress.url(from: text, home: "/Users/me")?.absoluteString }

    @Test func webAddressesGetTheirScheme() {
        #expect(address("github.com/theam/shepherdr") == "https://github.com/theam/shepherdr")
        #expect(address("  http://localhost:3000/a?b=c ") == "http://localhost:3000/a?b=c")
        #expect(address("not an address") == nil)
        #expect(address("") == nil)
    }

    @Test func filesOnThisMacOpenByPathOrFileURL() {
        #expect(address("file:///Users/me/out/report.html") == "file:///Users/me/out/report.html")
        #expect(address("file:///Users/me/My%20Notes/a.md") == "file:///Users/me/My%20Notes/a.md")
        // Pasted with its spaces, or from localhost, or with a section.
        #expect(address("file:///Users/me/My Notes/a.md") == "file:///Users/me/My%20Notes/a.md")
        #expect(address("file://localhost/tmp/a.png") == "file:///tmp/a.png")
        #expect(address("file:///Users/me/guide.html#install") == "file:///Users/me/guide.html#install")
        #expect(address("/Users/me/My Notes/a.md") == "file:///Users/me/My%20Notes/a.md")
        #expect(address("~/out/../report.pdf") == "file:///Users/me/report.pdf")
        #expect(address("file://") == nil)
    }
}
