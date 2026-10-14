import SwiftUI

/// Keep view-local state available to builds using Apple's standalone
/// Command Line Tools. On newer SDKs, writing @State selects a SwiftUI
/// macro whose implementation is not included in all CLT installations.
///
/// SwiftUI.State<Value> remains a public property wrapper. Using a separate
/// attribute name selects that wrapper directly, on both older and newer
/// SwiftUI SDKs, without shipping or loading an Xcode-only macro plugin.
///
/// State in these views holds small value types. Keep expensive reference
/// models in @StateObject rather than changing their initialization semantics.
typealias LocalViewState<Value> = SwiftUI.State<Value>
