import Foundation

extension CapabilityRegistration {
    init(
        _ id: CapabilityID,
        jsName: String,
        title: String,
        summary: String,
        tags: [String],
        example: String,
        requiredPermissions: [PermissionKind] = [],
        requiredArguments: [String] = [],
        optionalArguments: [String] = [],
        argumentTypes: [String: CapabilityArgumentType] = [:],
        argumentHints: [String: String] = [:],
        resultSummary: String = "JSON value",
        handler: @escaping CapabilityHandler
    ) {
        self.init(
            jsNames: [jsName],
            descriptor: CapabilityDescriptor(
                id: id,
                title: title,
                summary: summary,
                tags: tags,
                example: example,
                requiredPermissions: requiredPermissions,
                requiredArguments: requiredArguments,
                optionalArguments: optionalArguments,
                argumentTypes: argumentTypes,
                argumentHints: argumentHints,
                resultSummary: resultSummary
            ),
            handler: handler
        )
    }
}
