import DotNetMD
import CodeWriters

func toSwiftVisibility(_ visibility: DotNetMD.Visibility) -> SwiftVisibility {
    switch visibility {
        case .compilerControlled: return .fileprivate
        case .private: return .private
        case .assembly: return .internal
        case .familyAndAssembly: return .internal
        case .familyOrAssembly: return .public
        case .family: return .public
        case .public: return .public
    }
}

func toSwiftType(mscorlibType: BoundType, allowImplicitUnwrap: Bool = false) -> SwiftType? {
    guard mscorlibType.definition.namespace == "System" else { return nil }
    if mscorlibType.genericArgs.isEmpty {
        switch mscorlibType.definition.name {
            case "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64", "Double", "String", "Void":
                return .identifier(name: mscorlibType.definition.name)

            case "Boolean": return .bool
            case "SByte": return .int(bits: 8, signed: true)
            case "Byte": return .int(bits: 8, signed: false)
            case "IntPtr": return .int
            case "UIntPtr": return .uint
            case "Single": return .float
            case "Char": return .identifierChain("UTF16", "CodeUnit")
            case "Guid": return .identifierChain("Foundation", "UUID")
            case "Object": return .optional(wrapped: .any, implicitUnwrap: allowImplicitUnwrap)

            default: return nil
        }
    }
    else {
        return nil
    }
}

func toSwiftType(_ type: TypeNode, allowImplicitUnwrap: Bool = false) -> SwiftType {
    switch type {
        case let .bound(type):
            // Remap primitive types
            if type.definition.assembly is Mscorlib,
                let result = toSwiftType(mscorlibType: type, allowImplicitUnwrap: allowImplicitUnwrap) {
                return result
            }

            else if type.definition.assembly.name == "Windows",
                type.definition.assembly.version == .all255,
                type.definition.namespace == "Windows.Foundation",
                type.definition.name == "IReference`1"
                && type.genericArgs.count == 1 {
                return .optional(wrapped: toSwiftType(type.genericArgs[0]), implicitUnwrap: allowImplicitUnwrap)
            }

            let namePrefix = type.definition is InterfaceDefinition ? "Any" : ""
            let name = namePrefix + type.definition.nameWithoutGenericSuffix

            let genericArgs = type.genericArgs.map { toSwiftType($0) }
            var result: SwiftType = .identifier(name: name, genericArgs: genericArgs)
            if type.definition is InterfaceDefinition || type.definition is ClassDefinition
                && type.definition.fullName != "System.String" {
                result = .optional(wrapped: result, implicitUnwrap: allowImplicitUnwrap)
            }

            return result

        case let .array(element):
            return .optional(
                wrapped: .array(element: toSwiftType(element)),
                implicitUnwrap: allowImplicitUnwrap)

        case let .genericArg(param):
            return .identifier(name: param.name)

        default:
            fatalError()
    }
}

func toSwiftReturnType(_ type: TypeNode) -> SwiftType? {
    if case let .bound(type) = type,
        let mscorlib = type.definition.assembly as? Mscorlib,
        type.definition === mscorlib.specialTypes.void {
        return nil
    }
    return toSwiftType(type, allowImplicitUnwrap: true)
}

func toSwiftBaseType(_ type: BoundType?) -> SwiftType? {
    guard let type else { return nil }
    if let mscorlib = type.definition.assembly as? Mscorlib {
        guard type.definition !== mscorlib.specialTypes.object else { return nil }
    }
    guard type.definition.visibility == .public else { return nil }
    return .identifier(
        name: type.definition.nameWithoutGenericSuffix,
        genericArgs: type.genericArgs.map { toSwiftType($0) })
}

func toSwiftParameter(_ param: Param) -> SwiftParameter {
    .init(label: "_", name: param.name!, `inout`: param.isByRef, type: toSwiftType(param.type))
}

func toSwiftConstant(_ constant: Constant) -> String {
    switch constant {
        case let .boolean(value): return value ? "true" : "false"
        case let .int8(value): return String(value)
        case let .int16(value): return String(value)
        case let .int32(value): return String(value)
        case let .int64(value): return String(value)
        case let .uint8(value): return String(value)
        case let .uint16(value): return String(value)
        case let .uint32(value): return String(value)
        case let .uint64(value): return String(value)
        case .null: return "nil"
        default: fatalError("Not implemented")
    }
}