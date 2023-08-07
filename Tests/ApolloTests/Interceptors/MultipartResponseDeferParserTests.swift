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

  struct Types {
    static let Product = Object(typename: "Product", implementedInterfaces: [])
  }

  private class QueryData: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("allProducts", [AllProduct?]?.self),
    ]}

    var allProducts: [AllProduct?]? { __data["allProducts"] }

    class AllProduct: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .inlineFragment(AsProduct.self, deferred: true),
      ]}

      var id: String { __data["id"] }

      var asProduct: AsProduct? { _asInlineFragment() }

      class AsProduct: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: ParentType { Types.Product }
        override class var __selections: [Selection] {[
          .field("variation", Variation?.self),
        ]}

        var variation: Variation? { __data["variation"] }

        class Variation: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
          ]}

          var id: String { __data["id"] }
          var name: String? { __data["name"] }
        }
      }
    }
  }

  #warning("remove the nulls in this test when the executor can handle deferred data without explicit nulls - #3145")
  func test__parsing__givenInitialResponse_shouldReturnSuccess() throws {
    MockSchemaMetadata.stub_objectTypeForTypeName = {
      switch $0 {
      case "Product": return Types.Product
      default: XCTFail(); return nil
      }
    }

    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "data": {
          "allProducts": [{
            "__typename": "Product",
            "id": "apollo-federation",
            "variation": null
          }, {
            "__typename": "Product",
            "id": "apollo-studio",
            "variation": null
          }, {
            "__typename": "Product",
            "id": "apollo-client",
            "variation": null
          }]
        },
        "hasNext": true
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try QueryData(data: [
      "allProducts": [
        [
          "__typename": "Product",
          "id": "apollo-federation",
          "variation": NSNull()
        ],
        [
          "__typename": "Product",
          "id": "apollo-studio",
          "variation": NSNull()
        ],
        [
          "__typename": "Product",
          "id": "apollo-client",
          "variation": NSNull()
        ]
      ]
    ])

    let expectation = expectation(description: "Initial response received")

    _ = network.send(operation: MockQuery<QueryData>()) { result in
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

  #warning("remove the nulls in this test when the executor can handle deferred data without explicit nulls - #3145")
  func test__parsing__givenInitialResponseWithGraphQLError_shouldReturnSuccessWithGraphQLError() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "data": {
          "allProducts": [{
            "__typename": "Product",
            "id": "apollo-federation",
            "variation": null
          }, {
            "__typename": "Product",
            "id": "apollo-studio",
            "variation": null
          }, {
            "__typename": "Product",
            "id": "apollo-client",
            "variation": null
          }]
        },
        "errors": [
          { "message": "Forced test error" }
        ],
        "hasNext": true
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try QueryData(data: [
      "allProducts": [
        [
          "__typename": "Product",
          "id": "apollo-federation",
          "variation": NSNull()
        ],
        [
          "__typename": "Product",
          "id": "apollo-studio",
          "variation": NSNull()
        ],
        [
          "__typename": "Product",
          "id": "apollo-client",
          "variation": NSNull()
        ]
      ]
    ])

    let expectation = expectation(description: "Initial response received")

    _ = network.send(operation: MockQuery<QueryData>()) { result in
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
