import Foundation

/// Typing and numerical evaluation of derivation steps. A step is checked the way a property-based test checks code:
/// Lemma draws random values for every symbol · numbers, vectors and matrices of consistent sizes · and evaluates
/// both sides. A counterexample shows a step is wrong; agreement on every draw is strong evidence, not a proof.

// MARK: Dimensions

/// A matrix dimension: a number, a size named in the text (N, p) or an expression of them (p + 1).
public indirect enum MathDim: Hashable, Sendable, CustomStringConvertible {
    case constant(Int)
    case param(String)
    case sum(MathDim, MathDim)
    case difference(MathDim, MathDim)
    case product(MathDim, MathDim)

    public var description: String {
        switch self {
        case let .constant(n): String(n)
        case let .param(name): MathDim.displayName(name)
        case let .sum(a, b): "\(a)+\(b)"
        case let .difference(a, b): "\(a)−\(b)"
        case let .product(a, b): "\(a)\(b)"
        }
    }

    /// Inferred sizes are named after their symbol (“#X.r”); they read as plain letters.
    static func displayName(_ name: String) -> String { name.hasPrefix("#") ? "n" : MathNames.display(name) }

    public var params: Set<String> {
        switch self {
        case .constant: []
        case let .param(name): [name]
        case let .sum(a, b), let .difference(a, b), let .product(a, b): a.params.union(b.params)
        }
    }

    public func value(_ values: [String: Int]) -> Int? {
        switch self {
        case let .constant(n): return n
        case let .param(name): return values[name]
        case let .sum(a, b): guard let x = a.value(values), let y = b.value(values) else { return nil }; return x + y
        case let .difference(a, b): guard let x = a.value(values), let y = b.value(values) else { return nil }; return x - y
        case let .product(a, b): guard let x = a.value(values), let y = b.value(values) else { return nil }; return x * y
        }
    }

    /// A dimension written in a declaration: “N”, “p+1”, “2”, “n-1”, “2n”.
    public static func from(_ node: MathNode) -> MathDim? {
        switch node {
        case let .number(v) where v == v.rounded() && v >= 1 && v < 10_000: return .constant(Int(v))
        case let .symbol(name): return .param(name)
        case let .add(a, b): guard let x = from(a), let y = from(b) else { return nil }; return .sum(x, y)
        case let .subtract(a, b): guard let x = from(a), let y = from(b) else { return nil }; return .difference(x, y)
        case let .multiply(a, b): guard let x = from(a), let y = from(b) else { return nil }; return .product(x, y)
        default: return nil
        }
    }

    func substituting(_ map: [String: MathDim]) -> MathDim {
        switch self {
        case .constant: self
        case let .param(name): map[name] ?? self
        case let .sum(a, b): .sum(a.substituting(map), b.substituting(map))
        case let .difference(a, b): .difference(a.substituting(map), b.substituting(map))
        case let .product(a, b): .product(a.substituting(map), b.substituting(map))
        }
    }
}

// MARK: Types

public enum MathScalarDomain: Equatable, Sendable {
    case real, positive, nonnegative, integer
    case interval(Double, Double)
}

public enum MathMatrixStructure: Equatable, Sendable {
    case general, symmetric, positiveDefinite, positiveSemidefinite, diagonal
}

public enum MathType: Equatable, Sendable {
    case scalar(MathScalarDomain)
    case matrix(MathDim, MathDim, MathMatrixStructure)

    public var isScalar: Bool { if case .scalar = self { true } else { false } }

    /// “ℝ”, “ℝ^N”, “ℝ^{N×p}”, “λ > 0”-style text for the symbols strip.
    public var description: String {
        switch self {
        case let .scalar(domain):
            switch domain {
            case .real: return "a number"
            case .positive: return "a positive number"
            case .nonnegative: return "a number ≥ 0"
            case .integer: return "an integer"
            case let .interval(a, b): return "a number in [\(MathFormat.number(a)), \(MathFormat.number(b))]"
            }
        case let .matrix(r, c, structure):
            func grouped(_ d: MathDim) -> String { if case .sum = d { "(\(d))" } else if case .difference = d { "(\(d))" } else { d.description } }
            let shape = c == .constant(1) ? "vector of length \(r)" : "\(grouped(r))×\(grouped(c)) matrix"
            switch structure {
            case .general: return shape
            case .symmetric: return "symmetric " + shape
            case .positiveDefinite: return "positive definite " + shape
            case .positiveSemidefinite: return "positive semidefinite " + shape
            case .diagonal: return "diagonal " + shape
            }
        }
    }
}

/// A name defined in the derivation: “S := XᵀX”, “f(x) := x²”, “RSS(β) = (y − Xβ)ᵀ(y − Xβ)”.
public struct MathDefinition: Equatable, Sendable {
    public var parameters: [String]
    public var body: MathNode
    public var line: Int
    public init(parameters: [String], body: MathNode, line: Int) { self.parameters = parameters; self.body = body; self.line = line }
}

/// What a derivation has said so far: declarations, definitions and constraints between sizes.
public struct MathContext: Equatable, Sendable {
    public var declared: [String: MathType] = [:]
    /// x_i ∈ ℝ^p: an indexed family of vectors, by base name.
    public var families: [String: MathType] = [:]
    public var definitions: [String: MathDefinition] = [:]
    /// Constraints such as N > p, kept for sampling sizes.
    public var sizeConstraints: [MathSizeConstraint] = []
    public init() {}
}

public struct MathSizeConstraint: Equatable, Sendable {
    public var left: MathDim
    public var relation: MathRelation
    public var right: MathDim
}

enum MathEvalError: Error, Equatable {
    case unsupported(String)
    case shape(String)
    case domain(String)
    case singular(String)
}

// MARK: Definitions

enum MathExpansion {
    /// Replaces defined names by their definitions (S → XᵀX, f(t) → t² with t := argument).
    static func expand(_ node: MathNode, _ definitions: [String: MathDefinition], depth: Int = 0) throws -> MathNode {
        guard depth < 24 else { throw MathEvalError.unsupported("a definition refers to itself") }
        func e(_ n: MathNode) throws -> MathNode { try expand(n, definitions, depth: depth) }
        switch node {
        case let .symbol(name):
            // A name defined with parameters, written alone (“RSS” after “RSS(β) = …”), stands for its body.
            if let definition = definitions[name] { return try expand(definition.body, definitions, depth: depth + 1) }
            return node
        case let .apply(name, arguments):
            let expanded = try arguments.map(e)
            // f′(x), f″(x) of a defined f: its derivative at the argument.
            let primes = name.reversed().prefix { $0 == "′" }.count
            if primes > 0, let definition = definitions[String(name.dropLast(primes))], definition.parameters.count == 1, expanded.count == 1 {
                let point = "#\(definition.parameters[0])"
                let body = substitute(definition.body, [definition.parameters[0]: .symbol(point)])
                return try expand(.at(.derivative(body, variable: point, order: primes), variable: point, value: expanded[0]), definitions, depth: depth + 1)
            }
            if let definition = definitions[name] {
                if definition.parameters.isEmpty {
                    // A defined quantity written with its argument: “RSS(β)” after “RSS := …”.
                    return try expand(definition.body, definitions, depth: depth + 1)
                }
                guard definition.parameters.count == expanded.count else {
                    throw MathEvalError.unsupported("\(name) takes \(definition.parameters.count) argument\(definition.parameters.count == 1 ? "" : "s")")
                }
                let substituted = substitute(definition.body, Dictionary(uniqueKeysWithValues: zip(definition.parameters, expanded)))
                return try expand(substituted, definitions, depth: depth + 1)
            }
            return .apply(name, expanded)
        case let .indexed(name, indices): return .indexed(name, try indices.map(e))
        case let .add(a, b): return .add(try e(a), try e(b))
        case let .subtract(a, b): return .subtract(try e(a), try e(b))
        case let .multiply(a, b): return .multiply(try e(a), try e(b))
        case let .divide(a, b): return .divide(try e(a), try e(b))
        case let .negate(a): return .negate(try e(a))
        case let .power(a, b): return .power(try e(a), try e(b))
        case let .transpose(a): return .transpose(try e(a))
        case let .inverse(a): return .inverse(try e(a))
        case let .function(name, args): return .function(name, try args.map(e))
        case let .norm(a, p): return .norm(try e(a), p)
        case let .absolute(a): return .absolute(try e(a))
        case let .factorial(a): return .factorial(try e(a))
        case let .binomial(a, b): return .binomial(try e(a), try e(b))
        case let .sum(i, l, u, body):
            var inner = definitions; inner[i] = nil
            return .sum(index: i, lower: try l.map(e), upper: try u.map(e), body: try expand(body, inner, depth: depth))
        case let .product(i, l, u, body):
            var inner = definitions; inner[i] = nil
            return .product(index: i, lower: try l.map(e), upper: try u.map(e), body: try expand(body, inner, depth: depth))
        case let .derivative(body, variable, order):
            var inner = definitions; inner[variable] = nil
            return .derivative(try expand(body, inner, depth: depth), variable: variable, order: order)
        case let .integral(l, u, variable, body):
            var inner = definitions; inner[variable] = nil
            return .integral(lower: try e(l), upper: try e(u), variable: variable, body: try expand(body, inner, depth: depth))
        case let .matrix(rows): return .matrix(try rows.map { try $0.map(e) })
        case let .identity(size): return .identity(try size.map(e))
        case let .ones(size): return .ones(try size.map(e))
        case let .at(body, variable, value):
            var inner = definitions; inner[variable] = nil
            return .at(try expand(body, inner, depth: depth), variable: variable, value: try e(value))
        case .number, .unsupported: return node
        }
    }

