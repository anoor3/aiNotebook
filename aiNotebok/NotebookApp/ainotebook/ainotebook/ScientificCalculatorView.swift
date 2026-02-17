import SwiftUI
import Darwin

struct ScientificCalculatorView: View {
    enum AngleMode: String, CaseIterable, Identifiable {
        case degrees = "Degrees"
        case radians = "Radians"

        var id: String { rawValue }
    }

    var onClose: () -> Void
    @StateObject private var engine = CalculatorEngine()
    @State private var angleMode: AngleMode = .degrees
    @GestureState private var dragOffset: CGSize = .zero
    @State private var storedOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var cardWidth: CGFloat = 360
    @State private var hasInitializedOffset = false
    @AppStorage("calculatorOffsetX") private var persistedOffsetX: Double = 0
    @AppStorage("calculatorOffsetY") private var persistedOffsetY: Double = 0
    @AppStorage("calculatorLastDisplay") private var persistedDisplay: String = "0"

    private let scientificColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        GeometryReader { proxy in
            let resolvedWidth = min(proxy.size.width - 32, 420)
            let needsScroll = proxy.size.height < 480

            Group {
                if needsScroll {
                    ScrollView(showsIndicators: false) {
                        calculatorCard(width: resolvedWidth)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    calculatorCard(width: resolvedWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            .offset(totalOffset)
            .gesture(dragGesture)
            .onAppear {
                updateContainer(proxy.size, resolvedWidth: resolvedWidth)
            }
            .onChange(of: proxy.size) { newSize in
                updateContainer(newSize, resolvedWidth: resolvedWidth)
            }
        }
        .background(Color.clear)
        .onAppear {
            engine.loadDisplay(persistedDisplay)
        }
        .onChange(of: engine.displayText) { newValue in
            persistedDisplay = newValue
        }
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(engine.expressionDisplay)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            if let preview = engine.previewDisplay {
                Text("= \(preview)")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }

            Text(engine.displayText)
                .font(.system(size: 30,
                              weight: engine.shouldHighlightResult ? .semibold : .medium,
                              design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func calculatorButton(for spec: CalculatorButtonSpec) -> some View {
        Button(action: { handleTap(spec.type) }) {
            Text(spec.title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundColor(spec.foreground)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(spec.background)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func handleTap(_ type: CalculatorButtonType) {
        switch type {
        case .digit(let value):
            engine.inputDigit(value)
        case .decimal:
            engine.inputDecimal()
        case .binary(let op):
            engine.setOperation(op)
        case .equals:
            engine.equals()
        case .clear:
            engine.clear()
        case .toggleSign:
            engine.toggleSign()
        case .percent:
            engine.percent()
        case .unary(let op):
            engine.handleUnarySelection(op, angleMode: angleMode)
        case .constant(let value):
            engine.insertConstant(value)
        }
    }

    @ViewBuilder
    private func calculatorCore(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            calculatorHeader

            display

            VStack(alignment: .leading, spacing: 4) {
                Text("Angle Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Angle Mode", selection: $angleMode) {
                    ForEach(AngleMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            LazyVGrid(columns: scientificColumns, spacing: 4) {
                ForEach(scientificButtons) { spec in
                    calculatorButton(for: spec)
                }
            }

            LazyVGrid(columns: keypadColumns, spacing: 4) {
                ForEach(keypadButtons) { spec in
                    calculatorButton(for: spec)
                        .gridCellColumns(spec.columnSpan)
                }
            }
        }
        .frame(maxWidth: width)
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.09), radius: 18, y: 10)
        )
    }

    private func calculatorCard(width: CGFloat) -> some View {
        calculatorCore(width: width)
            .overlay(alignment: .topTrailing) { controlButtons }
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            Button(action: dockToRight) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }
    }

    private var calculatorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "function")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.15, green: 0.3, blue: 0.65))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.93, green: 0.97, blue: 1.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.82, green: 0.9, blue: 0.98), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Calculator")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                Text("Scientific mode")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var totalOffset: CGSize {
        CGSize(width: storedOffset.width + dragOffset.width,
               height: storedOffset.height + dragOffset.height)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                storedOffset.width += value.translation.width
                storedOffset.height += value.translation.height
                persistedOffsetX = storedOffset.width
                persistedOffsetY = storedOffset.height
            }
    }

    private func dockOffset(for size: CGSize, cardWidth: CGFloat) -> CGSize {
        let horizontal = (size.width - cardWidth) / 2 - 20
        return CGSize(width: horizontal, height: storedOffset.height)
    }

    private func dockToRight() {
        guard containerSize != .zero else { return }
        let target = dockOffset(for: containerSize, cardWidth: cardWidth)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            storedOffset = target
        }
        persistedOffsetX = storedOffset.width
        persistedOffsetY = storedOffset.height
    }

