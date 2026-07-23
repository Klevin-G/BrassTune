import SwiftUI
import UIKit

struct PracticeQuickStartCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            BTSectionHeader(
                title: "Quick start",
                subtitle: "Warm up, build an exercise, or open a saved practice plan. Everything here works offline."
            )

            NavigationLink {
                GuidedWarmupView()
            } label: {
                Label("Guided five-minute warm-up", systemImage: "timer")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.warmup")

            NavigationLink {
                CustomExerciseBuilderView()
            } label: {
                Label("Create a Play-Along exercise", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.builder")

            NavigationLink {
                PracticePacksView()
            } label: {
                Label("Offline practice packs", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.packs")

            if !model.practiceFeatures.favorites.isEmpty {
                Divider()
                shortcutSection(title: "Favorites", shortcuts: model.practiceFeatures.favorites.prefix(3).map { $0 })
            }
            if !model.practiceFeatures.recents.isEmpty {
                Divider()
                shortcutSection(title: "Recent practice", shortcuts: model.practiceFeatures.recents.prefix(3).map { $0 })
            }
        }
    }

    @ViewBuilder
    private func shortcutSection(title: String, shortcuts: [PracticeShortcut]) -> some View {
        Text(title)
            .font(.headline)
        ForEach(shortcuts) { shortcut in
            switch shortcut.kind {
            case .playAlongExercise:
                Button {
                    Task { _ = await model.launchShortcut(shortcut) }
                } label: {
                    ShortcutLabel(shortcut: shortcut)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.shortcut.\(shortcut.id)")
            case .guidedWarmup:
                NavigationLink {
                    GuidedWarmupView()
                } label: {
                    ShortcutLabel(shortcut: shortcut)
                }
                .buttonStyle(.plain)
            case .practicePack:
                NavigationLink {
                    PracticePacksView()
                } label: {
                    ShortcutLabel(shortcut: shortcut)
                }
                .buttonStyle(.plain)
            case .drone:
                NavigationLink {
                    DroneIntervalView()
                } label: {
                    ShortcutLabel(shortcut: shortcut)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ShortcutLabel: View {
    let shortcut: PracticeShortcut

    var body: some View {
        HStack(spacing: BTSpacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(BTTheme.accent)
                .frame(width: 28, height: 44)
            VStack(alignment: .leading, spacing: BTSpacing.xs) {
                Text(shortcut.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BTTheme.text)
                if let date = shortcut.lastStartedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(BTTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
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

struct SelectedExerciseFavoriteButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let exercise = model.selectedPlayAlongExercise
        let shortcut = PracticeShortcut(kind: .playAlongExercise, referenceID: exercise.id, title: exercise.title)
        Button {
            model.toggleFavorite(shortcut)
        } label: {
            Label(
                model.isFavorite(shortcut) ? "Remove from favorites" : "Add to favorites",
                systemImage: model.isFavorite(shortcut) ? "star.fill" : "star"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("playAlong.favorite")
    }
}

struct CustomExerciseBuilderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ["C"]
    @State private var errorMessage: String?

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Play-Along",
                title: "Build an exercise",
                subtitle: "Add 1–32 notes. Use the visible move buttons to put them in order."
            )

            BTCard {
                BTSectionHeader(title: "Name")
                TextField("Exercise name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: title) { _, value in
                        if value.count > 60 { title = String(value.prefix(60)) }
                    }
                    .accessibilityIdentifier("exerciseBuilder.title")
                Text(verbatim: NativeLocalization.isolate("\(title.count)/60"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BTTheme.muted)
            }

            BTCard {
                BTSectionHeader(
                    title: "Notes",
                    subtitle: NativeLocalization.format("%@ of 32", String(notes.count))
                )
                ForEach(notes.indices, id: \.self) { index in
                    HStack(spacing: BTSpacing.sm) {
                        Picker(NativeLocalization.format("Note %@", String(index + 1)), selection: Binding(
                            get: { notes[index] },
                            set: { notes[index] = $0 }
                        )) {
                            ForEach(SavedPlayAlongExercise.noteChoices, id: \.self) { note in
                                Text(verbatim: NativeLocalization.isolate(note)).tag(note)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            guard index > 0 else { return }
                            notes.swapAt(index, index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(index == 0)
                        .accessibilityLabel(NativeLocalization.format("Move note %@ up", String(index + 1)))

                        Button {
                            guard index < notes.count - 1 else { return }
                            notes.swapAt(index, index + 1)
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(index == notes.count - 1)
                        .accessibilityLabel(NativeLocalization.format("Move note %@ down", String(index + 1)))

                        Button(role: .destructive) {
                            guard notes.count > 1 else { return }
                            notes.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(notes.count == 1)
                        .accessibilityLabel(NativeLocalization.format("Delete note %@", String(index + 1)))
                    }
                    .accessibilityElement(children: .contain)
                }

                Button {
                    if notes.count < 32 { notes.append(notes.last ?? "C") }
                } label: {
                    Label("Add note", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(notes.count >= 32)
                .accessibilityIdentifier("exerciseBuilder.addNote")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("exerciseBuilder.error")
            }

            Button {
                switch model.saveCustomExercise(title: title, notes: notes) {
                case .success:
                    dismiss()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("Save exercise", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
            .accessibilityIdentifier("exerciseBuilder.save")
        }
        .navigationTitle("Exercise builder")
        .accessibilityIdentifier("screen.exerciseBuilder")
    }
}

struct GuidedWarmupView: View {
    @EnvironmentObject private var model: AppModel
    @AccessibilityFocusState private var stepFocused: Bool
    private let plan = GuidedWarmupPlan.fiveMinute

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let checkpoint = model.currentWarmupCheckpoint
            let elapsed = checkpoint?.elapsed(at: context.date, plan: plan) ?? 0
            let remaining = max(0, plan.durationSeconds - elapsed)
            let step = checkpoint?.currentStep(at: context.date, plan: plan) ?? plan.steps[0]
            let stepIndex = checkpoint?.currentStepIndex(at: context.date, plan: plan) ?? 0

            BTScreen {
                BTPageHeader(
                    eyebrow: "Warm-up",
                    title: plan.title,
                    subtitle: "A relaxed, resumable routine. Pause whenever you need to.",
                    trailing: timeLabel(remaining)
                )

                BTCard(tint: BTTheme.surfaceWarm) {
                    Text(NativeLocalization.format(
                        "Step %@ of %@",
                        String(stepIndex + 1),
                        String(plan.steps.count)
                    ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BTTheme.muted)
                    Text(step.title)
                        .font(.title2.weight(.bold))
                        .accessibilityFocused($stepFocused)
                        .accessibilityIdentifier("warmup.stepTitle")
                    Text(step.instruction)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: elapsed, total: plan.durationSeconds)
                        .accessibilityLabel("Warm-up progress")
                        .accessibilityValue(NativeLocalization.format(
                            "%@ of 300 seconds",
                            String(Int(elapsed))
                        ))
                }

                if checkpoint?.completed == true {
                    BTCard {
                        Label("Warm-up complete", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(BTTheme.success)
                        Button("Start another warm-up") {
                            model.resetWarmup()
                            model.startOrResumeWarmup(now: context.date)
                        }
                        .buttonStyle(BTPrimaryButtonStyle())
                    }
                } else if checkpoint?.isRunning == true {
                    Button {
                        model.pauseWarmup(now: context.date)
                    } label: {
                        Label("Pause warm-up", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("warmup.pause")
                } else {
                    Button {
                        model.startOrResumeWarmup(now: context.date)
                    } label: {
                        Label(checkpoint == nil ? "Start warm-up" : "Resume warm-up", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                    .accessibilityIdentifier("warmup.start")
                }

                if checkpoint != nil, checkpoint?.completed != true {
                    Button(role: .destructive) {
                        model.resetWarmup()
                    } label: {
                        Label("Restart from the beginning", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                }
            }
            .onChange(of: context.date) { _, date in
                model.advanceWarmup(now: date)
            }
            .onChange(of: stepIndex) { _, _ in
                stepFocused = true
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: "Step \(stepIndex + 1). \(step.title). \(step.instruction)")
                }
            }
        }
        .navigationTitle("Warm-up")
        .accessibilityIdentifier("screen.warmup")
        .onDisappear { model.pauseWarmup() }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MetronomePresetsCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var presetName = ""
    @State private var presetToRename: MetronomePreset?
    @State private var presetStatus: String?

    var body: some View {
        BTCard {
            BTSectionHeader(title: "Named presets", subtitle: "Save every tempo, meter, subdivision, sound, haptic, and volume setting together.")
            HStack(spacing: BTSpacing.sm) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("metronome.presetName")
                Button("Save") {
                    if model.saveMetronomePreset(name: presetName) {
                        presetStatus = "Preset saved."
                        presetName = ""
                    } else {
                        presetStatus = "Use a unique preset name."
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("metronome.savePreset")
            }

            ForEach(model.practiceFeatures.metronomePresets) { preset in
                VStack(alignment: .leading, spacing: BTSpacing.sm) {
                    Text(preset.name)
                        .font(.headline)
                    Text(NativeLocalization.format(
                        "%@ BPM · %@ · %@",
                        String(preset.settings.bpm),
                        preset.settings.meterLabel,
                        preset.settings.subdivision.title
                    ))
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    HStack {
                        Button("Apply") { model.applyMetronomePreset(id: preset.id) }
                            .buttonStyle(.bordered)
                        Button("Rename") {
                            presetToRename = preset
                        }
                        .buttonStyle(.bordered)
                        Button("Delete", role: .destructive) { model.deleteMetronomePreset(id: preset.id) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, BTSpacing.xs)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(NativeLocalization.format(
                    "%@, %@ beats per minute, %@, %@",
                    preset.name,
                    String(preset.settings.bpm),
                    preset.settings.meterLabel,
                    preset.settings.subdivision.title
                ))
            }

            if let presetStatus {
                Text(presetStatus)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .accessibilityIdentifier("metronome.presetStatus")
            }
        }
        .sheet(item: $presetToRename) { preset in
            RenameMetronomePresetView(preset: preset)
                .environmentObject(model)
        }
    }
}

private struct RenameMetronomePresetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let preset: MetronomePreset
    @State private var name: String
    @State private var error = false

    init(preset: MetronomePreset) {
        self.preset = preset
        _name = State(initialValue: preset.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Preset name", text: $name)
                if error { Text("Use a unique preset name.").foregroundStyle(.red) }
            }
            .navigationTitle("Rename preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.renameMetronomePreset(id: preset.id, name: name) { dismiss() } else { error = true }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct WeeklyGoalCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let goal = model.practiceFeatures.weeklyGoal
        let progress = model.weeklyPracticeProgress
        BTCard(tint: BTTheme.surfaceWarm) {
            BTSectionHeader(title: "This week's goal", subtitle: "A new week starts using your device's calendar and time zone.")
            ProgressView(value: Double(progress.minutes), total: Double(goal.targetMinutes))
                .accessibilityLabel("Weekly practice minutes")
                .accessibilityValue(NativeLocalization.format(
                    "%@ of %@ minutes",
                    String(progress.minutes),
                    String(goal.targetMinutes)
                ))
            Text(NativeLocalization.format(
                "%@ of %@ minutes · %@ of %@ sessions",
                String(progress.minutes),
                String(goal.targetMinutes),
                String(progress.sessionCount),
                String(goal.targetSessions)
            ))
                .font(.headline.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Stepper("Goal: \(goal.targetMinutes) minutes", value: Binding(
                get: { model.practiceFeatures.weeklyGoal.targetMinutes },
                set: { model.updateWeeklyGoal(minutes: $0, sessions: model.practiceFeatures.weeklyGoal.targetSessions) }
            ), in: 5...1_000, step: 5)
            .accessibilityIdentifier("progress.goalMinutes")
            Stepper("Goal: \(goal.targetSessions) sessions", value: Binding(
                get: { model.practiceFeatures.weeklyGoal.targetSessions },
                set: { model.updateWeeklyGoal(minutes: model.practiceFeatures.weeklyGoal.targetMinutes, sessions: $0) }
            ), in: 1...21)
            .accessibilityIdentifier("progress.goalSessions")
        }
        .accessibilityIdentifier("progress.weeklyGoal")
    }
}

struct WeakTransitionCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTCard {
            if let insight = model.weakTransitionInsight {
                BTSectionHeader(title: "Weak-transition drill", subtitle: insight.explanation)
                Text(insight.exercise.writtenNotes.joined(separator: "  "))
                    .font(.title3.monospaced().weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.startPlayAlong(exerciseID: insight.exercise.id) }
                } label: {
                    Label("Start personal drill", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("progress.startWeakTransition")
            } else {
                BTSectionHeader(
                    title: "Weak-transition drill",
                    subtitle: "Complete Play-Along exercises until the same note transition has at least three attempts. BrassTune will then build a focused drill."
                )
                .accessibilityIdentifier("progress.weakTransitionInsufficient")
            }
        }
        .accessibilityIdentifier("progress.weakTransition")
    }
}

struct PracticeReflectionCard: View {
    @EnvironmentObject private var model: AppModel
    let sessionID: PracticeSession.ID
    @State private var mood: PracticeReflectionMood = .focused
    @State private var note = ""
    @State private var saved = false

    var body: some View {
        BTCard {
            BTSectionHeader(title: "Short reflection", subtitle: "Save one quick thought for your next practice.")
            Picker("How did it feel?", selection: $mood) {
                ForEach(PracticeReflectionMood.allCases) { mood in
                    Text(mood.title).tag(mood)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reflection.mood")
            TextField("What should you remember?", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("reflection.note")
            Text(verbatim: NativeLocalization.isolate("\(note.count)/280"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(note.count > 280 ? BTTheme.danger : BTTheme.muted)
            Button(saved ? "Saved" : "Save reflection") {
                model.saveReflection(sessionID: sessionID, mood: mood, note: note)
                saved = true
            }
            .buttonStyle(.bordered)
            .disabled(note.count > 280)
            .accessibilityIdentifier("reflection.save")
            if model.reflection(for: sessionID) != nil {
                Button(role: .destructive) {
                    model.deleteReflection(sessionID: sessionID)
                    mood = .focused
                    note = ""
                    saved = false
                } label: {
                    Label("Delete reflection", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reflection.delete")
            }
        }
        .onAppear {
            if let reflection = model.reflection(for: sessionID) {
                mood = reflection.mood
                note = reflection.note
            }
        }
    }
}

struct DroneIntervalView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audioEngine: NativeAudioEngine

    var body: some View {
        let settings = model.practiceFeatures.droneSettings
        let targetMIDI = settings.writtenMIDINote + settings.interval.rawValue
        let baseLabel = PracticePitchMath.noteLabel(writtenMIDI: settings.writtenMIDINote)
        let upperLabel = PracticePitchMath.noteLabel(writtenMIDI: targetMIDI)
        BTScreen {
            BTPageHeader(
                eyebrow: "Tuner",
                title: "Drone and intervals",
                subtitle: "Listen first, then match the reference gently. Headphones help keep the speaker tone out of the microphone.",
                trailing: audioEngine.tonePlaying ? "Playing" : "Ready"
            )

            BTCard(tint: BTTheme.surfaceWarm) {
                Text(settings.interval == .unison ? baseLabel : "\(baseLabel) + \(upperLabel)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.55)
                    .accessibilityLabel(settings.interval == .unison ? "Written note \(baseLabel)" : "Written notes \(baseLabel) and \(upperLabel)")
                    .accessibilityIdentifier("drone.targetNote")
                Text(settings.interval == .unison ? "Match the reference note" : "Hear both written notes together, correctly transposed to concert pitch")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            BTCard {
                BTSectionHeader(title: "Reference")
                Stepper("Written note: \(PracticePitchMath.noteLabel(writtenMIDI: settings.writtenMIDINote))", value: Binding(
                    get: { model.practiceFeatures.droneSettings.writtenMIDINote },
                    set: { value in
                        var updated = model.practiceFeatures.droneSettings
                        updated.writtenMIDINote = value
                        model.updateDroneSettings(updated)
                    }
                ), in: 36...84)
                .accessibilityIdentifier("drone.noteStepper")

                Picker("Interval", selection: Binding(
                    get: { model.practiceFeatures.droneSettings.interval },
                    set: { value in
                        var updated = model.practiceFeatures.droneSettings
                        updated.interval = value
                        model.updateDroneSettings(updated)
                    }
                )) {
                    ForEach(TuningInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .accessibilityIdentifier("drone.interval")

                Slider(value: Binding(
                    get: { model.practiceFeatures.droneSettings.volume },
                    set: { value in
                        var updated = model.practiceFeatures.droneSettings
                        updated.volume = value
                        model.updateDroneSettings(updated)
                    }
                ), in: 0.05...0.5)
                .accessibilityLabel("Reference tone volume")
                .accessibilityIdentifier("drone.volume")
            }

            Label("Start quietly. Stop if the sound feels uncomfortable, and prefer headphones for microphone practice.", systemImage: "headphones")
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                audioEngine.tonePlaying ? model.stopDrone() : model.startDrone()
            } label: {
                Label(audioEngine.tonePlaying ? "Stop reference tone" : "Play reference tone", systemImage: audioEngine.tonePlaying ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
            .accessibilityIdentifier("drone.toggle")

            if let notice = audioEngine.audioNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Drone and intervals")
        .accessibilityIdentifier("screen.droneInterval")
        .onDisappear { model.stopDrone() }
    }
}

struct PracticePacksView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Practice library",
                title: "Offline practice packs",
                subtitle: "Each pack is stored in the app and opens one focused block at a time. No account or network is required."
            )

            ForEach(model.practicePacks) { pack in
                BTCard {
                    BTSectionHeader(title: pack.name, subtitle: pack.detail)
                    Text(NativeLocalization.format(
                        "%@ blocks · %@ minutes",
                        String(pack.blocks.count),
                        String(Int(pack.blocks.reduce(0) { $0 + $1.durationSeconds } / 60))
                    ))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(BTTheme.muted)
                    NavigationLink {
                        FocusedPracticeWorkspaceView(pack: pack)
                    } label: {
                        Label("Open focused workspace", systemImage: "rectangle.inset.filled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("practicePack.open.\(pack.id)")
                }
            }
        }
        .navigationTitle("Practice packs")
        .accessibilityIdentifier("screen.practicePacks")
    }
}

struct FocusedPracticeWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let pack: PracticePack
    @State private var confirmExit = false
    @AccessibilityFocusState private var blockFocused: Bool

    private var checkpoint: FocusedWorkspaceCheckpoint? {
        guard model.currentWorkspaceCheckpoint?.pack.id == pack.id else { return nil }
        return model.currentWorkspaceCheckpoint
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let block = checkpoint?.currentBlock
            let elapsed = checkpoint?.elapsedInBlock(at: context.date) ?? 0
            BTScreen {
                BTPageHeader(
                    eyebrow: pack.name,
                    title: block?.title ?? "Focused workspace",
                    subtitle: block?.instruction ?? "Start when you are ready. Only the current block is shown.",
                    trailing: block.map { timeLabel(max(0, $0.durationSeconds - elapsed)) }
                )
                .accessibilityFocused($blockFocused)

                if checkpoint == nil || checkpoint?.completed == true {
                    BTCard {
                        BTSectionHeader(title: checkpoint?.completed == true ? "Pack complete" : "Ready to focus", subtitle: pack.detail)
                        Button(checkpoint?.completed == true ? "Start again" : "Start pack") {
                            model.startWorkspace(pack: pack, now: context.date)
                        }
                        .buttonStyle(BTPrimaryButtonStyle())
                        .accessibilityIdentifier("workspace.startPack")
                    }
                } else if let block, let checkpoint {
                    BTCard(tint: BTTheme.surfaceWarm) {
                        Text(NativeLocalization.format(
                            "Block %@ of %@",
                            String(checkpoint.blockIndex + 1),
                            String(pack.blocks.count)
                        ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BTTheme.muted)
                        Label(block.kind.rawValue.capitalized, systemImage: icon(for: block.kind))
                            .font(.title2.weight(.bold))
                        ProgressView(value: elapsed, total: block.durationSeconds)
                            .accessibilityLabel("Block progress")
                            .accessibilityValue(NativeLocalization.format(
                                "%@ of %@ seconds",
                                String(Int(elapsed)),
                                String(Int(block.durationSeconds))
                            ))

                        if block.kind == .playAlong, let session = model.playAlongSession, model.playAlongPhase == .running {
                            Text(NativeLocalization.format(
                                "Play %@",
                                session.currentNoteName ?? NativeLocalization.string("the next note")
                            ))
                                .font(.title.weight(.bold))
                                .frame(maxWidth: .infinity)
                            ProgressView(value: session.heldFraction)
                                .accessibilityLabel("Two-second note hold")
                        }
                    }

                    if checkpoint.isRunning {
                        Button {
                            model.pauseWorkspace(now: context.date)
                        } label: {
                            Label("Pause block", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("workspace.pause")
                    } else {
                        Button {
                            Task { await model.beginWorkspaceCurrentBlock(now: context.date) }
                        } label: {
                            Label(elapsed > 0 ? "Resume block" : "Start block", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                        .accessibilityIdentifier("workspace.startBlock")
                    }

                    HStack(spacing: BTSpacing.md) {
                        Button {
                            model.moveWorkspace(by: -1, now: context.date)
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .disabled(checkpoint.blockIndex == 0)

                        if checkpoint.blockIndex == pack.blocks.count - 1 {
                            Button {
                                model.finishWorkspace(now: context.date)
                            } label: {
                                Label("Finish", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BTPrimaryButtonStyle())
                            .accessibilityIdentifier("workspace.finish")
                        } else {
                            Button {
                                model.moveWorkspace(by: 1, now: context.date)
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BTSecondaryButtonStyle())
                            .accessibilityIdentifier("workspace.next")
                        }
                    }

                    Button(role: .destructive) { confirmExit = true } label: {
                        Label("End this pack", systemImage: "xmark")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                }
            }
            .onChange(of: context.date) { _, date in
                model.advanceWorkspaceClock(now: date)
            }
            .onChange(of: checkpoint?.blockIndex) { _, _ in
                blockFocused = true
            }
        }
        .navigationTitle("Focused practice")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.focusedWorkspace")
        .onDisappear { model.pauseWorkspace() }
        .confirmationDialog("End this practice pack?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("End pack", role: .destructive) {
                model.discardWorkspace()
                dismiss()
            }
            Button("Keep practicing", role: .cancel) {}
        } message: {
            Text("Your completed practice history will stay saved, but this pack's current place will be removed.")
        }
    }

    private func icon(for kind: PracticePackBlockKind) -> String {
        switch kind {
        case .instruction: return "text.bubble"
        case .playAlong: return "music.note.list"
        case .metronome: return "metronome"
        case .drone: return "waveform"
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
