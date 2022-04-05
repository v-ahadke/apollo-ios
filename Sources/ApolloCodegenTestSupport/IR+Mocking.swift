@testable import ApolloCodegenLib
import ApolloUtils

extension IR {

  public static func mock(schema: String, document: String) throws -> IR {
    let frontend = try GraphQLJSFrontend()
    let compilationResult = try frontend.compile(schema: schema, document: document)
    return .mock(compilationResult: compilationResult)
  }

  public static func mock(schema: String, documents: [String]) throws -> IR {
    let frontend = try GraphQLJSFrontend()
    let compilationResult = try frontend.compile(schema: schema, documents: documents)
    return .mock(compilationResult: compilationResult)
  }

  public static func mock(
    schemaName: String = "TestSchema",
    compilationResult: CompilationResult
  ) -> IR {
    return IR(schemaName: schemaName, compilationResult: compilationResult)
  }

}

extension IR.NamedFragment {

  public static func mock(
    _ name: String,
    type: GraphQLCompositeType = .mock("MockType")
  ) -> IR.NamedFragment {
    let rootEntity = IR.Entity(
      rootTypePath: LinkedList(type),
      fieldPath: ResponsePath(name)
    )
    let rootField = IR.EntityField.init(
      CompilationResult.Field.mock(),
      inclusionConditions: nil,
      selectionSet: .init(
        entity: rootEntity,
        scopePath: LinkedList(
          .descriptor(
            forType: type,
            inclusionConditions: nil,
            givenAllTypesInSchema: .init([type])
          ))))

    return IR.NamedFragment(
      definition: CompilationResult.FragmentDefinition.mock(name, type: type),
      rootField: rootField,
      referencedFragments: [],
      entities: [rootEntity.fieldPath: rootEntity]
    )
  }
}