    private func updateContainer(_ size: CGSize, resolvedWidth: CGFloat) {
        guard size != .zero else { return }
        containerSize = size
        cardWidth = resolvedWidth
        if !hasInitializedOffset {
            let persisted = CGSize(width: persistedOffsetX, height: persistedOffsetY)
            if persisted == .zero {
                storedOffset = dockOffset(for: size, cardWidth: resolvedWidth)
            } else {
                storedOffset = persisted
            }
            hasInitializedOffset = true
        }
    }

    private var scientificButtons: [CalculatorButtonSpec] {
        let accent = Color(red: 0.24, green: 0.41, blue: 0.94)
        let slate = Color(red: 0.93, green: 0.97, blue: 1.0)
        let slateText = Color(red: 0.16, green: 0.2, blue: 0.32)
        return [
            CalculatorButtonSpec(title: "sin", background: accent, type: .unary(.sin)),
            CalculatorButtonSpec(title: "cos", background: accent, type: .unary(.cos)),
            CalculatorButtonSpec(title: "tan", background: accent, type: .unary(.tan)),
            CalculatorButtonSpec(title: "ln", background: accent, type: .unary(.ln)),
            CalculatorButtonSpec(title: "log", background: accent, type: .unary(.log10)),
            CalculatorButtonSpec(title: "π", background: slate, foreground: slateText, type: .constant(.pi)),
            CalculatorButtonSpec(title: "e", background: slate, foreground: slateText, type: .constant(M_E)),
            CalculatorButtonSpec(title: "√x", background: slate, foreground: slateText, type: .unary(.squareRoot)),
            CalculatorButtonSpec(title: "x²", background: slate, foreground: slateText, type: .unary(.square)),
            CalculatorButtonSpec(title: "xʸ", background: slate, foreground: slateText, type: .binary(.power)),
            CalculatorButtonSpec(title: "1/x", background: slate, foreground: slateText, type: .unary(.reciprocal))
        ]
    }

    private var keypadButtons: [CalculatorButtonSpec] {
        let darkSurface = Color(red: 0.95, green: 0.95, blue: 0.96)
        let textDark = Color(red: 0.16, green: 0.2, blue: 0.32)
        let highlight = Color(red: 1.0, green: 0.62, blue: 0.12)
        let utility = Color(red: 0.89, green: 0.92, blue: 0.96)

        return [
            CalculatorButtonSpec(title: "AC", background: utility, foreground: textDark, type: .clear),
            CalculatorButtonSpec(title: "±", background: utility, foreground: textDark, type: .toggleSign),
            CalculatorButtonSpec(title: "%", background: utility, foreground: textDark, type: .percent),
            CalculatorButtonSpec(title: "÷", background: highlight, type: .binary(.division)),
            CalculatorButtonSpec(title: "7", background: darkSurface, foreground: textDark, type: .digit("7")),
            CalculatorButtonSpec(title: "8", background: darkSurface, foreground: textDark, type: .digit("8")),
            CalculatorButtonSpec(title: "9", background: darkSurface, foreground: textDark, type: .digit("9")),
            CalculatorButtonSpec(title: "×", background: highlight, type: .binary(.multiplication)),
            CalculatorButtonSpec(title: "4", background: darkSurface, foreground: textDark, type: .digit("4")),
            CalculatorButtonSpec(title: "5", background: darkSurface, foreground: textDark, type: .digit("5")),
            CalculatorButtonSpec(title: "6", background: darkSurface, foreground: textDark, type: .digit("6")),
            CalculatorButtonSpec(title: "−", background: highlight, type: .binary(.subtraction)),
            CalculatorButtonSpec(title: "1", background: darkSurface, foreground: textDark, type: .digit("1")),
            CalculatorButtonSpec(title: "2", background: darkSurface, foreground: textDark, type: .digit("2")),
            CalculatorButtonSpec(title: "3", background: darkSurface, foreground: textDark, type: .digit("3")),
            CalculatorButtonSpec(title: "+", background: highlight, type: .binary(.addition)),
            CalculatorButtonSpec(title: "0", background: darkSurface, foreground: textDark, type: .digit("0"), columnSpan: 2),
            CalculatorButtonSpec(title: ".", background: darkSurface, foreground: textDark, type: .decimal),
            CalculatorButtonSpec(title: "=", background: Color(red: 0.26, green: 0.86, blue: 0.52), type: .equals)
        ]
    }

}

