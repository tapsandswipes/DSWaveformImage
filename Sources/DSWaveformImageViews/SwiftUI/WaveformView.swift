import DSWaveformImage
import SwiftUI

@available(iOS 15.0, macOS 12.0, *)
/// Renders and displays a waveform for the audio at `audioURL`.
public struct WaveformView<Content: View>: View {
    private let audioURL: URL
    private let configuration: Waveform.Configuration
    private let renderer: WaveformRenderer
    private let priority: TaskPriority
    private let content: (WaveformShape) -> Content

    @State private var samples: [Float] = []
    @State private var updateTask: Task<Void, Never>? {
        willSet {
            updateTask?.cancel()
        }
    }

    /**
     Creates a new WaveformView which displays a waveform for the audio at `audioURL`.

     - Parameters:
        - audioURL: The `URL` of the audio asset to be rendered.
        - configuration: The `Waveform.Configuration` to be used for rendering.
        - renderer: The `WaveformRenderer` implementation to be used. Defaults to `LinearWaveformRenderer`. Also comes with `CircularWaveformRenderer`.
        - priority: The `TaskPriority` used during analyzing. Defaults to `.userInitiated`.
        - content: ViewBuilder with the WaveformShape to be customized.
     */
    public init(
        audioURL: URL,
        configuration: Waveform.Configuration = Waveform.Configuration(damping: .init(percentage: 0.125, sides: .both)),
        renderer: WaveformRenderer = LinearWaveformRenderer(),
        priority: TaskPriority = .userInitiated,
        @ViewBuilder content: @escaping (WaveformShape) -> Content
    ) {
        self.audioURL = audioURL
        self.configuration = configuration
        self.renderer = renderer
        self.priority = priority
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            content(WaveformShape(samples: samples, configuration: configuration, renderer: renderer))
                .onAppear {
                    guard samples.isEmpty else { return }
                    update(size: geometry.size, url: audioURL, configuration: configuration)
                }
                .modifier(OnChange(of: geometry.size, action: { newValue in update(size: newValue, url: audioURL, configuration: configuration) }))
                .modifier(OnChange(of: audioURL, action: { newValue in update(size: geometry.size, url: audioURL, configuration: configuration) }))
                .modifier(OnChange(of: configuration, action: { newValue in update(size: geometry.size, url: audioURL, configuration: newValue) }))
        }
    }

    private func update(size: CGSize, url: URL, configuration: Waveform.Configuration) {
        updateTask = Task(priority: priority) {
            do {
                let samplesNeeded = Int(size.width * configuration.scale)
                let samples = try await WaveformAnalyzer().samples(fromAudioAt: url, count: samplesNeeded)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run { self.samples = samples }
            } catch is CancellationError {
                // no-op
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
}

public extension WaveformView {
    /**
     Creates a new WaveformView which displays a waveform for the audio at `audioURL`.

     - Parameters:
        - audioURL: The `URL` of the audio asset to be rendered.
        - configuration: The `Waveform.Configuration` to be used for rendering.
        - renderer: The `WaveformRenderer` implementation to be used. Defaults to `LinearWaveformRenderer`. Also comes with `CircularWaveformRenderer`.
        - priority: The `TaskPriority` used during analyzing. Defaults to `.userInitiated`.
     */
    init(
        audioURL: URL,
        configuration: Waveform.Configuration = Waveform.Configuration(damping: .init(percentage: 0.125, sides: .both)),
        renderer: WaveformRenderer = LinearWaveformRenderer(),
        priority: TaskPriority = .userInitiated
    ) where Content == AnyView {
        self.init(audioURL: audioURL, configuration: configuration, renderer: renderer, priority: priority) { shape in
            AnyView(DefaultShapeStyler().style(shape: shape, with: configuration))
        }
    }

    /**
     Creates a new WaveformView which displays a waveform for the audio at `audioURL`.

     - Parameters:
        - audioURL: The `URL` of the audio asset to be rendered.
        - configuration: The `Waveform.Configuration` to be used for rendering.
        - renderer: The `WaveformRenderer` implementation to be used. Defaults to `LinearWaveformRenderer`. Also comes with `CircularWaveformRenderer`.
        - priority: The `TaskPriority` used during analyzing. Defaults to `.userInitiated`.
        - placeholder: ViewBuilder for a placeholder view during the loading phase.
     */
    init<Placeholder: View>(
        audioURL: URL,
        configuration: Waveform.Configuration = Waveform.Configuration(damping: .init(percentage: 0.125, sides: .both)),
        renderer: WaveformRenderer = LinearWaveformRenderer(),
        priority: TaskPriority = .userInitiated,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Content == _ConditionalContent<Placeholder, AnyView> {
        self.init(audioURL: audioURL, configuration: configuration, renderer: renderer, priority: priority) { shape in
            if shape.isEmpty {
                placeholder()
            } else {
                AnyView(DefaultShapeStyler().style(shape: shape, with: configuration))
            }
        }
    }

    /**
     Creates a new WaveformView which displays a waveform for the audio at `audioURL`.

     - Parameters:
        - audioURL: The `URL` of the audio asset to be rendered.
        - configuration: The `Waveform.Configuration` to be used for rendering.
        - renderer: The `WaveformRenderer` implementation to be used. Defaults to `LinearWaveformRenderer`. Also comes with `CircularWaveformRenderer`.
        - priority: The `TaskPriority` used during analyzing. Defaults to `.userInitiated`.
        - content: ViewBuilder with the WaveformShape to be customized.
        - placeholder: ViewBuilder for a placeholder view during the loading phase.
     */
    init<Placeholder: View, ModifiedContent: View>(
        audioURL: URL,
        configuration: Waveform.Configuration = Waveform.Configuration(damping: .init(percentage: 0.125, sides: .both)),
        renderer: WaveformRenderer = LinearWaveformRenderer(),
        priority: TaskPriority = .userInitiated,
        @ViewBuilder content: @escaping (WaveformShape) -> ModifiedContent,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Content == _ConditionalContent<Placeholder, ModifiedContent> {
        self.init(audioURL: audioURL, configuration: configuration, renderer: renderer, priority: priority) { shape in
            if shape.isEmpty {
                placeholder()
            } else {
                content(shape)
            }
        }
    }
}