    /// Substitutes expressions for symbols (not for bound variables of sums, derivatives and integrals inside).
    static func substitute(_ node: MathNode, _ map: [String: MathNode]) -> MathNode {
        if map.isEmpty { return node }
        func s(_ n: MathNode) -> MathNode { substitute(n, map) }
        switch node {
        case let .symbol(name): return map[name] ?? node
        case let .indexed(name, indices): return .indexed(name, indices.map(s))
        case let .add(a, b): return .add(s(a), s(b))
        case let .subtract(a, b): return .subtract(s(a), s(b))
        case let .multiply(a, b): return .multiply(s(a), s(b))
        case let .divide(a, b): return .divide(s(a), s(b))
        case let .negate(a): return .negate(s(a))
        case let .power(a, b): return .power(s(a), s(b))
        case let .transpose(a): return .transpose(s(a))
        case let .inverse(a): return .inverse(s(a))
        case let .function(name, args): return .function(name, args.map(s))
        case let .apply(name, args): return .apply(name, args.map(s))
        case let .norm(a, p): return .norm(s(a), p)
        case let .absolute(a): return .absolute(s(a))
        case let .factorial(a): return .factorial(s(a))
        case let .binomial(a, b): return .binomial(s(a), s(b))
        case let .sum(i, l, u, body):
            var inner = map; inner[i] = nil
            return .sum(index: i, lower: l.map(s), upper: u.map(s), body: substitute(body, inner))
        case let .product(i, l, u, body):
            var inner = map; inner[i] = nil
            return .product(index: i, lower: l.map(s), upper: u.map(s), body: substitute(body, inner))
        case let .derivative(body, variable, order):
            // d/dβ of an expression where β is replaced: differentiate the replaced expression, keeping β free inside.
            var inner = map; inner[variable] = nil
            return .derivative(substitute(body, inner), variable: variable, order: order)
        case let .integral(l, u, variable, body):
            var inner = map; inner[variable] = nil
            return .integral(lower: s(l), upper: s(u), variable: variable, body: substitute(body, inner))
        case let .matrix(rows): return .matrix(rows.map { $0.map(s) })
        case let .identity(size): return .identity(size.map(s))
        case let .ones(size): return .ones(size.map(s))
        case let .at(body, variable, value):
            var inner = map; inner[variable] = nil
            return .at(substitute(body, inner), variable: variable, value: s(value))
        case .number, .unsupported: return node
        }
    }

    /// Free symbols: those not bound by a sum, product, derivative or integral.
    static func freeSymbols(_ node: MathNode) -> Set<String> {
        switch node {
        case let .symbol(name): return [name]
        case let .indexed(name, indices): return indices.reduce(into: [name]) { $0.formUnion(freeSymbols($1)) }
        case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b), let .binomial(a, b):
            return freeSymbols(a).union(freeSymbols(b))
        case let .negate(a), let .transpose(a), let .inverse(a), let .absolute(a), let .factorial(a), let .norm(a, _): return freeSymbols(a)
        case let .function(_, args), let .apply(_, args): return args.reduce(into: []) { $0.formUnion(freeSymbols($1)) }
        case let .sum(i, l, u, body), let .product(i, l, u, body):
            var inner = freeSymbols(body); inner.remove(i)
            if let l { inner.formUnion(freeSymbols(l)) }
            if let u { inner.formUnion(freeSymbols(u)) }
            return inner
        case let .derivative(body, variable, _): return freeSymbols(body).union([variable])
        case let .integral(l, u, variable, body):
            var inner = freeSymbols(body); inner.remove(variable)
            return inner.union(freeSymbols(l)).union(freeSymbols(u))
        case let .matrix(rows): return rows.joined().reduce(into: []) { $0.formUnion(freeSymbols($1)) }
        case let .identity(size), let .ones(size): return size.map(freeSymbols) ?? []
        case let .at(body, variable, value):
            var inner = freeSymbols(body); inner.remove(variable)
            return inner.union(freeSymbols(value))
        case .number, .unsupported: return []
        }
    }

    static func containsCalculus(_ node: MathNode) -> (derivative: Int, integral: Bool) {
        var order = 0, integral = false
        func visit(_ n: MathNode) {
            switch n {
            case let .derivative(body, _, o): order = max(order, o); visit(body)
            case let .integral(l, u, _, body): integral = true; visit(l); visit(u); visit(body)
            case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b), let .binomial(a, b): visit(a); visit(b)
            case let .negate(a), let .transpose(a), let .inverse(a), let .absolute(a), let .factorial(a), let .norm(a, _): visit(a)
            case let .function(_, args), let .apply(_, args): args.forEach(visit)
            case let .sum(_, l, u, body), let .product(_, l, u, body): l.map(visit); u.map(visit); visit(body)
            case let .indexed(_, indices): indices.forEach(visit)
            case let .matrix(rows): rows.joined().forEach(visit)
            case let .identity(size), let .ones(size): size.map(visit)
            case let .at(body, _, value): visit(body); visit(value)
            case .number, .symbol, .unsupported: break
            }
        }
        visit(node)
        return (order, integral)
    }
}

// MARK: Shape inference

/// Sizes that must agree, merged as a union-find; a size named in a declaration keeps its name.
struct MathDimSolver: Equatable {
    private(set) var parent: [String: String] = [:]
    private(set) var fixed: [String: Int] = [:]
    /// A class defined by an expression of other sizes (an inferred size equal to p + 1).
    private(set) var defined: [String: MathDim] = [:]
    /// Sizes named in declarations or as bounds: two of them are never merged silently.
    var named: Set<String> = []
    var checks: [(MathDim, MathDim)] = []

    static func == (a: MathDimSolver, b: MathDimSolver) -> Bool { a.parent == b.parent && a.fixed == b.fixed && a.defined == b.defined }

    mutating func find(_ name: String) -> String {
        var root = name
        while let next = parent[root], next != root { root = next }
        var current = name
        while let next = parent[current], next != root { parent[current] = root; current = next }
        return root
    }

    func root(_ name: String) -> String {
        var root = name
        while let next = parent[root], next != root { root = next }
        return root
    }

    /// Records that two sizes are equal. Returns false when they cannot be (two different numbers, or two sizes
    /// the reader named differently, such as N and p).
    mutating func equate(_ a: MathDim, _ b: MathDim) -> Bool {
        let x = normalize(a), y = normalize(b)
        if x == y { return true }
        switch (x, y) {
        case let (.constant(m), .constant(n)): return m == n
        case let (.param(p), .constant(n)), let (.constant(n), .param(p)):
            let r = find(p)
            // A size the reader named (N) is not silently a number.
            if named.contains(r) { return false }
            if let existing = fixed[r] { return existing == n }
            if let expression = defined[r] { checks.append((expression, .constant(n))); return true }
            fixed[r] = n; return true
        case let (.param(p), .param(q)):
            let rp = find(p), rq = find(q)
            if rp == rq { return true }
            let namedP = named.contains(rp), namedQ = named.contains(rq)
            if namedP && namedQ { return false }
            // Keep the reader's name as the representative.
            let (keep, drop) = namedQ ? (rq, rp) : (rp, rq)
            if let a = fixed[drop] {
                if let b = fixed[keep], a != b { return false }
                if named.contains(keep) { checks.append((.param(keep), .constant(a))) } else { fixed[keep] = a }
            }
            if let expression = defined[drop] {
                if defined[keep] == nil, !named.contains(keep), fixed[keep] == nil { defined[keep] = expression } else { checks.append((.param(keep), expression)) }
            }
            parent[drop] = keep; fixed[drop] = nil; defined[drop] = nil
            return true
        case let (.param(p), expression), let (expression, .param(p)):
            let r = find(p)
            if named.contains(r) || fixed[r] != nil || defined[r] != nil { checks.append((.param(r), expression)); return true }
            if expression.params.contains(where: { find($0) == r }) { return false }
            defined[r] = expression; return true
        default:
            checks.append((x, y)); return true
        }
    }

