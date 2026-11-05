//
//  InspectorHost.swift
//  MyWallpaperX
//

import AppKit

let inspectorHostAnimationDuration: Double = 0.24

enum InspectorHostUserInfoKey {
    static let module = "module"
    static let cardID = "cardID"
    static let title = "title"
    static let subtitle = "subtitle"
    static let preferredWidth = "preferredWidth"
    static let focusPolicy = "focusPolicy"
    static let chromeStyle = "chromeStyle"
    static let hostedView = "hostedView"
}

enum InspectorHostFocusPolicy: String {
    /// 打开时不主动抢占 first responder，保持浏览上下文原焦点不变。
    case preserveCurrentResponder
    /// 模块可在 inspectorDidPresent 后自行把焦点切到 inspector 内部控件。
    case moduleManaged
}

enum InspectorHostChromeStyle: String {
    case standard
    case infoPanel
}

struct InspectorCardToken: Hashable, Identifiable {
    let module: ModuleIdentifier
    let cardID: String

    var id: String {
        "\(module.rawValue):\(cardID)"
    }
}

struct InspectorHostRequest: Equatable {
    static let defaultPreferredWidth: CGFloat = 360
    static let minimumPreferredWidth: CGFloat = 300
    static let maximumPreferredWidth: CGFloat = 460

    let token: InspectorCardToken
    let title: String
    let subtitle: String?
    let preferredWidth: CGFloat
    let focusPolicy: InspectorHostFocusPolicy
    let chromeStyle: InspectorHostChromeStyle

    init(
        token: InspectorCardToken,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder,
        chromeStyle: InspectorHostChromeStyle = .standard
    ) {
        self.token = token
        self.title = title
        self.subtitle = subtitle
        self.preferredWidth = min(
            max(preferredWidth, Self.minimumPreferredWidth),
            Self.maximumPreferredWidth
        )
        self.focusPolicy = focusPolicy
        self.chromeStyle = chromeStyle
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let title = userInfo?[InspectorHostUserInfoKey.title] as? String
        else {
            return nil
        }

        let subtitle = userInfo?[InspectorHostUserInfoKey.subtitle] as? String
        let preferredWidthNumber = userInfo?[InspectorHostUserInfoKey.preferredWidth] as? NSNumber
        let preferredWidth = preferredWidthNumber.map { CGFloat(truncating: $0) } ?? Self.defaultPreferredWidth
        let focusPolicyRawValue = userInfo?[InspectorHostUserInfoKey.focusPolicy] as? String
        let focusPolicy = focusPolicyRawValue.flatMap(InspectorHostFocusPolicy.init(rawValue:))
            ?? .preserveCurrentResponder
        let chromeStyleRawValue = userInfo?[InspectorHostUserInfoKey.chromeStyle] as? String
        let chromeStyle = chromeStyleRawValue.flatMap(InspectorHostChromeStyle.init(rawValue:))
            ?? .standard

        self.init(
            token: InspectorCardToken(module: module, cardID: cardID),
            title: title,
            subtitle: subtitle,
            preferredWidth: preferredWidth,
            focusPolicy: focusPolicy,
            chromeStyle: chromeStyle
        )
    }

    var userInfo: [String: Any] {
        var result: [String: Any] = [
            InspectorHostUserInfoKey.module: token.module.rawValue,
            InspectorHostUserInfoKey.cardID: token.cardID,
            InspectorHostUserInfoKey.title: title,
            InspectorHostUserInfoKey.preferredWidth: preferredWidth,
            InspectorHostUserInfoKey.focusPolicy: focusPolicy.rawValue,
            InspectorHostUserInfoKey.chromeStyle: chromeStyle.rawValue
        ]
        if let subtitle, !subtitle.isEmpty {
            result[InspectorHostUserInfoKey.subtitle] = subtitle
        }
        return result
    }
}

struct InspectorHostDismissRequest {
    let module: ModuleIdentifier?
    let cardID: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo else {
            self.module = nil
            self.cardID = nil
            return
        }

        let moduleRawValue = userInfo[InspectorHostUserInfoKey.module] as? String
        let parsedModule = moduleRawValue.flatMap(ModuleIdentifier.init(rawValue:))
        let parsedCardID = userInfo[InspectorHostUserInfoKey.cardID] as? String
        guard parsedModule != nil || parsedCardID != nil else { return nil }

        module = parsedModule
        cardID = parsedCardID
    }

    func matches(_ token: InspectorCardToken) -> Bool {
        if let module, module != token.module {
            return false
        }
        if let cardID, cardID != token.cardID {
            return false
        }
        return true
    }
}

struct InspectorHostMountRequest {
    let token: InspectorCardToken
    let hostedView: NSView

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let hostedView = userInfo?[InspectorHostUserInfoKey.hostedView] as? NSView
        else {
            return nil
        }

        token = InspectorCardToken(module: module, cardID: cardID)
        self.hostedView = hostedView
    }
}

@MainActor
final class InspectorHostStore {
    private(set) var currentRequest: InspectorHostRequest?
    private(set) var hostedContentView: NSView?
    var onChange: (() -> Void)?

    var isPresented: Bool {
        currentRequest != nil
    }

    func present(_ request: InspectorHostRequest) {
        if currentRequest?.token != request.token {
            hostedContentView = nil
        }
        currentRequest = request
        onChange?()
    }

    func mountContent(_ request: InspectorHostMountRequest) {
        guard currentRequest?.token == request.token else { return }
        hostedContentView = request.hostedView
        onChange?()
    }


    func dismiss() {
        hostedContentView = nil
        currentRequest = nil
        onChange?()
    }

    func finalizeDismiss() {
        hostedContentView = nil
        currentRequest = nil
        onChange?()
    }
}
