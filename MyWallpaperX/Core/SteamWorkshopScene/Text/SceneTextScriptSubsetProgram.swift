import Foundation

/// A bounded, data-only representation of the property-bound JavaScript accepted by
/// the native text runtime. It intentionally has no loops, function declarations,
/// host-object access, or arbitrary calls.
nonisolated struct SceneTextScriptSubsetProgram: Equatable, Sendable {
    nonisolated enum AssignmentOperator: Equatable, Sendable {
        case assign
        case add
        case remainder
    }

    indirect nonisolated enum Expression: Equatable, Sendable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case identifier(String)
        case newDate
        case member(Expression, String)
        case call(Expression, [Expression])
        case unaryNot(Expression)
        case unaryMinus(Expression)
        case add(Expression, Expression)
        case remainder(Expression, Expression)
        case equal(Expression, Expression, negated: Bool)
    }

    indirect nonisolated enum Statement: Equatable, Sendable {
        case declare(String, Expression?)
        case assign(String, AssignmentOperator, Expression)
        case conditional(Expression, [Statement], [Statement])
        case returnValue(Expression)
    }

    let parameterName: String
    let statements: [Statement]
}
