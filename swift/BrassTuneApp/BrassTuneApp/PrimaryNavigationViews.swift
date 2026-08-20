import SwiftUI
import BrassTuneCore

struct PracticeHomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Today",
                title: "Practice",
                subtitle: "Choose a small next step and keep your momentum going."
            )

            if let checkpoint = model.currentWarmupCheckpoint, !checkpoint.completed {
                NavigationLink {
                    GuidedWarmupView()
                } label: {
                    BTCard(tint: BTTheme.surfaceWarm) {
                        Label("Resume warm-up", systemImage: "play.circle.fill")
                            .font(.title3.weight(.bold))
                        Text("Your five-minute warm-up is ready when you are.")
                            .font(.subheadline)
                            .foregroundStyle(BTTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.resumeWarmup")
            }

            BTCard {
                BTSectionHeader(title: "Practice routines", subtitle: "Start with a warm-up or a guided routine built for your instrument.")
                NavigationLink {
                    GuidedWarmupView()
                } label: {
                    Label {
                        Text(verbatim: NativeLocalization.string(model.currentWarmupCheckpoint == nil ? "Warm-up" : "Resume warm-up"))
                    } icon: {
                        Image(systemName: "wind")
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("practice.warmup")

                NavigationLink {
                    PlayAlongView(libraryExpanded: true)
                } label: {
                    Label("Guided Practice", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("practice.playAlong")

            }

            BTSectionHeader(title: "Practice tools", subtitle: "Open one focused tool in a single tap.")
            PracticeToolCard(title: "Metronome", detail: "Keep a steady pulse. No microphone needed.", systemImage: "metronome", identifier: "practice.metronome") { MetronomeView() }
            PracticeToolCard(title: "Drone & intervals", detail: "Hear a reference pitch and train your ear. Audio output required.", systemImage: "waveform", identifier: "practice.drone") { DroneIntervalView() }
            PracticeToolCard(title: "Scores", detail: "Import or open sheet music for your practice session.", systemImage: "music.note", identifier: "practice.sheetMusic") { ScorePracticeView() }

            PracticeHomeContextSection()
        }
        .navigationTitle("Practice")
        .accessibilityIdentifier("screen.practice")
    }
}

private struct PracticeToolCard<Destination: View>: View {
    let title: BTCopy
    let detail: BTCopy
    let systemImage: String
    let identifier: String
    @ViewBuilder let destination: () -> Destination
    @Environment(\.colorScheme) private var colorScheme

    private var readable: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        NavigationLink(destination: destination) {
            BTCard {
                HStack(alignment: .top, spacing: BTSpacing.md) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BTTheme.accent)
                        .frame(width: 30, height: 44)
                    VStack(alignment: .leading, spacing: BTSpacing.xs) {
                        Text(verbatim: title.resolved).font(.headline).foregroundStyle(readable)
                        Text(verbatim: detail.resolved).font(.subheadline).foregroundStyle(readable).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).padding(.top, BTSpacing.sm)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(PracticeToolCardButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

private struct PracticeToolCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

func uniqueReleaseVisibleShortcuts(_ shortcuts: [PracticeShortcut]) -> [PracticeShortcut] {
    var seen: Set<String> = []
    return shortcuts.filter { shortcut in
        guard NativeReleaseFeatureFlags.offlinePacks || shortcut.kind != .practicePack else { return false }
        return seen.insert(shortcut.id).inserted
    }
}

private struct PracticeHomeContextSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let shortcuts = uniqueReleaseVisibleShortcuts(
            model.practiceFeatures.favorites + model.practiceFeatures.recents
        )
        if !shortcuts.isEmpty {
            BTCard {
                BTSectionHeader(title: "Keep going")
                ForEach(Array(shortcuts.prefix(3))) { shortcut in
                    shortcutDestination(shortcut)
                }
            }
            .accessibilityIdentifier("practice.context")
        } else if let insight = model.weakTransitionInsight {
            BTCard {
                BTSectionHeader(title: "A useful focus", subtitle: .verbatim(insight.explanation))
            }
            .accessibilityIdentifier("practice.context")
        }
    }

    @ViewBuilder
    private func shortcutDestination(_ shortcut: PracticeShortcut) -> some View {
        switch shortcut.kind {
        case .playAlongExercise:
            NavigationLink {
                PlayAlongView(libraryExpanded: true)
            } label: {
                PracticeHomeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                if model.playAlongExercises.contains(where: { $0.id == shortcut.referenceID }) {
                    model.selectedPlayAlongExerciseID = shortcut.referenceID
                }
            })
        case .guidedWarmup:
            NavigationLink {
                GuidedWarmupView()
            } label: {
                PracticeHomeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        case .practicePack:
            EmptyView()
        case .drone:
            NavigationLink {
                DroneIntervalView()
            } label: {
                PracticeHomeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PracticeHomeShortcutRow: View {
    let shortcut: PracticeShortcut

    var body: some View {
        HStack(spacing: BTSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(BTTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(verbatim: shortcut.displayTitle)
                .font(.headline)
                .foregroundStyle(BTTheme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var systemImage: String {
        switch shortcut.kind {
        case .playAlongExercise: return "music.note.list"
        case .guidedWarmup: return "timer"
        case .practicePack: return "shippingbox"
        case .drone: return "waveform"
        }
    }
}

struct ScalesTabView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var root: ScaleRoot = .c
    @State private var scaleType: ScaleType = .major
    @State private var octaves: ScaleOctaves = .one
    @State private var direction: ScaleDirection = .ascending
    @State private var practiceMode: ScalePracticeMode = .microphone
    @State private var manualPracticeActive = false

    private var readable: Color { colorScheme == .dark ? .white : .black }

    private var selectedProfile: InstrumentProfile? {
        InstrumentProfiles.profile(for: model.selectedInstrumentId)
    }

    private var exercise: PlayAlongExercise? {
        PlayAlongExercise.scaleExercise(
            root: root,
            type: scaleType,
            direction: direction,
            octaves: octaves,
            profile: selectedProfile,
            id: "scale:\(model.selectedInstrumentId):\(root.rawValue):\(scaleType.rawValue):\(octaves.rawValue):\(direction.rawValue)"
        )
    }

    private var threeOctavesAvailable: Bool {
        PlayAlongExercise.isScaleAvailable(
            root: root,
            type: scaleType,
            octaves: .three,
            direction: direction,
            instrumentID: model.selectedInstrumentId
        )
    }

    var body: some View {
        Group {
            if manualPracticeActive, let exercise {
                ManualScalePracticeView(
                    exercise: exercise,
                    configuration: VisualScalePracticeConfiguration(
                        exerciseID: exercise.id,
                        instrumentID: model.selectedInstrumentId,
                        root: root,
                        type: scaleType,
                        octaves: octaves,
                        direction: direction,
                        tempoBPM: 72
                    ),
                    isPresented: $manualPracticeActive,
                    onCompleted: { completion in
                        _ = model.saveVisualScaleCompletion(completion)
                    }
                )
                    .toolbar(.hidden, for: .tabBar)
            } else if model.playAlongPhase != .idle {
                PlayAlongView()
                    .toolbar(.hidden, for: .tabBar)
            } else {
                scalePicker
            }
        }
        .navigationTitle("Scales")
        .accessibilityIdentifier("screen.scales")
    }

    private var scalePicker: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Play-Along",
                title: "Scales",
                subtitle: "Choose a key, preview the notes, then play at your own pace."
            )

            BTCard {
                Picker("Scale type", selection: $scaleType) {
                    ForEach(ScaleType.allCases, id: \.self) { type in
                        Text(verbatim: scaleTypeTitle(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("scales.typePicker")

                Picker("Key", selection: $root) {
                    ForEach(ScaleRoot.allCases, id: \.self) { root in
                        Text(verbatim: root.rawValue).tag(root)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("scales.keyPicker")

                Picker("Octaves", selection: $octaves) {
                    Text("One octave").tag(ScaleOctaves.one)
                    Text("Two octaves").tag(ScaleOctaves.two)
                    Text("Three octaves")
                        .tag(ScaleOctaves.three)
                        .disabled(!threeOctavesAvailable)
                }
                // A menu avoids clipped segment labels at large Dynamic Type
                // while keeping all three ranges easy to reach on compact phones.
                .pickerStyle(.menu)
                .accessibilityIdentifier("scales.octavesPicker")

                if !threeOctavesAvailable {
                    Text("Three octaves is unavailable for this key and instrument range.")
                        .font(.footnote)
                        .foregroundStyle(readable)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scales.threeOctavesUnavailable")
                }

                Picker("Direction", selection: $direction) {
                    ForEach(ScaleDirection.allCases, id: \.self) { direction in
                        Text(verbatim: scaleDirectionTitle(direction)).tag(direction)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("scales.directionPicker")
            }

            BTCard {
                BTSectionHeader(title: "Practice mode")
                Picker("Practice mode", selection: $practiceMode) {
                    ForEach(ScalePracticeMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scales.practiceMode")
                Text(verbatim: practiceMode.detail)
                    .font(.footnote)
                    .foregroundStyle(readable)
                    .fixedSize(horizontal: false, vertical: true)
                startScaleButton
            }

            if let exercise {
                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(title: .verbatim(exercise.displayTitle), subtitle: .verbatim(exercise.displayDetail))
                    Text(verbatim: NativeLocalization.isolate(exercise.writtenTargets.joined(separator: " · ")))
                        .font(.title3.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("scales.notePreview")
                    Text(verbatim: NativeLocalization.format("Written for %@.", instrumentDisplayName(model.selectedInstrumentId)))
                        .font(.footnote)
                        .foregroundStyle(readable)
                }
            } else {
                BTEmptyState(
                    title: "Scale unavailable",
                    message: octaves == .three
                        ? "This three-octave scale does not fit the selected instrument’s practical written range. Choose a shorter range or a different key."
                        : "Try a different range or direction.",
                    systemImage: "exclamationmark.triangle"
                )
            }

            if practiceMode == .microphone {
                if requiresNativeMicrophoneRecovery(model) {
                    MicrophoneRecoveryCard()
                    MicrophoneRecoveryActions {
                        guard let exercise else { return }
                        Task {
                            await model.startPlayAlong(exercise: exercise)
                        }
                    }
                    .accessibilityIdentifier("scales.microphoneRecoveryActions")

                    Button {
                        practiceMode = .visualTiming
                    } label: {
                        Label("Use visual timing instead", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("scales.useVisualTiming")
                } else {
                    Label("Mic-assisted mode listens and grades each note. If asked, allow microphone access before you begin.", systemImage: "mic")
                        .font(.footnote)
                        .foregroundStyle(readable)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scales.microphoneGuidance")
                }
            } else {
                Label("Visual timing advances through written note-and-octave targets without a microphone or grade; completed runs are saved as practice time.", systemImage: "eye")
                    .font(.title3.monospaced())
                    .foregroundStyle(readable)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scales.visualTimingGuidance")
            }
        }
    }

    private var startScaleButton: some View {
        Button {
            guard let exercise else { return }
            if practiceMode == .microphone {
                Task { await model.startPlayAlong(exercise: exercise) }
            } else {
                manualPracticeActive = true
            }
        } label: {
            Label {
                Text(verbatim: NativeLocalization.string(practiceMode == .microphone ? "Start mic-assisted scale" : "Start visual timing"))
            } icon: {
                Image(systemName: "play.fill")
            }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTPrimaryButtonStyle())
        .disabled(exercise == nil || model.playAlongStartInProgress)
        .accessibilityIdentifier("scales.start")
    }
}

private enum ScalePracticeMode: String, CaseIterable, Identifiable {
    case microphone
    case visualTiming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Mic assisted"
        case .visualTiming: return "Visual timing"
        }
    }

    var detail: String {
        switch self {
        case .microphone: return "BrassTune listens through the microphone and grades your held notes."
        case .visualTiming: return "A visual cue advances through the sequence. No microphone capture or score is created."
        }
    }
}

private struct ManualScalePracticeView: View {
    let exercise: PlayAlongExercise
    let configuration: VisualScalePracticeConfiguration
    @Binding var isPresented: Bool
    let onCompleted: (VisualScalePracticeCompletion) -> Void
    @State private var tempo = 72
    @State private var phase: VisualScalePracticePhase = .setup
    @State private var countInStartedAt: Date?
    @State private var noteStartedAt: Date?
    @State private var elapsedOnCurrentNote: TimeInterval = 0
    @State private var currentIndex = 0
    @State private var loopEnabled = false
    @State private var loopCount = 0
    @State private var practiceStartedAt: Date?

    private var secondsPerNote: TimeInterval { 120.0 / Double(tempo) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let countInElapsed = max(0, context.date.timeIntervalSince(countInStartedAt ?? context.date))
            let countInBeats = min(4, Int(countInElapsed / (60.0 / Double(tempo))))
            let liveNoteElapsed = phase == .running
                ? elapsedOnCurrentNote + max(0, context.date.timeIntervalSince(noteStartedAt ?? context.date))
                : elapsedOnCurrentNote
            let hasFinishedCurrentNote = phase == .running && liveNoteElapsed >= secondsPerNote

            BTScreen {
                BTPageHeader(
                    eyebrow: "Visual timing",
                    title: .verbatim(exercise.displayTitle),
                    subtitle: "A timed visual cue only. It does not listen or grade; a completed run is saved as practice time."
                )

                BTCard(tint: BTTheme.surfaceWarm) {
                    if phase == .countIn {
                        Text(verbatim: "Count-in: \(min(4, countInBeats + 1))")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(BTTheme.accent)
                            .frame(maxWidth: .infinity)
                        Text("Four beats before the first note")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    } else if phase == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BTTheme.success)
                            .frame(maxWidth: .infinity)
                        Text("Sequence complete")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label {
                            Text(verbatim: NativeLocalization.format(
                                "Current note %@",
                                exercise.writtenTargets[currentIndex]
                            ))
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .font(.headline)
                        .foregroundStyle(BTTheme.text)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                        Text(verbatim: NativeLocalization.isolate(exercise.writtenTargets[currentIndex]))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(BTTheme.accent)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(NativeLocalization.format(
                                "Current note %@",
                                exercise.writtenTargets[currentIndex]
                            ))
                            .accessibilityAddTraits(.isSelected)
                            .accessibilityIdentifier("scales.visualTiming.currentNote")
                        Text(verbatim: phase == .paused ? "Paused" : "Hold for two beats")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        ProgressView(value: min(liveNoteElapsed / secondsPerNote, 1))
                            .accessibilityLabel("Current note duration")
                    }

                    ProgressView(value: Double(phase == .completed ? exercise.writtenNotes.count : currentIndex), total: Double(exercise.writtenNotes.count))
                        .accessibilityLabel("Visual timing progress")
                        .accessibilityValue(NativeLocalization.format("%@ of %@", String(currentIndex + 1), String(exercise.writtenNotes.count)))
                }

                BTCard {
                    Stepper(value: $tempo, in: 40...180, step: 2) {
                        Text(verbatim: NativeLocalization.format("Tempo: %@ BPM", String(tempo)))
                    }
                    .disabled(phase == .running || phase == .countIn)
                    Toggle("Loop sequence", isOn: $loopEnabled)
                        .disabled(phase == .completed)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BTSpacing.sm) {
                        ForEach(Array(exercise.writtenTargets.enumerated()), id: \.offset) { index, target in
                            VStack(spacing: BTSpacing.xs) {
                                if index == currentIndex {
                                    Image(systemName: "arrowtriangle.up.fill")
                                        .font(.caption2.weight(.bold))
                                        .accessibilityHidden(true)
                                }
                                Text(verbatim: NativeLocalization.isolate(target))
                                    .font(.headline.monospaced())
                            }
                            .foregroundStyle(index == currentIndex ? BTTheme.accent : BTTheme.muted)
                            .padding(BTSpacing.sm)
                            .background(index == currentIndex ? BTTheme.accent.opacity(0.14) : .clear, in: Circle())
                            .overlay {
                                if index == currentIndex {
                                    Circle().stroke(BTTheme.accent, lineWidth: 2)
                                }
                            }
                            .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)

                HStack(spacing: BTSpacing.sm) {
                    Button {
                        primaryAction(at: context.date)
                    } label: {
                        Label {
                            Text(verbatim: NativeLocalization.string(primaryActionTitle))
                        } icon: {
                            Image(systemName: primaryActionIcon)
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                    .accessibilityIdentifier("scales.visualTiming.primary")

                    Button("Restart", systemImage: "arrow.counterclockwise") {
                        restart()
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("scales.visualTiming.restart")
                }

                Button {
                    isPresented = false
                } label: {
                    Label {
                        Text(verbatim: NativeLocalization.string(phase == .completed ? "Done" : "Exit without saving"))
                    } icon: {
                        Image(systemName: phase == .completed ? "checkmark" : "xmark")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("scales.visualTiming.finish")
            }
            .onChange(of: hasFinishedCurrentNote) { _, finished in
                guard finished else { return }
                advanceOrComplete(at: context.date)
            }
            .onChange(of: currentIndex) { _, index in
                guard phase == .running, UIAccessibility.isVoiceOverRunning else { return }
                let position = NativeLocalization.format(
                    "Step %@ of %@",
                    String(index + 1),
                    String(exercise.writtenTargets.count)
                )
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(position). \(NativeLocalization.isolate(exercise.writtenTargets[index]))"
                )
            }
            .onChange(of: countInBeats) { _, beats in
                guard phase == .countIn, beats >= 4 else { return }
                practiceStartedAt = context.date
                noteStartedAt = context.date
                phase = .running
            }
        }
        .accessibilityIdentifier("screen.scales.visualTiming")
    }

    private var primaryActionTitle: String {
        switch phase {
        case .setup: return "Start 4-beat count-in"
        case .countIn: return "Count-in running"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .completed: return "Practice again"
        }
    }

    private var primaryActionIcon: String {
        switch phase {
        case .running: return "pause.fill"
        case .paused: return "play.fill"
        case .completed: return "arrow.counterclockwise"
        case .setup, .countIn: return "play.fill"
        }
    }

    private func primaryAction(at now: Date) {
        switch phase {
        case .setup:
            countInStartedAt = now
            phase = .countIn
        case .running:
            elapsedOnCurrentNote += max(0, now.timeIntervalSince(noteStartedAt ?? now))
            noteStartedAt = nil
            phase = .paused
        case .paused:
            noteStartedAt = now
            phase = .running
        case .completed:
            restart()
        case .countIn:
            break
        }
    }

    private func advanceOrComplete(at now: Date) {
        elapsedOnCurrentNote = 0
        if currentIndex + 1 < exercise.writtenNotes.count {
            currentIndex += 1
            noteStartedAt = now
        } else if loopEnabled {
            currentIndex = 0
            noteStartedAt = now
            loopCount += 1
        } else {
            noteStartedAt = nil
            phase = .completed
            var completedConfiguration = configuration
            completedConfiguration.tempoBPM = tempo
            completedConfiguration.loopCount = loopCount
            onCompleted(
                VisualScalePracticeCompletion(
                    configuration: completedConfiguration,
                    startedAt: practiceStartedAt ?? now,
                    completedAt: now
                )
            )
        }
    }

    private func restart() {
        currentIndex = 0
        elapsedOnCurrentNote = 0
        countInStartedAt = nil
        noteStartedAt = nil
        practiceStartedAt = nil
        loopCount = 0
        phase = .setup
    }
}

private enum VisualScalePracticePhase: Equatable {
    case setup
    case countIn
    case running
    case paused
    case completed
}

private func scaleTypeTitle(_ type: ScaleType) -> String {
    switch type {
    case .major: return "Major"
    case .naturalMinor: return "Natural minor"
    case .harmonicMinor: return "Harmonic minor"
    case .melodicMinor: return "Melodic minor"
    case .chromatic: return "Chromatic"
    }
}

private func scaleDirectionTitle(_ direction: ScaleDirection) -> String {
    switch direction {
    case .ascending: return "Ascending"
    case .descending: return "Descending"
    case .both: return "Both"
    }
}

struct MoreView: View {
    @Binding var onboardingPresented: Bool

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "More",
                title: "Settings and support",
                subtitle: "Manage your account, instrument, data, and help."
            )

            BTCard {
                BTSectionHeader(title: "Account and app", subtitle: "Settings, privacy, and help in one place.")
                NavigationLink { SettingsView(onboardingPresented: $onboardingPresented) } label: {
                    MoreActionRow(title: "Settings", detail: "Account, instrument, audio, and appearance", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("more.settings")

                Divider()

                NavigationLink { LegalDetailView(kind: .privacy) } label: {
                    MoreActionRow(title: "Privacy", detail: "How local practice data is handled", systemImage: "hand.raised")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("more.privacy")

                Divider()

                NavigationLink { LegalDetailView(kind: .support) } label: {
                    MoreActionRow(title: "Support", detail: "Help with the tuner, scores, or your account", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("more.support")
            }
        }
        .navigationTitle("More")
        .accessibilityIdentifier("screen.more")
    }
}

private struct MoreActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    private var readable: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(alignment: .top, spacing: BTSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BTTheme.accent)
                .frame(width: 30, height: 44)
            VStack(alignment: .leading, spacing: BTSpacing.xs) {
                Text(verbatim: NativeLocalization.string(title)).font(.headline).foregroundStyle(readable)
                Text(verbatim: NativeLocalization.string(detail)).font(.subheadline).foregroundStyle(readable).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).padding(.top, BTSpacing.sm)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
