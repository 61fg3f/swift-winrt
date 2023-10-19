import CABI

public enum HResultProjection: ABIInertProjection {
    public typealias SwiftValue = HResult
    public typealias ABIValue = CABI.HRESULT

    public static var defaultAbiValue: ABIValue { CABI.S_OK }
    public static func toSwift(_ value: CABI.HRESULT) -> SwiftValue { HResult(value) }
    public static func toABI(_ value: HResult) throws -> CABI.HRESULT { value.value }
}