private struct CalculatorButtonSpec: Identifiable {
    let id = UUID()
    let title: String
    let background: Color
    var foreground: Color = .white
    let type: CalculatorButtonType
    var columnSpan: Int = 1
}

private enum CalculatorButtonType {
    case digit(String)
    case decimal
    case binary(BinaryOperation)
    case equals
    case clear
    case toggleSign
    case percent
    case unary(UnaryOperation)
    case constant(Double)
}

private struct BinaryOperation {
    let symbol: String
    let function: (Double, Double) -> Double

    static let addition = BinaryOperation(symbol: "+", function: { $0 + $1 })
    static let subtraction = BinaryOperation(symbol: "−", function: { $0 - $1 })
    static let multiplication = BinaryOperation(symbol: "×", function: { $0 * $1 })
    static let division = BinaryOperation(symbol: "÷", function: { $1 == 0 ? Double.nan : $0 / $1 })
    static let power = BinaryOperation(symbol: "^", function: { pow($0, $1) })
}

private enum UnaryOperation {
    case sin, cos, tan
    case ln, log10
    case squareRoot
    case square
    case reciprocal

    var title: String {
        switch self {
        case .sin: return "sin"
        case .cos: return "cos"
        case .tan: return "tan"
        case .ln: return "ln"
        case .log10: return "log"
        case .squareRoot: return "√"
        case .square: return "sq"
        case .reciprocal: return "1/x"
        }
    }
}

private final class CalculatorEngine: ObservableObject {
    @Published var displayText: String = "0"
    @Published var pendingDescription: String?

    private var storedValue: Double?
    private var pendingOperation: BinaryOperation?
    private var isEnteringNumber = false
    private var didJustCalculate = false

    func inputDigit(_ digit: String) {
        if displayText == "Error" || (!isEnteringNumber && !didJustCalculate) {
            displayText = digit
        } else if !isEnteringNumber && didJustCalculate {
            displayText = digit
        } else if displayText == "0" || !isEnteringNumber {
            displayText = digit
        } else {
            displayText += digit
        }
        isEnteringNumber = true
        didJustCalculate = false
    }

    func inputDecimal() {
        guard displayText != "Error" else {
            displayText = "0."
            isEnteringNumber = true
            didJustCalculate = false
            return
        }

        if !isEnteringNumber {
            displayText = "0."
            isEnteringNumber = true
        } else if !displayText.contains(".") {
            displayText += "."
        }
    }

    func clear() {
        displayText = "0"
        pendingDescription = nil
        storedValue = nil
        pendingOperation = nil
        isEnteringNumber = false
        didJustCalculate = false
    }

    func toggleSign() {
        guard displayText != "Error" else { return }
        if displayText.hasPrefix("-") {
            displayText.removeFirst()
        } else if displayText != "0" {
            displayText = "-" + displayText
        }
    }

    func percent() {
        guard displayText != "Error" else { return }
        let value = currentValue / 100
        updateDisplay(value)
    }

