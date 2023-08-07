import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class MultipartResponseDeferParserTests: XCTestCase {

  let defaultTimeout = 0.5
  let testParser = MultipartResponseDeferParser.self
  let testSpec = MultipartResponseDeferParser.protocolSpec

  // MARK: - Error tests

  func test__error__givenChunk_withIncorrectContentType_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;\(self.testSpec)"],
        data: """
          --graphql
          content-type: test/custom

          {
            "data" : {
              "key" : "value"
            }
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(self.testParser.ParsingError.unsupportedContentType(type: "test/custom"))
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenUnrecognizableChunk_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;\(self.testSpec)"],
        data: """
          --graphql
          content-type: application/json

          not_a_valid_json_object
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(self.testParser.ParsingError.cannotParseChunkData)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenChunk_withMissingData_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;\(self.testSpec)"],
        data: """
          --graphql
          content-type: application/json

          {
            "key": "value"
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(self.testParser.ParsingError.cannotParsePayloadData)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  // MARK: Parsing tests

  private class Hero: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("name", String.self),
      .field("films", [String].self),
    ]}

    var name: String { __data["name"] }
    var films: [String] { __data["films"] }
  }

  private func buildNetworkTransport(
    responseData: Data
  ) -> RequestChainNetworkTransport {
    let client = MockURLSessionClient(
      response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;\(self.testSpec)"]),
      data: responseData
    )

    let provider = MockInterceptorProvider([
      NetworkFetchInterceptor(client: client),
      MultipartResponseParsingInterceptor(),
      JSONResponseParsingInterceptor()
    ])

    return RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )
  }

  func test__parsing__givenInitialResponse_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "data": {
          "__typename": "Hero",
          "name": "Luke Skywalker",
          "films": [
            "A New Hope",
            "The Empire Strikes Back"
          ]
        },
        "hasNext": true
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "Luke Skywalker",
      "films": [
        "A New Hope",
        "The Empire Strikes Back"
      ]
    ])

    let expectation = expectation(description: "Initial response received")

    _ = network.send(operation: MockQuery<Hero>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenInitialResponseWithGraphQLError_shouldReturnSuccessWithGraphQLError() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "data": {
          "__typename": "Hero",
          "name": "Luke Skywalker",
          "films": [
            "A New Hope",
            "The Empire Strikes Back"
          ]
        },
        "errors": [
          { "message": "Forced test error" }
        ],
        "hasNext": true
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "Luke Skywalker",
      "films": [
        "A New Hope",
        "The Empire Strikes Back"
      ]
    ])

    let expectation = expectation(description: "Initial response received")

    _ = network.send(operation: MockQuery<Hero>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
        expect(data.errors).to(equal([GraphQLError("Forced test error")]))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }
}