    func normalize(_ dim: MathDim) -> MathDim {
        switch dim {
        case .constant: return dim
        case let .param(name):
            let r = root(name)
            if let n = fixed[r] { return .constant(n) }
            return .param(r)
        case let .sum(a, b): return .sum(normalize(a), normalize(b))
        case let .difference(a, b): return .difference(normalize(a), normalize(b))
        case let .product(a, b): return .product(normalize(a), normalize(b))
        }
    }

    /// Values for every size: named sizes and free ones drawn small (2…6), then checked against the constraints.
    func sample(_ params: Set<String>, constraints: [MathSizeConstraint], using rng: inout MathRandom) -> [String: Int]? {
        var roots = Set(params.map(root))
        for (a, b) in checks { roots.formUnion(a.params.map(root)); roots.formUnion(b.params.map(root)) }
        for constraint in constraints { roots.formUnion(constraint.left.params.map(root)); roots.formUnion(constraint.right.params.map(root)) }
        for _ in 0..<200 {
            var values: [String: Int] = [:]
            for r in roots where defined[r] == nil { values[r] = fixed[r] ?? Int.random(in: 2...6, using: &rng) }
            // Defined classes after the values they depend on.
            for _ in 0..<4 { for r in roots { if let expression = defined[r] { if let v = expression.substitutingRoots(self).value(values) { values[r] = v } } } }
            var all = values
            for p in params { all[p] = values[root(p)] }
            for r in roots { all[r] = values[r] }
            guard all.values.allSatisfy({ $0 >= 1 }) else { continue }
            let ok = checks.allSatisfy { a, b in
                guard let x = a.substitutingRoots(self).value(all), let y = b.substitutingRoots(self).value(all) else { return false }
                return x == y
            } && constraints.allSatisfy { c in
                guard let x = c.left.substitutingRoots(self).value(all), let y = c.right.substitutingRoots(self).value(all) else { return true }
                return c.relation.holds(Double(x), Double(y), tolerance: 0)
            }
            if ok { return all }
        }
        return nil
    }
}

extension MathDim {
    func substitutingRoots(_ solver: MathDimSolver) -> MathDim {
        switch self {
        case .constant: self
        case let .param(name): .param(solver.root(name))
        case let .sum(a, b): .sum(a.substitutingRoots(solver), b.substitutingRoots(solver))
        case let .difference(a, b): .difference(a.substitutingRoots(solver), b.substitutingRoots(solver))
        case let .product(a, b): .product(a.substitutingRoots(solver), b.substitutingRoots(solver))
        }
    }
}

/// The types of a derivation's symbols: declared, or inferred from how they are used (Xᵀ makes X a matrix,
/// Xβ with X of size N×p makes β a vector of length p, y − Xβ makes y one of length N).
public struct MathTyping: Equatable, Sendable {
    public var types: [String: MathType] = [:]
    /// Symbols whose type Lemma inferred (shown as such, and editable by declaring them).
    public var inferred: Set<String> = []
    /// Sizes named in the text (N, p) or bounds of sums, with the symbols that are sizes.
    public var sizeNames: Set<String> = []
    /// Problems found while typing, by the index of the expression that caused them.
    public var issues: [Int: String] = [:]
    /// Whether “I” stands for the identity matrix.
    public var identityIsMatrix = false
    var solver = MathDimSolver()
    var context = MathContext()

    public static func == (a: MathTyping, b: MathTyping) -> Bool { a.types == b.types && a.inferred == b.inferred && a.issues == b.issues }
}

struct MathShapeInference {
    enum NodeType: Equatable {
        case scalar
        case matrix(MathDim, MathDim)
        case unknown(String?)
        case unsupported(String)
    }

    enum Hint: Equatable {
        case sameShape(MathDim, MathDim)
        case rightOperand(rows: MathDim)
        case leftOperand(columns: MathDim)
        case matrixLike(square: Bool)
        case scalar
    }

    var context: MathContext
    var assigned: [String: MathType]
    var solver: MathDimSolver
    var hints: [String: [Hint]] = [:]
    var issues: [Int: String] = [:]
    var bound: Set<String> = []
    var identityIsMatrix: Bool
    var sizeNames: Set<String>
    var currentNode = 0
    var freshCounter = 0

    func type(of name: String) -> MathType? { context.declared[name] ?? assigned[name] }

    mutating func issue(_ message: String) { if issues[currentNode] == nil { issues[currentNode] = message } }

    mutating func fresh(_ label: String) -> MathDim {
        freshCounter += 1
        return .param("#\(label).\(freshCounter)")
    }

    func isMatrix(_ t: NodeType) -> (MathDim, MathDim)? {
        if case let .matrix(r, c) = t {
            // A 1×1 matrix is a number.
            if solver.normalize(r) == .constant(1), solver.normalize(c) == .constant(1) { return nil }
            return (r, c)
        }
        return nil
    }

    mutating func hint(_ t: NodeType, _ h: Hint) {
        if case let .unknown(name?) = t { hints[name, default: []].append(h) }
    }

    mutating func equate(_ a: MathDim, _ b: MathDim, _ message: String) -> Bool {
        if solver.equate(a, b) { return true }
        issue(message)
        return false
    }

    func shapeText(_ r: MathDim, _ c: MathDim) -> String {
        let r = solver.normalize(r), c = solver.normalize(c)
        return c == .constant(1) ? "a vector of length \(r)" : "\(r)×\(c)"
    }

