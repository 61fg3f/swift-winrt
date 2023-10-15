import CodeWriters
import DotNetMetadata
import struct Foundation.UUID

extension SwiftAssemblyModuleFileWriter {
    func writeProjection(_ type: BoundType) throws {
        // TODO: Support generic interfaces/delegates

        if let interfaceDefinition = type.definition as? InterfaceDefinition {
            // Generic interfaces have no projection, only their instantiations do
            guard interfaceDefinition.genericArity == 0 else { return }
            try writeInterfaceProjection(interfaceDefinition, genericArgs: type.genericArgs)
        }
        else if let classDefinition = type.definition as? ClassDefinition {
            try writeClassProjection(classDefinition)
        }
        else if let enumDefinition = type.definition as? EnumDefinition {
            try writeEnumProjection(enumDefinition)
        }
    }

    private func writeInterfaceProjection(_ interfaceDefinition: InterfaceDefinition, genericArgs: [TypeNode] = []) throws {
        let interface = interfaceDefinition.bind(genericArgs: genericArgs)
        let projectionTypeName = try projection.toProjectionTypeName(interfaceDefinition)
        try sourceFileWriter.writeClass(
            visibility: SwiftProjection.toVisibility(interfaceDefinition.visibility),
            final: true,
            name: projectionTypeName,
            base: .identifier(
                name: "WinRTProjectionBase",
                genericArgs: [.identifier(name: projectionTypeName)]),
            protocolConformances: [
                .identifier(name: "WinRTProjection"),
                .identifier(name: try projection.toProtocolName(interfaceDefinition))
            ]) { writer throws in

            try writeWinRTProjectionConformance(type: interface, interface: interface, to: writer)
            try writeInterfaceMembersProjection(interface, to: writer)
        }
    }

    private func writeClassProjection(_ classDefinition: ClassDefinition) throws {
        let typeName = try projection.toTypeName(classDefinition)
        if let defaultInterface = try WinMD.getDefaultInterface(for: classDefinition) {
            try sourceFileWriter.writeClass(
                visibility: SwiftProjection.toVisibility(classDefinition.visibility),
                final: true,
                name: typeName,
                base: .identifier(
                    name: "WinRTProjectionBase",
                    genericArgs: [.identifier(name: typeName)]),
                protocolConformances: [.identifier(name: "WinRTProjection")]) { writer throws in

                try writeWinRTProjectionConformance(type: classDefinition.bind(), interface: defaultInterface, to: writer)
                try writeInterfaceMembersProjection(defaultInterface, to: writer)
            }
        }
        else {
            // Static class
            try sourceFileWriter.writeClass(
                visibility: SwiftProjection.toVisibility(classDefinition.visibility),
                final: true,
                name: typeName) { writer throws in

                writer.writeInit(visibility: .private) { writer in }
            }
        }
    }

    private func writeEnumProjection(_ enumDefinition: EnumDefinition) throws {
        sourceFileWriter.writeExtension(
            name: try projection.toTypeName(enumDefinition),
            protocolConformances: [SwiftType.identifierChain("WindowsRuntime", "EnumProjection")]) { writer in

            writer.writeTypeAlias(visibility: .public, name: "CEnum",
                target: projection.toAbiType(enumDefinition.bind(), referenceNullability: .none))
        }
    }

    private func writeWinRTProjectionConformance(type: BoundType, interface: BoundType, to writer: SwiftRecordBodyWriter) throws {
        writer.writeTypeAlias(visibility: .public, name: "SwiftValue",
            target: try projection.toType(type.asNode, referenceNullability: .none))
        writer.writeTypeAlias(visibility: .public, name: "CStruct",
            target: projection.toAbiType(interface, referenceNullability: .none))
        writer.writeTypeAlias(visibility: .public, name: "CVTableStruct",
            target: projection.toAbiVTableType(interface, referenceNullability: .none))

        writer.writeStoredProperty(visibility: .public, static: true, let: true, name: "iid",
            initializer: try Self.toIIDInitializer(WinMD.getGuid(interface)))
        // TODO: Support generic interfaces
        writer.writeStoredProperty(visibility: .public, static: true, let: true, name: "runtimeClassName",
            initializer: "\"\(type.definition.fullName)\"")
    }

    private static func toIIDInitializer(_ guid: WinMD.Guid) throws -> String {
        func toPrefixedPaddedHex<Value: UnsignedInteger & FixedWidthInteger>(
            _ value: Value,
            minimumLength: Int = MemoryLayout<Value>.size * 2) -> String {

            var hex = String(value, radix: 16, uppercase: true)
            if hex.count < minimumLength {
                hex.insert(contentsOf: String(repeating: "0", count: minimumLength - hex.count), at: hex.startIndex)
            }
            hex.insert(contentsOf: "0x", at: hex.startIndex)
            return hex
        }

        let arguments = [
            toPrefixedPaddedHex(guid.a),
            toPrefixedPaddedHex(guid.b),
            toPrefixedPaddedHex(guid.c),
            toPrefixedPaddedHex((UInt16(guid.d) << 8) | UInt16(guid.e)),
            toPrefixedPaddedHex(
                (UInt64(guid.f) << 40) | (UInt64(guid.g) << 32)
                | (UInt64(guid.h) << 24) | (UInt64(guid.i) << 16)
                | (UInt64(guid.j) << 8) | (UInt64(guid.k) << 0),
                minimumLength: 12)
        ]
        return "IID(\(arguments.joined(separator: ", ")))"
    }

    private func writeInterfaceMembersProjection(_ interface: BoundType, to writer: SwiftRecordBodyWriter) throws {
        // TODO: Support generic interfaces
        let interfaceDefinition = interface.definition
        for property in interfaceDefinition.properties {
            let typeProjection = try projection.getTypeProjection(property.type)

            if let getter = try property.getter, getter.isPublic {
                try writer.writeComputedProperty(
                    visibility: .public,
                    name: projection.toMemberName(property),
                    type: projection.toReturnType(property.type),
                    throws: true) { writer throws in

                    if let abiProjection = typeProjection.abi {
                        switch abiProjection {
                            case .identity:
                                writer.writeStatement("try _getter(_vtable.get_\(property.name))")
                            case .simple(abiType: _, let projectionType, inert: _):
                                writer.writeStatement("try _getter(_vtable.get_\(property.name), \(projectionType).self)")
                        }
                    }
                    else {
                        writer.writeNotImplemented()
                    }
                }
            }

            if let setter = try property.setter, setter.isPublic {
                try writer.writeFunc(
                    visibility: .public,
                    name: projection.toMemberName(property),
                    parameters: [SwiftParameter(
                        label: "_", name: "newValue",
                        type: projection.toType(property.type))],
                    throws: true) { writer throws in

                    if let abiProjection = typeProjection.abi {
                        switch abiProjection {
                            case .identity:
                                writer.writeStatement("try _setter(_vtable.get_\(property.name), newValue)")
                            case .simple(abiType: _, let projectionType, inert: _):
                                writer.writeStatement("try _getter(_vtable.get_\(property.name), newValue, \(projectionType).self)")
                        }
                    }
                    else {
                        writer.writeNotImplemented()
                    }
                }
            }
        }

        for method in interfaceDefinition.methods {
            guard method.isPublic, method.nameKind == .regular else { continue }

            try writer.writeFunc(
                visibility: .public,
                name: projection.toMemberName(method),
                parameters: method.params.map(projection.toParameter),
                throws: true,
                returnType: projection.toReturnTypeUnlessVoid(method.returnType)) { writer throws in

                writer.writeNotImplemented()
            }
        }
    }
}