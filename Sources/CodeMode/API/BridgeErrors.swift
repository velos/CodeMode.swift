import Foundation

enum BridgeError: Error, Sendable {
    case invalidRequest(String)
    case invalidArguments(String)
    case capabilityDenied(CapabilityID)
    case capabilityKeyDenied(CodeModeCapabilityKey)
    case capabilityNotFound(String)
    case permissionDenied(PermissionKind)
    case customPermissionDenied(String)
    case unsupportedPlatform(String)
    case uiPresenterUnavailable
    case timeout(milliseconds: Int)
    case cancelled
    case pathViolation(String)
    case javascriptError(String)
    case nativeFailure(String)
}

extension BridgeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            return message
        case let .invalidArguments(message):
            return message
        case let .capabilityDenied(capability):
            return "Capability denied: \(capability.rawValue)"
        case let .capabilityKeyDenied(capabilityKey):
            return "Capability denied: \(capabilityKey.rawValue)"
        case let .capabilityNotFound(name):
            return "Capability not found: \(name)"
        case let .permissionDenied(permission):
            return "Permission denied: \(permission.rawValue)"
        case let .customPermissionDenied(message):
            return message
        case let .unsupportedPlatform(feature):
            return "Unsupported platform for \(feature)"
        case .uiPresenterUnavailable:
            return "System UI presenter is unavailable. Configure CodeModeConfiguration.systemUIPresenter before using UI-presenting helpers."
        case let .timeout(milliseconds):
            return "Execution timed out after \(milliseconds)ms"
        case .cancelled:
            return "Execution cancelled"
        case let .pathViolation(message):
            return message
        case let .javascriptError(message):
            return message
        case let .nativeFailure(message):
            return message
        }
    }

    var diagnosticCode: String {
        switch self {
        case .invalidRequest:
            return "INVALID_REQUEST"
        case .invalidArguments:
            return "INVALID_ARGUMENTS"
        case .capabilityDenied, .capabilityKeyDenied:
            return "CAPABILITY_DENIED"
        case .capabilityNotFound:
            return "CAPABILITY_NOT_FOUND"
        case .permissionDenied, .customPermissionDenied:
            return "PERMISSION_DENIED"
        case .unsupportedPlatform:
            return "UNSUPPORTED_PLATFORM"
        case .uiPresenterUnavailable:
            return "UI_PRESENTER_UNAVAILABLE"
        case .timeout:
            return "EXECUTION_TIMEOUT"
        case .cancelled:
            return "CANCELLED"
        case .pathViolation:
            return "PATH_POLICY_VIOLATION"
        case .javascriptError:
            return "JAVASCRIPT_ERROR"
        case .nativeFailure:
            return "NATIVE_FAILURE"
        }
    }
}