    mutating func infer(_ node: MathNode) -> NodeType {
        switch node {
        case .number: return .scalar
        case let .symbol(name):
            if bound.contains(name) { return .scalar }
            if let t = type(of: name) {
                if case let .matrix(r, c, _) = t { return .matrix(r, c) }
                return .scalar
            }
            if name == "I" || name.hasPrefix("I_"), identityIsMatrix {
                if name.hasPrefix("I_"), let dim = MathDim.from((try? MathParser.expression(String(name.dropFirst(2)))) ?? .number(0)) { return .matrix(dim, dim) }
                let d = fresh("I")
                return .matrix(d, d)
            }
            if name == "π" || name == "e" || sizeNames.contains(name) { return .scalar }
            if name.hasSuffix("′"), let base = type(of: String(name.dropLast())), case let .matrix(r, c, _) = base { return .matrix(c, r) }
            return .unknown(name)
        case let .indexed(name, indices):
            for index in indices { _ = infer(index) }
            if let element = context.families[name] {
                if case let .matrix(r, c, _) = element { return .matrix(r, c) }
                return .scalar
            }
            return .scalar
        case let .add(a, b), let .subtract(a, b):
            return combineSum(infer(a), infer(b), zeroLeft: a == .number(0), zeroRight: b == .number(0))
        case let .multiply(a, b):
            return multiply(infer(a), infer(b))
        case let .divide(a, b):
            let ta = infer(a), tb = infer(b)
            if isMatrix(tb) != nil { issue("Dividing by a matrix: write its inverse"); return .unsupported("division by a matrix") }
            hint(tb, .scalar)
            return ta
        case let .negate(a): return infer(a)
        case let .power(a, b):
            let ta = infer(a), tb = infer(b)
            hint(tb, .scalar)
            if let (r, c) = isMatrix(ta) {
                let message = "Only a square matrix has powers; this one is \(shapeText(r, c))"
                _ = equate(r, c, message)
                return .matrix(r, r)
            }
            return ta
        case let .transpose(a):
            let ta = infer(a)
            hint(ta, .matrixLike(square: false))
            if case .multiply = a { hintFactors(a) }
            if case let .matrix(r, c) = ta { return .matrix(c, r) }
            if case .unknown = ta { return .unknown(nil) }
            return ta
        case let .inverse(a):
            let ta = infer(a)
            if case .multiply = a { hintFactors(a) }
            if let (r, c) = isMatrix(ta) {
                let message = "Only a square matrix has an inverse; this one is \(shapeText(r, c))"
                _ = equate(r, c, message)
                return .matrix(r, r)
            }
            if case let .unknown(name?) = ta {
                if let first = name.first, first.isUppercase { hints[name, default: []].append(.matrixLike(square: true)); return .unknown(nil) }
                hints[name, default: []].append(.scalar)
            }
            return ta
        case let .function(name, args):
            let types = args.map { infer($0) }
            switch name {
            case "tr", "det":
                if let first = args.first { hintFactors(first) }
                if let t = types.first {
                    hint(t, .matrixLike(square: true))
                    if let (r, c) = isMatrix(t) {
                        let message = "The \(name == "tr" ? "trace" : "determinant") needs a square matrix; this one is \(shapeText(r, c))"
                        _ = equate(r, c, message)
                    }
                }
                return .scalar
            case "diag":
                guard let t = types.first else { return .unsupported("diag") }
                hint(t, .matrixLike(square: false))
                if let (r, c) = isMatrix(t) {
                    if solver.normalize(c) == .constant(1) { return .matrix(r, r) }
                    return .matrix(r, .constant(1))
                }
                return .unknown(nil)
            default:
                for t in types {
                    hint(t, .scalar)
                    if isMatrix(t) != nil { issue("\\\(name) applies to numbers, not to a matrix or vector") }
                }
                return .scalar
            }
        case let .apply(_, args):
            for t in args.map({ infer($0) }) { hint(t, .scalar) }
            return .scalar
        case let .norm(a, _):
            let t = infer(a)
            hint(t, .matrixLike(square: false))
            return .scalar
        case let .absolute(a):
            let t = infer(a)
            if let (r, c) = isMatrix(t) { _ = equate(r, c, "|A| is a determinant here, which needs a square matrix") }
            hint(t, .scalar)
            return .scalar
        case let .factorial(a): hint(infer(a), .scalar); return .scalar
        case let .binomial(a, b): hint(infer(a), .scalar); hint(infer(b), .scalar); return .scalar
        case let .sum(index, lower, upper, body), let .product(index, lower, upper, body):
            if let lower { _ = infer(lower) }
            if let upper { _ = infer(upper) }
            let saved = bound
            bound.insert(index)
            defer { bound = saved }
            let t = infer(body)
            if case .product = node, isMatrix(t) != nil { issue("A product ∏ of matrices is not supported") }
            return t
        case let .derivative(body, variable, _):
            let saved = bound
            let variableType: NodeType = bound.contains(variable) ? .scalar : infer(.symbol(variable))
            bound = saved
            let t = infer(body)
            if let (vr, vc) = isMatrix(variableType) {
                if isMatrix(t) == nil {
                    return .matrix(vr, vc)
                }
                if let (br, bc) = isMatrix(t), solver.normalize(bc) == .constant(1), solver.normalize(vc) == .constant(1) { return .matrix(br, vr) }
                issue("Derivatives of matrices with respect to vectors are not supported")
                return .unsupported("derivative")
            }
            return t
        case let .integral(lower, upper, variable, body):
            _ = infer(lower); _ = infer(upper)
            let saved = bound
            bound.insert(variable)
            defer { bound = saved }
            let t = infer(body)
            if isMatrix(t) != nil { issue("Only integrals of numbers are supported") }
            return .scalar
        case let .matrix(rows):
            for row in rows { for entry in row { hint(infer(entry), .scalar) } }
            return .matrix(.constant(rows.count), .constant(rows.first?.count ?? 0))
        case let .identity(size):
            if let size, let dim = MathDim.from(size) { return .matrix(dim, dim) }
            let d = fresh("I")
            return .matrix(d, d)
        case let .ones(size):
            if let size, let dim = MathDim.from(size) { return .matrix(dim, .constant(1)) }
            return .matrix(fresh("1"), .constant(1))
        case let .at(body, variable, value):
            hint(infer(value), .scalar)
            let saved = bound
            bound.insert(variable)
            defer { bound = saved }
            return infer(body)
        case let .unsupported(what):
            return .unsupported(what)
        }
    }

    /// Uppercase letters inside a transposed, inverted or traced product are matrices: (AB)ᵀ, tr(AB).
    mutating func hintFactors(_ node: MathNode, square: Bool = false) {
        switch node {
        case let .multiply(a, b): hintFactors(a); hintFactors(b)
        case let .symbol(name) where name.first?.isUppercase == true && type(of: name) == nil && !bound.contains(name) && !sizeNames.contains(name):
            if !(identityIsMatrix && (name == "I" || name.hasPrefix("I_"))) { hints[name, default: []].append(.matrixLike(square: square)) }
        case let .transpose(a), let .inverse(a), let .negate(a): hintFactors(a)
        default: break
        }
    }

    mutating func combineSum(_ ta: NodeType, _ tb: NodeType, zeroLeft: Bool = false, zeroRight: Bool = false) -> NodeType {
        if case .unsupported = ta { return ta }
        if case .unsupported = tb { return tb }
        let ma = isMatrix(ta), mb = isMatrix(tb)
        switch (ma, mb) {
        case let ((r1, c1)?, (r2, c2)?):
            let message = "\(shapeText(r1, c1)) and \(shapeText(r2, c2)) have different sizes"
            if equate(r1, r2, message) { _ = equate(c1, c2, message) }
            return .matrix(r1, c1)
        case let ((r, c)?, nil):
            if case let .unknown(name) = tb { if let name { hints[name, default: []].append(.sameShape(r, c)) }; return .matrix(r, c) }
            if !zeroRight { issue("Adding a number to \(shapeText(r, c))") }
            return .matrix(r, c)
        case let (nil, (r, c)?):
            if case let .unknown(name) = ta { if let name { hints[name, default: []].append(.sameShape(r, c)) }; return .matrix(r, c) }
            if !zeroLeft { issue("Adding a number to \(shapeText(r, c))") }
            return .matrix(r, c)
        case (nil, nil):
            if case .unknown = ta { if case .scalar = tb { hint(ta, .scalar) }; return tb == .scalar ? .scalar : .unknown(nil) }
            if case .unknown = tb { if case .scalar = ta { hint(tb, .scalar) }; return .scalar }
            return .scalar
        }
    }

    mutating func multiply(_ ta: NodeType, _ tb: NodeType) -> NodeType {
        if case .unsupported = ta { return ta }
        if case .unsupported = tb { return tb }
        let ma = isMatrix(ta), mb = isMatrix(tb)
        switch (ma, mb) {
        case let ((r1, c1)?, (r2, c2)?):
            if !solver.equate(c1, r2) {
                issue("Cannot multiply \(shapeText(r1, c1)) by \(shapeText(r2, c2))")
                return .unsupported("shape")
            }
            return .matrix(r1, c2)
        case let ((r, c)?, nil):
            if case .unknown = tb { hint(tb, .rightOperand(rows: c)); _ = r; return .unknown(nil) }
            return .matrix(r, c)
        case let (nil, (r, c)?):
            if case .unknown = ta { hint(ta, .leftOperand(columns: r)); _ = c; return .unknown(nil) }
            return .matrix(r, c)
        case (nil, nil):
            if case .unknown = ta { return .unknown(nil) }
            if case .unknown = tb { return .unknown(nil) }
            return .scalar
        }
    }

    /// Types a relation between two expressions. Sides of known shapes are compared when the step is checked,
    /// so a wrong step reports its sizes instead of constraining them.
    mutating func relate(_ a: MathNode, _ b: MathNode) {
        let ta = infer(a), tb = infer(b)
        if case .unknown = ta, let (r, c) = isMatrix(tb) { hint(ta, .sameShape(r, c)) }
        if case .unknown = tb, let (r, c) = isMatrix(ta) { hint(tb, .sameShape(r, c)) }
        if case .unknown = ta, tb == .scalar { hint(ta, .scalar) }
        if case .unknown = tb, ta == .scalar { hint(tb, .scalar) }
    }
}

extension MathTyping {
    /// Types the expressions of a derivation together, so a size inferred on one line holds on every line.
    /// `relations` pairs expressions that are compared (sides of a step).
    static func infer(expressions: [MathNode], relations: [(Int, Int)], context: MathContext) -> MathTyping {
        var sizeNames = Set<String>()
        for type in context.declared.values { if case let .matrix(r, c, _) = type { sizeNames.formUnion(r.params); sizeNames.formUnion(c.params) } }
        for type in context.families.values { if case let .matrix(r, c, _) = type { sizeNames.formUnion(r.params); sizeNames.formUnion(c.params) } }
        for constraint in context.sizeConstraints { sizeNames.formUnion(constraint.left.params); sizeNames.formUnion(constraint.right.params) }
        // Bounds of sums are sizes too.
        func collectBounds(_ node: MathNode) {
            switch node {
            case let .sum(_, l, u, body), let .product(_, l, u, body):
                for bound in [l, u].compactMap({ $0 }) { if case let .symbol(name) = bound { sizeNames.insert(name) } else { collectBounds(bound) } }
                collectBounds(body)
            case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b), let .binomial(a, b): collectBounds(a); collectBounds(b)
            case let .negate(a), let .transpose(a), let .inverse(a), let .absolute(a), let .factorial(a), let .norm(a, _): collectBounds(a)
            case let .function(_, args), let .apply(_, args): args.forEach(collectBounds)
            case let .derivative(body, _, _): collectBounds(body)
            case let .integral(l, u, _, body): collectBounds(l); collectBounds(u); collectBounds(body)
            case let .identity(size?), let .ones(size?): if case let .symbol(name) = size { sizeNames.insert(name) }
            default: break
            }
        }
        expressions.forEach(collectBounds)
        sizeNames.subtract(context.declared.keys.filter { !(context.declared[$0]?.isScalar ?? true) })

