import XCTest

@testable import Typless

final class APIEndpointTests: XCTestCase {
  func testBuildsChatCompletionsURL() throws {
    let url = try APIEndpoint.chatCompletionsURL(
      from: "https://api.openai.com/v1/"
    )
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testAllowsPrivateHTTPAddresses() throws {
    let url = try APIEndpoint.chatCompletionsURL(
      from: "http://192.168.1.8:11434/v1"
    )
    XCTAssertEqual(url.host, "192.168.1.8")
  }

  func testRejectsPublicHTTPAddresses() {
    XCTAssertThrowsError(
      try APIEndpoint.chatCompletionsURL(from: "http://example.com/v1")
    ) { error in
      XCTAssertEqual(error as? APIEndpointError, .insecureRemoteHTTP)
    }
  }

  func testDefaultRecognitionLanguageIsSimplifiedChinese() async {
    await MainActor.run {
      let suiteName = "TyplessTests.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suiteName)!
      defer { defaults.removePersistentDomain(forName: suiteName) }
      let preferences = AppPreferences(defaults: defaults)
      XCTAssertEqual(preferences.recognitionLanguage, .simplifiedChinese)
    }
  }

  func testConservativePromptForbidsRewriting() {
    XCTAssertTrue(LLMRefinementService.systemPrompt.contains("Never rewrite"))
    XCTAssertTrue(LLMRefinementService.systemPrompt.contains("配森 → Python"))
    XCTAssertTrue(LLMRefinementService.systemPrompt.contains("杰森 → JSON"))
  }
}
