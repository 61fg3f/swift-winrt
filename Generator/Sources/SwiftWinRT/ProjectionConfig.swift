struct ProjectionConfig: Codable {
    var abiModule: String = "CWinRT"
    var modules: Dictionary<String, Module> = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        abiModule = try container.decodeIfPresent(String.self, forKey: .abiModule) ?? abiModule
        modules = try container.decodeIfPresent(Dictionary<String, Module>.self, forKey: .modules) ?? modules
    }

    struct Module: Codable {
        var assemblies: [String] = []
        var types: [String]? = nil
        var flattenNamespaces: Bool = false

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            assemblies = try container.decodeIfPresent([String].self, forKey: .assemblies) ?? assemblies
            types = try container.decodeIfPresent([String]?.self, forKey: .types) ?? types
            flattenNamespaces = try container.decodeIfPresent(Bool.self, forKey: .flattenNamespaces) ?? flattenNamespaces
        }
    }

    func getModule(assemblyName: String) -> (name: String, module: Module) {
        for (moduleName, module) in modules {
            if module.assemblies.contains(where: { Filter(pattern: $0).matches(assemblyName) }) {
                return (moduleName, module)
            }
        }

        var defaultModule = Module()
        defaultModule.assemblies.append(assemblyName)
        return (assemblyName, defaultModule)
    }
}