        var assigned: [String: MathType] = [:]
        var identity = false
        var result = MathTyping()
        var freshCounter = 0
        for round in 0..<8 {
            var solver = MathDimSolver()
            solver.named = sizeNames
            var inference = MathShapeInference(context: context, assigned: assigned, solver: solver, identityIsMatrix: identity, sizeNames: sizeNames)
            inference.freshCounter = freshCounter
            defer { freshCounter = inference.freshCounter }
            for (index, expression) in expressions.enumerated() { inference.currentNode = index; _ = inference.infer(expression) }
            for (a, b) in relations {
                inference.currentNode = b
                inference.relate(expressions[a], expressions[b])
            }
            // Decide the types the hints imply, most specific first.
            var changed = false
            for (name, hints) in inference.hints.sorted(by: { $0.key < $1.key }) where assigned[name] == nil && context.declared[name] == nil {
                if identity, name == "I" || name.hasPrefix("I_") { continue }
                if let decided = MathTyping.decide(name, hints, solver: &inference) { assigned[name] = decided; changed = true }
            }
            let hasMatrix = assigned.contains { !$0.value.isScalar && $0.key != "I" && !$0.key.hasPrefix("I_") } || context.declared.values.contains { !$0.isScalar } || !context.families.isEmpty
            if hasMatrix, !identity {
                // With matrices about, an undeclared I is the identity.
                identity = true; changed = true
                assigned = assigned.filter { $0.key != "I" && !$0.key.hasPrefix("I_") }
            }
            result = MathTyping(types: [:], inferred: [], sizeNames: sizeNames, issues: inference.issues, identityIsMatrix: identity, solver: inference.solver, context: context)
            if !changed || round == 7 {
                // Everything still unknown is a number.
                var types = context.declared
                for expression in expressions {
                    for name in MathExpansion.freeSymbols(expression) where types[name] == nil && !sizeNames.contains(name) {
                        if name == "π" || name == "e" || (identity && (name == "I" || name.hasPrefix("I_"))) { continue }
                        if name.hasSuffix("′"), types[String(name.dropLast())].map({ !$0.isScalar }) == true { continue }
                        if context.families[name] != nil { continue }
                        types[name] = assigned[name] ?? .scalar(.real)
                        result.inferred.insert(name)
                    }
                }
                for (name, type) in assigned where types[name] == nil { types[name] = type; result.inferred.insert(name) }
                result.types = types
                return result
            }
        }
        return result
    }

    private static func decide(_ name: String, _ hints: [MathShapeInference.Hint], solver inference: inout MathShapeInference) -> MathType? {
        let lowercase = name.first.map { $0.isLowercase } ?? true
        for h in hints { if case let .sameShape(r, c) = h { return .matrix(r, c, .general) } }
        for h in hints { if case let .rightOperand(rows) = h { return lowercase ? .matrix(rows, .constant(1), .general) : .matrix(rows, inference.fresh(name), .general) } }
        // An uppercase letter written before a matrix is a matrix too (VA⁻¹U); a lowercase one is a number (λX).
        if !lowercase { for h in hints { if case let .leftOperand(columns) = h { return .matrix(inference.fresh(name), columns, .general) } } }
        let matrixLike = hints.compactMap { if case let .matrixLike(square) = $0 { square } else { nil } }
        if !matrixLike.isEmpty {
            let square = matrixLike.contains(true)
            if lowercase && !square {
                for h in hints { if case let .leftOperand(columns) = h { return .matrix(columns, .constant(1), .general) } }
                return .matrix(inference.fresh(name), .constant(1), .general)
            }
            for h in hints { if case let .leftOperand(columns) = h { return .matrix(inference.fresh(name), columns, .general) } }
            let r = inference.fresh(name)
            return .matrix(r, square ? r : inference.fresh(name), .general)
        }
        return nil
    }
}

// MARK: Random draws

/// A small deterministic generator, so a step's counterexample stays the same while the reader edits other lines.
public struct MathRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func normal() -> Double {
        let u = Double.random(in: Double.ulpOfOne..<1, using: &self), v = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
    public static func seed(_ text: String, _ salt: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash ^ UInt64(truncatingIfNeeded: salt &* 0x5851_F42D)
    }
}

/// An arbitrary smooth function standing for an undefined f, g or h.
struct MathRandomFunction {
    var terms: [(a0: Double, a1: Double, a2: Double, a3: Double, b: Double, c: Double)]
    var cross: Double

    init(arity: Int, rng: inout MathRandom) {
        terms = (0..<max(1, arity)).map { _ in (rng.normal(), rng.normal(), 0.5 * rng.normal(), rng.normal(), 0.5 + Double.random(in: 0..<1.5, using: &rng), rng.normal()) }
        cross = arity > 1 ? rng.normal() : 0
    }

    func callAsFunction(_ x: [Double]) -> Double {
        var value = 0.0
        for (t, xi) in zip(terms, x) { value += t.a0 + t.a1 * xi + t.a2 * xi * xi + t.a3 * sin(t.b * xi + t.c) }
        if x.count > 1 { value += cross * x[0] * x[1] }
        return value
    }
}

// MARK: Evaluation

/// One random draw of every symbol, consistent in size, and the evaluator of expressions in it.
final class MathWorld {
    let typing: MathTyping
    var dims: [String: Int]
    var values: [String: MathValue] = [:]
    var families: [String: [[Int]: MathValue]] = [:]
    var functions: [String: MathRandomFunction] = [:]
    var rng: MathRandom
    /// Retrying a draw with positive numbers when a logarithm or square root needs them.
    var positive = false
    /// Values fixed for this draw (a solved variable).
    var overrides: [String: MathValue] = [:]
    /// Lengths drawn for sums written without their range over undeclared families (“\\sum_i x_i”).
    var implicitRanges: [String: Int] = [:]

    init?(typing: MathTyping, seed: UInt64, positive: Bool = false) {
        self.typing = typing
        rng = MathRandom(seed: seed)
        self.positive = positive
        var params: Set<String> = typing.sizeNames
        for type in typing.types.values { if case let .matrix(r, c, _) = type { params.formUnion(r.params); params.formUnion(c.params) } }
        for type in typing.context.families.values { if case let .matrix(r, c, _) = type { params.formUnion(r.params); params.formUnion(c.params) } }
        guard let dims = typing.solver.sample(params, constraints: typing.context.sizeConstraints, using: &rng) else { return nil }
        self.dims = dims
    }

    func size(_ dim: MathDim) throws -> Int {
        let normalized = typing.solver.normalize(dim).substitutingRoots(typing.solver)
        guard let value = normalized.value(dims) ?? dim.value(dims), value >= 1 else { throw MathEvalError.shape("size \(dim) is undetermined") }
        return value
    }

    func drawScalar(_ domain: MathScalarDomain) -> Double {
        switch domain {
        case .real:
            if positive { return exp(0.8 * rng.normal()) }
            return Double.random(in: 0..<1, using: &rng) < 0.7 ? rng.normal() : Double.random(in: -3...3, using: &rng)
        case .positive, .nonnegative: return exp(0.8 * rng.normal())
        case .integer: return Double(Int.random(in: 1...6, using: &rng))
        case let .interval(a, b): return Double.random(in: min(a, b)...max(a, b), using: &rng)
        }
    }

    func drawMatrix(rows: Int, columns: Int, structure: MathMatrixStructure) -> MathMatrix {
        var m = MathMatrix(rows: rows, columns: columns, values: (0..<(rows * columns)).map { _ in rng.normal() })
        switch structure {
        case .general: break
        case .symmetric: if rows == columns { m = 0.5 * (m + m.transposed) }
        case .positiveDefinite:
            if rows == columns { m = (1 / Double(rows)) * (m * m.transposed) + MathMatrix.identity(rows, scale: 0.5) }
        case .positiveSemidefinite: if rows == columns { m = (1 / Double(rows)) * (m * m.transposed) }
        case .diagonal:
            var d = MathMatrix(rows: rows, columns: columns)
            for i in 0..<min(rows, columns) { d[i, i] = rng.normal() }
            m = d
        }
        return m
    }