    func setOperation(_ operation: BinaryOperation) {
        guard displayText != "Error" else { return }
        if isEnteringNumber {
            commitPendingOperation()
        }

        if storedValue == nil {
            storedValue = currentValue
        }

        pendingOperation = BinaryOperation(symbol: operation.symbol, function: operation.function)
        if let storedValue {
            pendingDescription = "\(format(storedValue)) \(operation.symbol)"
        }
        isEnteringNumber = false
        didJustCalculate = false
    }

    func equals() {
        guard let pendingOperation, let storedValue else { return }
        guard displayText != "Error" else { return }
        let result = pendingOperation.function(storedValue, currentValue)
        updateDisplay(result)
        self.storedValue = nil
        self.pendingOperation = nil
        pendingDescription = nil
        isEnteringNumber = false
        didJustCalculate = true
    }

    func handleUnarySelection(_ operation: UnaryOperation,
                              angleMode: ScientificCalculatorView.AngleMode) {
        applyUnary(operation, angleMode: angleMode)
    }

    private func applyUnary(_ operation: UnaryOperation,
                            angleMode: ScientificCalculatorView.AngleMode) {
        guard displayText != "Error" else { return }
        let value = currentValue
        let result: Double
        switch operation {
        case .sin:
            result = sin(adjustedAngle(value, mode: angleMode))
        case .cos:
            result = cos(adjustedAngle(value, mode: angleMode))
        case .tan:
            result = tan(adjustedAngle(value, mode: angleMode))
        case .ln:
            guard value > 0 else { setError(); return }
            result = log(value)
        case .log10:
            guard value > 0 else { setError(); return }
            result = log10(value)
        case .squareRoot:
            guard value >= 0 else { setError(); return }
            result = sqrt(value)
        case .square:
            result = value * value
        case .reciprocal:
            guard value != 0 else { setError(); return }
            result = 1 / value
        }
        updateDisplay(result)
        isEnteringNumber = false
    }

    func insertConstant(_ value: Double) {
        updateDisplay(value)
        isEnteringNumber = true
        didJustCalculate = false
    }

    private func commitPendingOperation() {
        let current = currentValue
        if let pendingOperation, let storedValue {
            let result = pendingOperation.function(storedValue, current)
            updateDisplay(result)
            self.storedValue = result
        } else {
            storedValue = current
        }
        isEnteringNumber = false
    }

    private var currentValue: Double {
        Double(displayText) ?? 0
    }

    private func updateDisplay(_ value: Double) {
        guard value.isFinite else {
            setError()
            return
        }
        displayText = format(value)
    }

    private func adjustedAngle(_ value: Double, mode: ScientificCalculatorView.AngleMode) -> Double {
        switch mode {
        case .degrees:
            return value * .pi / 180
        case .radians:
            return value
        }
    }

    private func format(_ value: Double) -> String {
        let formatter = CalculatorEngine.formatter
        if let text = formatter.string(from: NSNumber(value: value)) {
            return text
        }
        return String(value)
    }

    private func setError() {
        displayText = "Error"
        storedValue = nil
        pendingOperation = nil
        pendingDescription = nil
        isEnteringNumber = false
        didJustCalculate = false
    }

    var expressionDisplay: String {
        if let pendingOperation, let storedValue {
            let currentSegment: String
            if isEnteringNumber {
                currentSegment = displayText
            } else {
                currentSegment = ""
            }
            let base = "\(format(storedValue)) \(pendingOperation.symbol) \(currentSegment)"
            return base.trimmingCharacters(in: .whitespaces)
        }
        return displayText
    }

    var previewDisplay: String? {
        guard let pendingOperation, let storedValue, isEnteringNumber else { return nil }
        let result = pendingOperation.function(storedValue, currentValue)
        guard result.isFinite else { return nil }
        return format(result)
    }

    func loadDisplay(_ text: String) {
        displayText = text
        isEnteringNumber = text != "0"
        didJustCalculate = false
    }

    var shouldHighlightResult: Bool {
        didJustCalculate && pendingOperation == nil
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.minimumIntegerDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}
