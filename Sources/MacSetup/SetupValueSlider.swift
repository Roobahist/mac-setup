import SwiftUI

/// Keep the track continuous: native stepped sliders draw a tick for every
/// increment on newer macOS versions. Quantize values without those marks.
struct SetupValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let title: String

    var body: some View {
        Slider(value: Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { proposed in
                let snapped = range.lowerBound + ((proposed - range.lowerBound) / step).rounded() * step
                value = min(max(snapped, range.lowerBound), range.upperBound)
            }), in: range)
            .accessibilityLabel(title)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(value + step, range.upperBound)
                case .decrement: value = max(value - step, range.lowerBound)
                @unknown default: break
                }
            }
            .onMoveCommand { direction in
                switch direction {
                case .right, .up: value = min(value + step, range.upperBound)
                case .left, .down: value = max(value - step, range.lowerBound)
                @unknown default: break
                }
            }
    }
}