    func draw(_ type: MathType) throws -> MathValue {
        switch type {
        case let .scalar(domain): return .scalar(drawScalar(domain))
        case let .matrix(r, c, structure): return .matrix(drawMatrix(rows: try size(r), columns: try size(c), structure: structure))
        }
    }

    func symbol(_ name: String, _ bindings: [String: MathValue]) throws -> MathValue {
        if let value = bindings[name] ?? overrides[name] ?? values[name] { return value }
        if let type = typing.types[name] {
            let value = try draw(type)
            values[name] = value
            return value
        }
        if typing.sizeNames.contains(name) || dims[name] != nil {
            let root = typing.solver.root(name)
            if let v = dims[name] ?? dims[root] { return .scalar(Double(v)) }
            let v = Double(Int.random(in: 2...6, using: &rng))
            dims[name] = Int(v)
            return .scalar(v)
        }
        if name == "π" { return .scalar(.pi) }
        if name == "e" { return .scalar(M_E) }
        if typing.identityIsMatrix, name == "I" { return .identity(1) }
        if typing.identityIsMatrix, name.hasPrefix("I_"), let size = MathDim.from((try? MathParser.expression(String(name.dropFirst(2)))) ?? .number(0)) {
            return .matrix(MathMatrix.identity(try self.size(size)))
        }
        if name.hasSuffix("′"), let base = typing.types[String(name.dropLast())], !base.isScalar {
            return try transpose(try symbol(String(name.dropLast()), bindings))
        }
        // A symbol the typing did not see (inside a derivative's body): a number.
        let value = MathValue.scalar(drawScalar(.real))
        values[name] = value
        return value
    }

    func integer(_ value: MathValue, _ what: String) throws -> Int {
        guard let v = value.scalar, abs(v - v.rounded()) < 1e-9, abs(v) < 1_000_000 else { throw MathEvalError.domain("\(what) must be a whole number") }
        return Int(v.rounded())
    }

    func evaluate(_ node: MathNode, _ bindings: [String: MathValue] = [:]) throws -> MathValue {
        switch node {
        case let .number(v): return .scalar(v)
        case let .symbol(name): return try symbol(name, bindings)
        case let .indexed(name, indices):
            let index = try indices.map { try integer(try evaluate($0, bindings), "An index") }
            if let element = typing.context.families[name] {
                if let value = families[name]?[index] { return value }
                let value = try draw(element)
                families[name, default: [:]][index] = value
                return value
            }
            if let type = typing.types[name], !type.isScalar, case let .matrix(m) = try symbol(name, bindings) {
                if index.count == 1, m.columns == 1 {
                    guard (1...m.rows).contains(index[0]) else { throw MathEvalError.domain("\(MathNames.display(name))_\(index[0]) is outside \(MathNames.display(name)) (length \(m.rows))") }
                    return .scalar(m[index[0] - 1, 0])
                }
                if index.count == 2 {
                    guard (1...m.rows).contains(index[0]), (1...m.columns).contains(index[1]) else { throw MathEvalError.domain("An index is outside \(MathNames.display(name)) (\(m.shapeText))") }
                    return .scalar(m[index[0] - 1, index[1] - 1])
                }
                if index.count == 1, m.rows == 1 { return .scalar(m[0, index[0] - 1]) }
                throw MathEvalError.unsupported("\(MathNames.display(name))_i of a matrix: write \(MathNames.display(name))_{ij}")
            }
            if let value = families[name]?[index] { return value }
            let value = MathValue.scalar(drawScalar(typing.types[name].flatMap { if case let .scalar(d) = $0 { d } else { nil } } ?? .real))
            families[name, default: [:]][index] = value
            return value
        case let .add(a, b): return try add(try evaluate(a, bindings), try evaluate(b, bindings))
        case let .subtract(a, b): return try add(try evaluate(a, bindings), try negate(try evaluate(b, bindings)))
        case let .multiply(a, b): return try multiply(try evaluate(a, bindings), try evaluate(b, bindings))
        case let .divide(a, b):
            let x = try evaluate(a, bindings)
            guard let y = try evaluate(b, bindings).scalar else { throw MathEvalError.shape("Dividing by a matrix") }
            if y == 0 { throw MathEvalError.domain("division by zero") }
            return try multiply(.scalar(1 / y), x)
        case let .negate(a): return try negate(try evaluate(a, bindings))
        case let .power(a, b):
            let base = try evaluate(a, bindings)
            guard let exponent = try evaluate(b, bindings).scalar else { throw MathEvalError.shape("An exponent must be a number") }
            switch base.normalized {
            case let .scalar(x):
                let v = pow(x, exponent)
                if v.isNaN { throw MathEvalError.domain("a power of a negative number") }
                return .scalar(v)
            case let .identity(c): return .identity(pow(c, exponent))
            case let .matrix(m):
                guard m.isSquare else { throw MathEvalError.shape("Only a square matrix has powers") }
                guard abs(exponent - exponent.rounded()) < 1e-12 else { throw MathEvalError.unsupported("fractional powers of matrices") }
                var k = Int(exponent.rounded())
                var factor = m
                if k < 0 { guard let inv = m.inverse else { throw MathEvalError.singular("a singular matrix") }; factor = inv; k = -k }
                var result = MathMatrix.identity(m.rows)
                for _ in 0..<k { result = result * factor }
                return .matrix(result)
            }
        case let .transpose(a): return try transpose(try evaluate(a, bindings))
        case let .inverse(a):
            switch try evaluate(a, bindings).normalized {
            case let .scalar(x):
                if x == 0 { throw MathEvalError.domain("division by zero") }
                return .scalar(1 / x)
            case let .identity(c): return .identity(1 / c)
            case let .matrix(m):
                guard m.isSquare else { throw MathEvalError.shape("Only a square matrix has an inverse (this one is \(m.shapeText))") }
                guard let inverse = m.inverse else { throw MathEvalError.singular("a singular matrix") }
                return .matrix(inverse)
            }
        case let .function(name, args): return try function(name, try args.map { try evaluate($0, bindings) })
        case let .apply(name, args):
            let values = try args.map { value -> Double in
                guard let v = try evaluate(value, bindings).scalar else { throw MathEvalError.unsupported("\(name) applied to a vector or matrix") }
                return v
            }
            let primes = name.reversed().prefix { $0 == "′" }.count
            let base = String(name.dropLast(primes))
            if base.count > 1 { throw MathEvalError.unsupported("\(base) is not defined here: define it with \(base)(…) := …") }
            let key = "\(base)/\(values.count)"
            if functions[key] == nil { functions[key] = MathRandomFunction(arity: values.count, rng: &rng) }
            let function = functions[key]!
            guard primes > 0 else { return .scalar(function(values)) }
            // f′(x), f″(x) of an arbitrary f: its derivative, by central differences.
            guard values.count == 1 else { throw MathEvalError.unsupported("primes on a function of several variables") }
            let x = values[0]
            if primes == 1 { let h = 1e-5 * max(1, abs(x)); return .scalar((function([x + h]) - function([x - h])) / (2 * h)) }
            let h = 1e-3 * max(1, abs(x))
            return .scalar((function([x + h]) - 2 * function([x]) + function([x - h])) / (h * h))
        case let .norm(a, p):
            switch try evaluate(a, bindings).normalized {
            case let .scalar(x): return .scalar(abs(x))
            case .identity: throw MathEvalError.shape("the norm of I needs its size")
            case let .matrix(m):
                if m.columns == 1 || m.rows == 1 {
                    switch p {
                    case 1?: return .scalar(m.values.reduce(0) { $0 + abs($1) })
                    case let q? where q.isInfinite: return .scalar(m.maxAbs)
                    case let q? where q != 2: return .scalar(pow(m.values.reduce(0) { $0 + pow(abs($1), q) }, 1 / q))
                    default: return .scalar(m.values.reduce(0) { $0 + $1 * $1 }.squareRoot())
                    }
                }
                switch p {
                case 1?: return .scalar((0..<m.columns).map { j in (0..<m.rows).reduce(0) { $0 + abs(m[$1, j]) } }.max() ?? 0)
                case let q? where q.isInfinite: return .scalar((0..<m.rows).map { i in (0..<m.columns).reduce(0) { $0 + abs(m[i, $1]) } }.max() ?? 0)
                case 2?: return .scalar(MathWorld.spectralNorm(m))
                default: return .scalar(m.values.reduce(0) { $0 + $1 * $1 }.squareRoot())
                }
            }
        case let .absolute(a):
            switch try evaluate(a, bindings).normalized {
            case let .scalar(x): return .scalar(abs(x))
            case let .matrix(m):
                guard m.isSquare else { throw MathEvalError.shape("|A| of a non-square matrix: write ‖A‖") }
                return .scalar(m.determinant)
            case .identity: return .scalar(1)
            }
        case let .factorial(a):
            guard let n = try evaluate(a, bindings).scalar else { throw MathEvalError.shape("a factorial of a matrix") }
            if n < 0, n == n.rounded() { throw MathEvalError.domain("a factorial of a negative integer") }
            return .scalar(tgamma(n + 1))
        case let .binomial(a, b):
            guard let n = try evaluate(a, bindings).scalar, let k = try evaluate(b, bindings).scalar else { throw MathEvalError.shape("a binomial of a matrix") }
            return .scalar(MathWorld.binomial(n, k))
        case let .sum(index, lower, upper, body), let .product(index, lower, upper, body):
            let isSum: Bool = if case .sum = node { true } else { false }
            let start = try lower.map { try integer(try evaluate($0, bindings), "A bound of the sum") } ?? 1
            let end: Int
            if let upper { end = try integer(try evaluate(upper, bindings), "A bound of the sum") }
            else { end = try impliedUpperBound(index: index, body: body, bindings: bindings) }
            guard end - start < 20_000 else { throw MathEvalError.unsupported("a sum with more than 20 000 terms") }
            var total: MathValue = .scalar(isSum ? 0 : 1)
            if end < start { return total }
            var first = true
            for i in start...end {
                var inner = bindings
                inner[index] = .scalar(Double(i))
                let term = try evaluate(body, inner)
                if first { total = term; first = false; continue }
                total = isSum ? try add(total, term) : try multiply(total, term)
            }
            return total
        case let .derivative(body, variable, order):
            return try derivative(body, variable: variable, order: order, bindings: bindings)
        case let .integral(lower, upper, variable, body):
            let a = try limit(lower, bindings), b = try limit(upper, bindings)
            return .scalar(try integrate(from: a, to: b) { x in
                var inner = bindings
                inner[variable] = .scalar(x)
                guard let v = try self.evaluate(body, inner).scalar else { throw MathEvalError.shape("Only integrals of numbers are supported") }
                return v
            })
        case let .matrix(rows):
            var m = MathMatrix(rows: rows.count, columns: rows.first?.count ?? 0)
            for (i, row) in rows.enumerated() {
                for (j, entry) in row.enumerated() {
                    guard let v = try evaluate(entry, bindings).scalar else { throw MathEvalError.unsupported("matrices of blocks") }
                    m[i, j] = v
                }
            }
            return .matrix(m)
        case let .identity(size):
            guard let size else { return .identity(1) }
            return .matrix(MathMatrix.identity(try integer(try evaluate(size, bindings), "The size of I")))
        case let .ones(size):
            guard let size else { throw MathEvalError.unsupported("𝟏 without its length: write \\mathbf{1}_N") }
            return .matrix(MathMatrix(rows: try integer(try evaluate(size, bindings), "The length of 𝟏"), columns: 1, repeating: 1))
        case let .at(body, variable, value):
            var inner = bindings
            inner[variable] = try evaluate(value, bindings)
            return try evaluate(body, inner)
        case let .unsupported(what):
            throw MathEvalError.unsupported(MathWorld.describe(unsupported: what))
        }
    }

    static func describe(unsupported what: String) -> String {
        switch what {
        case "expectation": "expectations cannot be checked by drawing numbers"
        case "probability": "probabilities cannot be checked by drawing numbers"
        case "variance": "variances cannot be checked by drawing numbers"
        case "infinity": "∞ only works as a bound of an integral"
        default: what
        }
    }

    private func limit(_ node: MathNode, _ bindings: [String: MathValue]) throws -> Double {
        switch node {
        case .unsupported("infinity"): return .infinity
        case .negate(.unsupported("infinity")): return -.infinity
        default:
            guard let v = try evaluate(node, bindings).scalar else { throw MathEvalError.shape("A bound of an integral must be a number") }
            return v
        }
    }

    /// The range of an index written without bounds (“\sum_i x_i”), from the length of what it indexes.
    private func impliedUpperBound(index: String, body: MathNode, bindings: [String: MathValue]) throws -> Int {
        var found: Int?
        func visit(_ n: MathNode) throws {
            switch n {
            case let .indexed(name, indices):
                for (position, i) in indices.enumerated() where i == .symbol(index) {
                    if let type = typing.types[name], case let .matrix(m) = try symbol(name, bindings) {
                        _ = type
                        found = position == 0 ? (m.columns == 1 || indices.count == 2 ? m.rows : m.columns) : m.columns
                    }
                }
                try indices.forEach(visit)
            case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b), let .binomial(a, b): try visit(a); try visit(b)
            case let .negate(a), let .transpose(a), let .inverse(a), let .absolute(a), let .factorial(a), let .norm(a, _): try visit(a)
            case let .function(_, args), let .apply(_, args): try args.forEach(visit)
            case let .sum(_, _, _, body), let .product(_, _, _, body), let .derivative(body, _, _), let .integral(_, _, _, body): try visit(body)
            default: break
            }
        }
        try visit(body)
        if let found { return found }
        // A family nobody declared: draw a length for this index, the same for every sum over it in this draw.
        if let drawn = implicitRanges[index] { return drawn }
        let drawn = Int.random(in: 2...6, using: &rng)
        implicitRanges[index] = drawn
        return drawn
    }

    // MARK: Operations

    func add(_ a: MathValue, _ b: MathValue) throws -> MathValue {
        switch (a.normalized, b.normalized) {
        case let (.scalar(x), .scalar(y)): return .scalar(x + y)
        case let (.matrix(m), .matrix(n)):
            guard m.rows == n.rows, m.columns == n.columns else { throw MathEvalError.shape("Adding \(m.shapeText) and \(n.shapeText)") }
            return .matrix(m + n)
        case let (.matrix(m), .identity(c)), let (.identity(c), .matrix(m)):
            guard m.isSquare else { throw MathEvalError.shape("Adding I to a \(m.shapeText) matrix") }
            return .matrix(m + MathMatrix.identity(m.rows, scale: c))
        case let (.identity(c), .identity(d)): return .identity(c + d)
        case let (.scalar(x), .matrix(m)), let (.matrix(m), .scalar(x)):
            if x == 0 { return .matrix(m) }
            throw MathEvalError.shape("Adding a number to a \(m.shapeText) matrix")
        case let (.scalar(x), .identity(c)), let (.identity(c), .scalar(x)):
            if x == 0 { return .identity(c) }
            throw MathEvalError.shape("Adding a number to I")
        }
    }

    func negate(_ a: MathValue) throws -> MathValue {
        switch a {
        case let .scalar(x): .scalar(-x)
        case let .matrix(m): .matrix(m.map { -$0 })
        case let .identity(c): .identity(-c)
        }
    }

    func multiply(_ a: MathValue, _ b: MathValue) throws -> MathValue {
        switch (a.normalized, b.normalized) {
        case let (.scalar(x), .scalar(y)): return .scalar(x * y)
        case let (.scalar(x), .matrix(m)), let (.matrix(m), .scalar(x)): return .matrix(x * m)
        case let (.scalar(x), .identity(c)), let (.identity(c), .scalar(x)): return .identity(x * c)
        case let (.identity(c), .matrix(m)), let (.matrix(m), .identity(c)): return .matrix(c * m)
        case let (.identity(c), .identity(d)): return .identity(c * d)
        case let (.matrix(m), .matrix(n)):
            guard m.columns == n.rows else { throw MathEvalError.shape("Multiplying \(m.shapeText) by \(n.shapeText)") }
            return .matrix(m * n)
        }
    }

    func transpose(_ a: MathValue) throws -> MathValue {
        switch a {
        case .scalar, .identity: a
        case let .matrix(m): .matrix(m.transposed)
        }
    }

    func function(_ name: String, _ args: [MathValue]) throws -> MathValue {
        func scalarArgument() throws -> Double {
            guard let first = args.first, let v = first.scalar else { throw MathEvalError.shape("\\\(name) applies to numbers") }
            return v
        }
        func checked(_ v: Double, _ what: String) throws -> MathValue {
            guard v.isFinite else { throw MathEvalError.domain(what) }
            return .scalar(v)
        }
        switch name {
        case "exp": return try checked(exp(try scalarArgument()), "an overflow")
        case "log":
            let x = try scalarArgument()
            guard x > 0 else { throw MathEvalError.domain("the logarithm of a number ≤ 0") }
            return .scalar(log(x))
        case "sqrt":
            let x = try scalarArgument()
            guard x >= 0 else { throw MathEvalError.domain("the square root of a negative number") }
            return .scalar(x.squareRoot())
        case "sin": return .scalar(sin(try scalarArgument()))
        case "cos": return .scalar(cos(try scalarArgument()))
        case "tan": return try checked(tan(try scalarArgument()), "tan at a pole")
        case "sec": return try checked(1 / cos(try scalarArgument()), "sec at a pole")
        case "csc": return try checked(1 / sin(try scalarArgument()), "csc at a pole")
        case "cot": return try checked(1 / tan(try scalarArgument()), "cot at a pole")
        case "sinh": return .scalar(sinh(try scalarArgument()))
        case "cosh": return .scalar(cosh(try scalarArgument()))
        case "tanh": return .scalar(tanh(try scalarArgument()))
        case "arcsin":
            let x = try scalarArgument(); guard abs(x) <= 1 else { throw MathEvalError.domain("arcsin outside [−1, 1]") }
            return .scalar(asin(x))
        case "arccos":
            let x = try scalarArgument(); guard abs(x) <= 1 else { throw MathEvalError.domain("arccos outside [−1, 1]") }
            return .scalar(acos(x))
        case "arctan": return .scalar(atan(try scalarArgument()))
        case "sign": let x = try scalarArgument(); return .scalar(x > 0 ? 1 : x < 0 ? -1 : 0)
        case "max", "min":
            let values = try args.map { value -> Double in
                guard let v = value.scalar else { throw MathEvalError.shape("\\\(name) of vectors is not supported") }
                return v
            }
            return .scalar(name == "max" ? values.max()! : values.min()!)
        case "tr":
            switch args.first?.normalized {
            case let .matrix(m)?: guard m.isSquare else { throw MathEvalError.shape("The trace needs a square matrix") }; return .scalar(m.trace)
            case let .scalar(x)?: return .scalar(x)
            default: throw MathEvalError.shape("the trace of I needs its size")
            }
        case "det":
            switch args.first?.normalized {
            case let .matrix(m)?: guard m.isSquare else { throw MathEvalError.shape("The determinant needs a square matrix") }; return .scalar(m.determinant)
            case let .scalar(x)?: return .scalar(x)
            default: return .scalar(1)
            }
        case "diag":
            guard case let .matrix(m)? = args.first?.normalized else { throw MathEvalError.shape("diag needs a vector or a matrix") }
            if m.columns == 1 || m.rows == 1 {
                let n = m.values.count
                var d = MathMatrix(rows: n, columns: n)
                for i in 0..<n { d[i, i] = m.values[i] }
                return .matrix(d)
            }
            let n = min(m.rows, m.columns)
            return .matrix(MathMatrix(rows: n, columns: 1, values: (0..<n).map { m[$0, $0] }))
        default: throw MathEvalError.unsupported("\\\(name)")
        }
    }

    static func binomial(_ n: Double, _ k: Double) -> Double {
        if k < 0 || (n >= 0 && k > n && n == n.rounded()) { return 0 }
        return exp(lgamma(n + 1) - lgamma(k + 1) - lgamma(n - k + 1)).rounded(toPlaces: n == n.rounded() && k == k.rounded())
    }

    static func spectralNorm(_ m: MathMatrix) -> Double {
        let gram = m.transposed * m
        var v = MathMatrix(rows: gram.rows, columns: 1, repeating: 1)
        var lambda = 0.0
        for _ in 0..<200 {
            let w = gram * v
            let norm = w.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if norm == 0 { return 0 }
            v = (1 / norm) * w
            if abs(norm - lambda) < 1e-14 * norm { lambda = norm; break }
            lambda = norm
        }
        return lambda.squareRoot()
    }

    // MARK: Calculus

    /// Central differences; a gradient for a vector variable, elementwise for a vector body.
    func derivative(_ body: MathNode, variable: String, order: Int, bindings: [String: MathValue]) throws -> MathValue {
        let point = try symbol(variable, bindings)
        func at(_ value: MathValue) throws -> MathValue {
            var inner = bindings
            inner[variable] = value
            return try evaluate(body, inner)
        }
        switch point.normalized {
        case let .scalar(x):
            if order == 2 {
                let h = 1e-3 * max(1, abs(x))
                let f0 = try at(.scalar(x)), fp = try at(.scalar(x + h)), fm = try at(.scalar(x - h))
                return try multiply(.scalar(1 / (h * h)), try add(try add(fp, fm), try multiply(.scalar(-2), f0)))
            }
            let h = 1e-5 * max(1, abs(x))
            let fp = try at(.scalar(x + h)), fm = try at(.scalar(x - h))
            return try multiply(.scalar(1 / (2 * h)), try add(fp, try negate(fm)))
        case let .matrix(m):
            guard order == 1 else { throw MathEvalError.unsupported("second derivatives with respect to a vector") }
            var columns: [MathValue] = []
            for k in 0..<m.values.count {
                let h = 1e-5 * max(1, abs(m.values[k]))
                var plus = m, minus = m
                plus.values[k] += h; minus.values[k] -= h
                let d = try multiply(.scalar(1 / (2 * h)), try add(try at(.matrix(plus)), try negate(try at(.matrix(minus)))))
                columns.append(d)
            }
            // A scalar body: the gradient, shaped like the variable.
            if columns.allSatisfy({ $0.scalar != nil }) {
                return .matrix(MathMatrix(rows: m.rows, columns: m.columns, values: columns.map { $0.scalar! }))
            }
            // A vector body and a vector variable: the Jacobian, one column per component of the variable.
            guard m.columns == 1, let first = columns.first, case let .matrix(f) = first.normalized, f.columns == 1 else {
                throw MathEvalError.unsupported("derivatives of matrices")
            }
            var jacobian = MathMatrix(rows: f.rows, columns: columns.count)
            for (j, column) in columns.enumerated() {
                guard case let .matrix(c) = column.normalized else { throw MathEvalError.unsupported("derivatives of matrices") }
                for i in 0..<f.rows { jacobian[i, j] = c[i, 0] }
            }
            return .matrix(jacobian)
        case .identity: throw MathEvalError.unsupported("a derivative with respect to I")
        }
    }

    /// Adaptive Gauss–Kronrod (7–15) quadrature, with infinite bounds mapped to finite ones.
    func integrate(from a: Double, to b: Double, _ f: @escaping (Double) throws -> Double) throws -> Double {
        if a == b { return 0 }
        if a > b { return -(try integrate(from: b, to: a, f)) }
        if a.isInfinite && b.isInfinite { return try integrate(from: -.infinity, to: 0, f) + integrate(from: 0, to: .infinity, f) }
        if b.isInfinite {
            return try MathWorld.kronrod(0, 1) { t in
                let x = a + t / (1 - t)
                return try f(x) / ((1 - t) * (1 - t))
            }
        }
        if a.isInfinite {
            return try MathWorld.kronrod(0, 1) { t in
                let x = b - (1 - t) / t
                return try f(x) / (t * t)
            }
        }
        return try MathWorld.kronrod(a, b, f)
    }

    private static let kronrodNodes: [Double] = [0.991455371120812639, 0.949107912342758525, 0.864864423359769073, 0.741531185599394440,
                                                 0.586087235467691130, 0.405845151377397167, 0.207784955007898468, 0]
    private static let kronrodWeights: [Double] = [0.022935322010529225, 0.063092092629978553, 0.104790010322250184, 0.140653259715525919,
                                                   0.169004726639267903, 0.190350578064785410, 0.204432940075298892, 0.209482141084727828]
    private static let gaussWeights: [Double] = [0.129484966168869693, 0.279705391489276668, 0.381830050505118945, 0.417959183673469388]

    static func kronrod(_ a: Double, _ b: Double, depth: Int = 0, _ f: @escaping (Double) throws -> Double) throws -> Double {
        let center = (a + b) / 2, half = (b - a) / 2
        var k15 = 0.0, g7 = 0.0
        for (i, x) in kronrodNodes.enumerated() {
            // The nodes avoid the endpoints, where a mapped infinite range is singular.
            let sum = x == 0 ? try f(center) : try f(center - half * x) + f(center + half * x)
            guard sum.isFinite else { throw MathEvalError.domain("the integrand is not finite on the interval") }
            k15 += kronrodWeights[i] * sum
            // Gauss nodes are every other Kronrod node, ending with the centre.
            if i % 2 == 1 { g7 += gaussWeights[i / 2] * sum }
        }
        k15 *= half; g7 *= half
        if abs(k15 - g7) <= max(1e-11, 1e-10 * abs(k15)) || depth >= 18 { return k15 }
        return try kronrod(a, center, depth: depth + 1, f) + kronrod(center, b, depth: depth + 1, f)
    }
}

extension Double {
    fileprivate func rounded(toPlaces integral: Bool) -> Double { integral ? rounded() : self }
}
