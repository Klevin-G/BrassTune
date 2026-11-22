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
    private func shortcutSection(title: BTCopy, shortcuts: [PracticeShortcut]) -> some View {
        Text(verbatim: title.resolved)
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
                EmptyView()
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
                Text(verbatim: shortcut.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BTTheme.text)
                if let date = shortcut.lastStartedAt {
                    Text(verbatim: date.formatted(date: .abbreviated, time: .shortened))
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
            Label {
                Text(verbatim: NativeLocalization.string(model.isFavorite(shortcut) ? "Remove from favorites" : "Add to favorites"))
            } icon: {
                Image(systemName: model.isFavorite(shortcut) ? "star.fill" : "star")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("playAlong.favorite")
    }
}

struct CustomExerciseBuilderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let exerciseToEdit: SavedPlayAlongExercise?
    @State private var title: String
    @State private var notes: [String]
    @State private var errorMessage: String?

    init(exerciseToEdit: SavedPlayAlongExercise? = nil) {
        self.exerciseToEdit = exerciseToEdit
        _title = State(initialValue: exerciseToEdit?.title ?? "")
        _notes = State(initialValue: exerciseToEdit?.writtenNotes ?? ["C"])
    }

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Play-Along",
                title: exerciseToEdit == nil ? "Build an exercise" : "Edit exercise",
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
                    title: "Exercise notes",
                    subtitle: .verbatim(NativeLocalization.format("%@ of 32", String(notes.count)))
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
                Text(verbatim: errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("exerciseBuilder.error")
            }

            Button {
                let result: Result<SavedPlayAlongExercise, CustomExerciseValidationError>
                if let exerciseToEdit {
                    result = model.updateCustomExercise(id: exerciseToEdit.id, title: title, notes: notes)
                } else {
                    result = model.saveCustomExercise(title: title, notes: notes)
                }
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label {
                    Text(verbatim: NativeLocalization.string(
                        exerciseToEdit == nil ? "Save exercise" : "Save changes"
                    ))
                } icon: {
                    Image(systemName: "checkmark")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
            .accessibilityIdentifier("exerciseBuilder.save")

            if exerciseToEdit == nil, !model.practiceFeatures.customExercises.isEmpty {
                BTCard {
                    BTSectionHeader(title: "Your exercises", subtitle: "Edit or remove saved exercises here. Removing one also clears its shortcuts.")
                    ForEach(model.practiceFeatures.customExercises) { saved in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: saved.title).font(.headline)
                                Text(verbatim: saved.writtenNotes.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(BTTheme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            NavigationLink {
                                CustomExerciseBuilderView(exerciseToEdit: saved)
                            } label: {
                                Text("Edit")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(NativeLocalization.format("Edit %@", saved.title))
                            .accessibilityIdentifier("exerciseManager.edit.\(saved.title)")
                            Button(role: .destructive) {
                                model.deleteCustomExercise(id: saved.id)
                            } label: {
                                Text("Delete")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(NativeLocalization.format("Delete %@", saved.title))
                            .accessibilityIdentifier("exerciseManager.delete.\(saved.title)")
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .navigationTitle("Exercise builder")
        .accessibilityIdentifier("screen.exerciseBuilder")
    }
}

struct GuidedWarmupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var stepFocused: Bool
    @State private var showRestartConfirmation = false
    @State private var showExitConfirmation = false
    private let plan = GuidedWarmupPlan.fiveMinute

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: model.currentWarmupCheckpoint?.isRunning == true ? 0.1 : 1
        )) { context in
            let checkpoint = model.currentWarmupCheckpoint
            let elapsed = checkpoint?.elapsed(at: context.date, plan: plan) ?? 0
            let remaining = max(0, plan.durationSeconds - elapsed)
            let step = checkpoint?.currentStep(at: context.date, plan: plan) ?? plan.steps[0]
            let stepIndex = checkpoint?.currentStepIndex(at: context.date, plan: plan) ?? 0
            let stepElapsed = checkpoint?.elapsedInCurrentStep(at: context.date, plan: plan) ?? 0
            let breathingCycle = checkpoint?.breathingCycle(at: context.date, plan: plan)

            BTScreen {
                BTPageHeader(
                    eyebrow: "Warm-up",
                    title: .verbatim(plan.displayTitle),
                    subtitle: "A relaxed, resumable routine. Pause whenever you need to.",
                    trailing: .verbatim(timeLabel(remaining))
                )

                BTCard(tint: BTTheme.surfaceWarm) {
                    Text(verbatim: NativeLocalization.format(
                        "Step %@ of %@",
                        String(stepIndex + 1),
                        String(plan.steps.count)
                    ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BTTheme.muted)
                    Text(verbatim: step.displayTitle)
                        .font(.title2.weight(.bold))
                        .accessibilityFocused($stepFocused)
                        .accessibilityIdentifier("warmup.stepTitle")
                    Text(verbatim: step.displayInstruction)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    WarmupStepCue(step: step)
                    if let breathingCycle {
                        BreathingOrb(cycle: breathingCycle, reduceMotion: reduceMotion)
                            .accessibilityIdentifier("warmup.breathingOrb")
                    }
                    ProgressView(value: stepElapsed, total: step.durationSeconds)
                        .tint(BTTheme.accent)
                        .accessibilityLabel("Step progress")
                        .accessibilityValue(NativeLocalization.format(
                            "%@ percent",
                            String(Int((checkpoint?.stepProgress(at: context.date, plan: plan) ?? 0) * 100))
                        ))
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
                        Label {
                            Text(verbatim: NativeLocalization.string(checkpoint == nil ? "Start warm-up" : "Resume warm-up"))
                        } icon: {
                            Image(systemName: "play.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                    .accessibilityIdentifier("warmup.start")
                }

                if checkpoint != nil, checkpoint?.completed != true {
                    ViewThatFits(in: .horizontal) {
                        stepNavigationControls(stepIndex: stepIndex, now: context.date, horizontal: true)
                        stepNavigationControls(stepIndex: stepIndex, now: context.date, horizontal: false)
                    }

                    Button {
                        model.skipWarmupStep(now: context.date)
                    } label: {
                        Label("Skip this step", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .disabled(stepIndex == plan.steps.count - 1)
                    .accessibilityIdentifier("warmup.skip")

                    Button(role: .destructive) {
                        showRestartConfirmation = true
                    } label: {
                        Label("Restart from the beginning", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("warmup.restart")
                }
            }
            .onChange(of: context.date) { _, date in
                model.advanceWarmup(now: date)
            }
            .onChange(of: stepIndex) { _, _ in
                stepFocused = true
                if UIAccessibility.isVoiceOverRunning {
                    let stepPosition = NativeLocalization.format(
                        "Step %@ of %@",
                        String(stepIndex + 1),
                        String(plan.steps.count)
                    )
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(stepPosition). \(step.displayTitle). \(step.displayInstruction)"
                    )
                }
            }
            .onChange(of: breathingCycle?.phase) { _, phase in
                guard let phase, UIAccessibility.isVoiceOverRunning else { return }
                UIAccessibility.post(notification: .announcement, argument: phase.title)
            }
        }
        .navigationTitle("Warm-up")
        .accessibilityIdentifier("screen.warmup")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(
            model.currentWarmupCheckpoint != nil && model.currentWarmupCheckpoint?.completed != true
        )
        .onDisappear { model.pauseWarmup() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Exit") {
                    showExitConfirmation = true
                }
                .accessibilityIdentifier("warmup.exit")
            }
        }
        .confirmationDialog("Restart this warm-up?", isPresented: $showRestartConfirmation, titleVisibility: .visible) {
            Button("Restart warm-up", role: .destructive) {
                model.resetWarmup()
                model.startOrResumeWarmup()
            }
        } message: {
            Text("Your current warm-up progress will be discarded.")
        }
        .confirmationDialog("Leave warm-up?", isPresented: $showExitConfirmation, titleVisibility: .visible) {
            Button("Keep warm-up paused") {
                model.pauseWarmup()
                dismiss()
            }
            Button("Discard warm-up", role: .destructive) {
                model.discardWarmup()
                dismiss()
            }
        } message: {
            Text("You can keep this warm-up paused and resume it later, or discard its progress.")
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func stepNavigationControls(stepIndex: Int, now: Date, horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: BTSpacing.sm) {
                previousStepButton(stepIndex: stepIndex, now: now)
                nextStepButton(stepIndex: stepIndex, now: now)
            }
        } else {
            VStack(spacing: BTSpacing.sm) {
                previousStepButton(stepIndex: stepIndex, now: now)
                nextStepButton(stepIndex: stepIndex, now: now)
            }
        }
    }

    private func previousStepButton(stepIndex: Int, now: Date) -> some View {
        Button {
            model.moveWarmupStep(by: -1, now: now)
        } label: {
            Label("Previous step", systemImage: "backward.end.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .disabled(stepIndex == 0)
        .accessibilityIdentifier("warmup.previous")
    }

    private func nextStepButton(stepIndex: Int, now: Date) -> some View {
        Button {
            model.moveWarmupStep(by: 1, now: now)
        } label: {
            Label("Next step", systemImage: "forward.end.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .disabled(stepIndex == plan.steps.count - 1)
        .accessibilityIdentifier("warmup.next")
    }
}

private struct WarmupStepCue: View {
    let step: GuidedWarmupStep

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cueTitle).font(.subheadline.weight(.semibold))
                Text(verbatim: cueDetail).font(.footnote).foregroundStyle(BTTheme.muted)
            }
        } icon: {
            Image(systemName: iconName).foregroundStyle(BTTheme.accent)
        }
        .padding(.vertical, BTSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch step.kind {
        case .breathe: return "wind"
        case .buzz: return "waveform"
        case .longTone: return "music.note"
        case .slur: return "arrow.triangle.branch"
        case .scale: return "music.quarternote.3"
        }
    }

    private var cueTitle: String {
        switch step.kind {
        case .breathe: return "Air cue"
        case .buzz: return "Sound cue"
        case .longTone: return "Tone target"
        case .slur: return "Movement cue"
        case .scale: return "Scale target"
        }
    }

    private var cueDetail: String {
        switch step.kind {
        case .breathe: return "Let the air lead; keep the shoulders quiet."
        case .buzz: return "Choose an effortless middle-register pitch."
        case .longTone: return "Aim for a soft start and an even center."
        case .slur: return "Let the air connect the notes before the fingers."
        case .scale: return "Use the written scale target at an even volume."
        }
    }
}

private struct BreathingOrb: View {
    let cycle: GuidedWarmupBreathingCycle
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            ZStack {
                Circle()
                    .fill(BTTheme.accent.opacity(reduceMotion ? 0.15 : 0.22))
                    .frame(width: 128, height: 128)
                    .scaleEffect(reduceMotion ? 1 : orbScale)
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: cycle.phaseElapsed)
                Circle()
                    .trim(from: 0, to: max(0.02, cycle.cycleProgress))
                    .stroke(BTTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 142, height: 142)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(verbatim: cycle.phase.title).font(.headline)
                    Text(verbatim: "\(Int(cycle.remainingInPhase.rounded(.up))) sec").font(.caption.monospacedDigit())
                }
            }
            Text(verbatim: "Breath \(cycle.cycleNumber) · \(Int((cycle.cycleProgress * 100).rounded()))% of cycle")
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
        }
        .padding(.vertical, BTSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Breathing guide")
        .accessibilityValue(
            NativeLocalization.format(
                "%@, %@ seconds remaining, breath %@",
                NativeLocalization.string(cycle.phase.title),
                String(Int(cycle.remainingInPhase.rounded(.up))),
                String(cycle.cycleNumber)
            )
        )
    }

    private var orbScale: CGFloat {
        switch cycle.phase {
        case .inhale: return 0.72 + CGFloat(cycle.phaseElapsed / cycle.phaseDuration) * 0.28
        case .hold: return 1
        case .exhale: return 1 - CGFloat(cycle.phaseElapsed / cycle.phaseDuration) * 0.28
        }
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
                        presetStatus = NativeLocalization.string("Done")
                        presetName = ""
                    } else {
                        presetStatus = NativeLocalization.string("Use a unique preset name.")
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("metronome.savePreset")
            }

            ForEach(model.practiceFeatures.metronomePresets) { preset in
                VStack(alignment: .leading, spacing: BTSpacing.sm) {
                    Text(verbatim: preset.name)
                        .font(.headline)
                    Text(verbatim: NativeLocalization.format(
                        "%@ BPM · %@ · %@",
                        String(preset.settings.bpm),
                        preset.settings.meterLabel,
                        preset.settings.subdivision.title
                    ))
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    HStack {
                        Button {
                            model.applyMetronomePreset(id: preset.id)
                        } label: {
                            Text("Apply")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(NativeLocalization.format("Apply %@", preset.name))
                        .accessibilityIdentifier("metronome.preset.apply.\(preset.name)")
                        Button {
                            presetToRename = preset
                        } label: {
                            Text("Rename")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(NativeLocalization.format("Rename %@", preset.name))
                        .accessibilityIdentifier("metronome.preset.rename.\(preset.name)")
                        Button(role: .destructive) {
                            model.deleteMetronomePreset(id: preset.id)
                        } label: {
                            Text("Delete")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(NativeLocalization.format("Delete %@", preset.name))
                        .accessibilityIdentifier("metronome.preset.delete.\(preset.name)")
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
                Text(verbatim: presetStatus)
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
    @State private var editingGoal = false

    var body: some View {
        let goal = model.practiceFeatures.weeklyGoal
        let progress = model.weeklyPracticeProgress
        BTCard(tint: BTTheme.surfaceWarm) {
            BTSectionHeader(title: "This week's goal", subtitle: "A new week starts using your device's calendar and time zone.")
                .accessibilityIdentifier("progress.weeklyGoal")
            ProgressView(value: Double(progress.minutes), total: Double(goal.targetMinutes))
                .accessibilityLabel("Weekly practice minutes")
                .accessibilityValue(NativeLocalization.format(
                    "%@ of %@ minutes",
                    String(progress.minutes),
                    String(goal.targetMinutes)
                ))
                .accessibilityRespondsToUserInteraction(false)
            Text(verbatim: NativeLocalization.format(
                "%@ of %@ minutes · %@ of %@ sessions",
                String(progress.minutes),
                String(goal.targetMinutes),
                String(progress.sessionCount),
                String(goal.targetSessions)
            ))
                .font(.headline.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Button("Edit weekly goal") { editingGoal = true }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("progress.editWeeklyGoal")
        }
        .sheet(isPresented: $editingGoal) { WeeklyGoalEditor() }
    }
}

struct PracticeGoalListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var presentedSheet: PracticeGoalSheet?
    @State private var goalPendingDeletion: PracticeGoal?
    let focusedGoalID: PracticeGoal.ID?

    init(focusedGoalID: PracticeGoal.ID? = nil) {
        self.focusedGoalID = focusedGoalID
    }

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Goal practice",
                title: "Measurable goals",
                subtitle: "Log your own assessment after each attempt. BrassTune does not automatically verify outcomes."
            )

            if model.practiceFeatures.measurableGoals.isEmpty {
                BTCard(tint: BTTheme.surfaceWarm) {
                    Label("Start with one observable target", systemImage: "target")
                        .font(.headline)
                    Text("Choose a passage, skill, criterion, and strategy. Then note what happened and what you will change next time.")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    Button("Create a practice goal") { presentedSheet = .create }
                        .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                        .accessibilityIdentifier("practiceGoals.create")
                }
            } else {
                ForEach(displayedGoals) { goal in
                    PracticeGoalCard(
                        goal: goal,
                        logAttempt: { presentedSheet = .attempt(goal) },
                        edit: { presentedSheet = .edit(goal) },
                        completeOrReopen: {
                            if goal.isCompleted {
                                model.reopenPracticeGoal(id: goal.id)
                            } else {
                                model.completePracticeGoal(id: goal.id)
                            }
                        },
                        delete: { goalPendingDeletion = goal }
                    )
                }
                if model.practiceFeatures.measurableGoals.count < PracticeGoal.maximumGoals {
                    Button("Create another goal") { presentedSheet = .create }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("practiceGoals.create")
                } else {
                    Text(verbatim: NativeLocalization.format(
                        "You have %@ preserved goals. This device supports creating up to 24 new goals; export your local data, then delete a goal if you need room for another.",
                        model.practiceFeatures.measurableGoals.count.formatted(.number.locale(NativeLocalization.language.locale))
                    ))
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                }
            }
        }
        .navigationTitle("Practice goals")
        .accessibilityIdentifier("screen.practiceGoals")
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .create:
                PracticeGoalEditor()
            case .edit(let goal):
                PracticeGoalEditor(goal: goal)
            case .attempt(let goal):
                PracticeGoalAttemptEditor(goal: goal)
            }
        }
        .confirmationDialog(
            "Delete this practice goal?",
            isPresented: Binding(
                get: { goalPendingDeletion != nil },
                set: { if !$0 { goalPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete goal", role: .destructive) {
                if let goalPendingDeletion {
                    model.deletePracticeGoal(id: goalPendingDeletion.id)
                }
                goalPendingDeletion = nil
            }
        } message: {
            Text("Its self-reported attempts will also be removed from this device account.")
        }
    }

    private var displayedGoals: [PracticeGoal] {
        PracticeGoal.reviewPriority(in: model.practiceFeatures.measurableGoals, focusedGoalID: focusedGoalID)
    }
}

private enum PracticeGoalSheet: Identifiable {
    case create
    case edit(PracticeGoal)
    case attempt(PracticeGoal)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let goal): return "edit-" + goal.id.uuidString
        case .attempt(let goal): return "attempt-" + goal.id.uuidString
        }
    }
}

private struct PracticeGoalCard: View {
    @EnvironmentObject private var model: AppModel
    let goal: PracticeGoal
    let logAttempt: () -> Void
    let edit: () -> Void
    let completeOrReopen: () -> Void
    let delete: () -> Void
    @State private var attemptHistoryExpanded = false
    @State private var metronomePresented = false

    var body: some View {
        BTCard(tint: goal.isCompleted ? BTTheme.surfaceWarm : BTTheme.surface) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(verbatim: goal.passage)
                        .font(.headline)
                    Text(verbatim: "\(goal.skill.title) · \(goal.criterion.summary)")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    Text(verbatim: NativeLocalization.format("Strategy: %@", goal.strategy.title))
                        .font(.caption)
                        .foregroundStyle(BTTheme.muted)
                    Text(verbatim: goal.isDueForReview()
                        ? NativeLocalization.string("Due for your self-assessment")
                        : NativeLocalization.format(
                            "Review on %@",
                            goal.nextReviewAt.formatted(date: .abbreviated, time: .omitted)
                        ))
                        .font(.caption)
                        .foregroundStyle(BTTheme.muted)
                }
                Spacer()
                if goal.isCompleted {
                    Label("Completed manually", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BTTheme.success)
                        .accessibilityLabel("Completed manually")
                }
            }

            if let attempt = goal.attempts.first {
                Divider()
                PracticeGoalAttemptSummary(attempt: attempt, isLatest: true)
                if goal.attempts.count > 1 {
                    DisclosureGroup("Attempt history", isExpanded: $attemptHistoryExpanded) {
                        ForEach(goal.attempts.dropFirst()) { historicalAttempt in
                            Divider()
                            PracticeGoalAttemptSummary(attempt: historicalAttempt, isLatest: false)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("practiceGoals.attemptHistory.\(goal.id.uuidString)")
                }
            } else {
                Text("No self-assessed attempts logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
            }

            HStack {
                Button("Log attempt", action: logAttempt)
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("practiceGoals.logAttempt.\(goal.id.uuidString)")
                Button(goal.isCompleted ? "Reopen" : "Complete", action: completeOrReopen)
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("practiceGoals.complete.\(goal.id.uuidString)")
            }
            if goal.supportsMetronomePractice {
                Button {
                    model.stopMetronomeTuner()
                    model.stopMetronome()
                    var settings = model.metronome
                    settings.bpm = goal.recommendedMetronomeTempoBPM
                    model.metronome = settings
                    metronomePresented = true
                } label: {
                    Label { Text(verbatim: practiceTempoLabel) } icon: { Image(systemName: "metronome") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityHint("Opens the metronome at this tempo. The metronome stays stopped until you start it.")
                .accessibilityIdentifier("practiceGoals.practiceTempo.\(goal.id.uuidString)")
                .navigationDestination(isPresented: $metronomePresented) { MetronomeView() }
                DisclosureGroup("Tempo ladder") {
                    PracticeTempoLadderView(goal: goal)
                        .id("\(goal.id.uuidString)-\(goal.criterion.targetTempoBPM)-\(goal.mostRecentRecordedTempoBPM ?? -1)")
                }
                .accessibilityIdentifier("practiceGoals.ladderDisclosure.\(goal.id.uuidString)")
            }
            HStack {
                Button("Edit", action: edit)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Delete", role: .destructive, action: delete)
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var practiceTempoLabel: String {
        let tempo = goal.recommendedMetronomeTempoBPM.formatted(.number.locale(NativeLocalization.language.locale))
        if goal.mostRecentRecordedTempoBPM != nil {
            return NativeLocalization.format("Practice at %@ BPM", tempo)
        }
        return NativeLocalization.format("Practice at target %@ BPM", tempo)
    }
}

private struct PracticeTempoLadderView: View {
    @EnvironmentObject private var model: AppModel
    let goal: PracticeGoal
    @State private var ladder: PracticeTempoLadder
    @State private var metronomePresented = false

    init(goal: PracticeGoal) {
        self.goal = goal
        _ladder = State(initialValue: PracticeTempoLadder(
            startBPM: PracticeTempoLadder.suggestedStart(targetBPM: goal.criterion.targetTempoBPM, recordedBPM: goal.mostRecentRecordedTempoBPM),
            targetBPM: goal.criterion.targetTempoBPM
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            if let adjustment = goal.attempts.first?.nextAdjustment, !adjustment.isEmpty {
                Text(verbatim: NativeLocalization.format("Next adjustment: %@", adjustment))
                    .font(.caption).foregroundStyle(BTTheme.muted)
            }
            Stepper(value: Binding(get: { ladder.startBPM }, set: { ladder.setStart($0) }),
                    in: PracticeGoalCriterion.tempoRange.lowerBound...ladder.targetBPM) {
                Text(verbatim: NativeLocalization.format("Starting tempo: %@ BPM", ladder.startBPM.formatted(.number.locale(NativeLocalization.language.locale))))
            }
            .accessibilityIdentifier("practiceGoals.ladderStart")
            Stepper(value: Binding(get: { ladder.stepBPM }, set: { ladder.setStep($0) }), in: 1...20) {
                Text(verbatim: NativeLocalization.format("Tempo step: %@ BPM", ladder.stepBPM.formatted(.number.locale(NativeLocalization.language.locale))))
            }
            .accessibilityIdentifier("practiceGoals.ladderStep")
            Text(verbatim: NativeLocalization.format("Current: %@ BPM · Target: %@ BPM", ladder.currentBPM.formatted(.number.locale(NativeLocalization.language.locale)), ladder.targetBPM.formatted(.number.locale(NativeLocalization.language.locale))))
                .font(.subheadline)
            HStack {
                Button("Step back") { ladder.stepBack() }
                    .disabled(ladder.currentBPM == ladder.startBPM)
                    .accessibilityIdentifier("practiceGoals.ladderBack")
                Spacer()
                Button("Next tempo") { ladder.advance() }
                    .disabled(ladder.currentBPM == ladder.targetBPM)
                    .accessibilityIdentifier("practiceGoals.ladderNext")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            Button {
                model.stopMetronomeTuner()
                model.stopMetronome()
                var settings = model.metronome
                settings.bpm = ladder.currentBPM
                model.metronome = settings
                metronomePresented = true
            } label: {
                Label {
                    Text(verbatim: NativeLocalization.format("Practice at %@ BPM", ladder.currentBPM.formatted(.number.locale(NativeLocalization.language.locale))))
                } icon: { Image(systemName: "metronome") }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityHint("Opens the metronome at this tempo. The metronome stays stopped until you start it.")
            .accessibilityIdentifier("practiceGoals.ladderPractice.\(goal.id.uuidString)")
            .navigationDestination(isPresented: $metronomePresented) { MetronomeView() }
            Text("Repeat a tempo or move when you are ready; this does not record an outcome.")
                .font(.footnote).foregroundStyle(BTTheme.muted)
        }
    }
}

struct PracticeGoalAttemptSummary: View {
    let attempt: PracticeGoalAttempt
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            if isLatest {
                Text(verbatim: NativeLocalization.format("Latest self-assessment: %@", attempt.outcome.title))
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(verbatim: attempt.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                Text(verbatim: attempt.outcome.title)
                    .font(.subheadline.weight(.semibold))
            }
            achievedValues
            if let criterionSnapshot = attempt.criterionSnapshot {
                Text(verbatim: criterionSnapshot.summary)
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
            }
            if let strategySnapshot = attempt.strategySnapshot {
                Text(verbatim: NativeLocalization.format("Strategy: %@", strategySnapshot.title))
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
            }
            Text(verbatim: NativeLocalization.format("Reflection: %@", attempt.reflection))
                .font(.caption)
            Text(verbatim: NativeLocalization.format("Next adjustment: %@", attempt.nextAdjustment))
                .font(.caption)
        }
    }

    @ViewBuilder
    private var achievedValues: some View {
        if let achievedTempoBPM = attempt.achievedTempoBPM,
           let achievedCleanRepetitions = attempt.achievedCleanRepetitions {
            Text(verbatim: NativeLocalization.format(
                "Self-reported: %@ repetitions at %@ BPM",
                achievedCleanRepetitions.formatted(.number.locale(NativeLocalization.language.locale)),
                achievedTempoBPM.formatted(.number.locale(NativeLocalization.language.locale))
            ))
                .font(.caption)
        } else if let achievedCleanRepetitions = attempt.achievedCleanRepetitions {
            Text(verbatim: NativeLocalization.format(
                "Self-reported: %@ repetitions",
                achievedCleanRepetitions.formatted(.number.locale(NativeLocalization.language.locale))
            ))
                .font(.caption)
        } else if let achievedSustainSeconds = attempt.achievedSustainSeconds {
            Text(verbatim: NativeLocalization.format(
                "Self-reported: sustained %@ seconds",
                achievedSustainSeconds.formatted(.number.locale(NativeLocalization.language.locale))
            ))
                .font(.caption)
        }
    }
}

struct PracticeGoalEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let existingGoal: PracticeGoal?
    @State private var passage = ""
    @State private var skill: PracticeGoalSkill = .articulation
    @State private var strategy: PracticeGoalStrategy = .slowPractice
    @State private var criterionKind: PracticeGoalCriterionKind = .cleanRepetitions
    @State private var tempo = 80
    @State private var repetitions = 3
    @State private var sustainSeconds = 8
    @State private var nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    init(goal: PracticeGoal? = nil, initialPassage: String = "", initialTempo: Int = 80) {
        existingGoal = goal
        _passage = State(initialValue: initialPassage)
        _tempo = State(initialValue: min(PracticeGoalCriterion.tempoRange.upperBound, max(PracticeGoalCriterion.tempoRange.lowerBound, initialTempo)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Focus") {
                    TextField("Passage or exercise", text: $passage, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("practiceGoals.passage")
                    Picker("Skill", selection: $skill) {
                        ForEach(PracticeGoalSkill.allCases) { skill in
                            Text(verbatim: skill.title).tag(skill)
                        }
                    }
                }
                Section("Observable criterion") {
                    Picker("Criterion", selection: $criterionKind) {
                        ForEach(PracticeGoalCriterionKind.allCases) { kind in
                            Text(verbatim: kind.title).tag(kind)
                        }
                    }
                    if criterionKind == .cleanRepetitions {
                        Stepper(value: $tempo, in: PracticeGoalCriterion.tempoRange) {
                            Text(verbatim: NativeLocalization.format("Tempo: %@ BPM", tempo.formatted(.number.locale(NativeLocalization.language.locale))))
                        }
                        Stepper(value: $repetitions, in: PracticeGoalCriterion.repetitionRange) {
                            Text(verbatim: NativeLocalization.format("Clean repetitions: %@", repetitions.formatted(.number.locale(NativeLocalization.language.locale))))
                        }
                    } else {
                        Stepper(value: $sustainSeconds, in: PracticeGoalCriterion.sustainSecondsRange) {
                            Text(verbatim: NativeLocalization.format("Sustain: %@ seconds", sustainSeconds.formatted(.number.locale(NativeLocalization.language.locale))))
                        }
                    }
                }
                Section("Strategy") {
                    Picker("Use", selection: $strategy) {
                        ForEach(PracticeGoalStrategy.allCases) { strategy in
                            Text(verbatim: strategy.title).tag(strategy)
                        }
                    }
                    Text("Use this as your next practice approach; it is not an automatic assessment.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                }
                Section("Revisit") {
                    DatePicker("Review this goal", selection: $nextReviewAt, displayedComponents: .date)
                    Text("Choose when you plan to revisit this target; it is a reminder for your own practice plan.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                }
            }
            .navigationTitle(existingGoal == nil ? "New goal" : "Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.savePracticeGoal(
                            id: existingGoal?.id,
                            passage: passage,
                            skill: skill,
                            criterion: PracticeGoalCriterion(
                                kind: criterionKind,
                                targetTempoBPM: tempo,
                                targetCleanRepetitions: repetitions,
                                targetSustainSeconds: sustainSeconds
                            ),
                            strategy: strategy,
                            nextReviewAt: nextReviewAt
                        )
                        dismiss()
                    }
                    .disabled(passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let existingGoal else { return }
                passage = existingGoal.passage
                skill = existingGoal.skill
                strategy = existingGoal.strategy
                criterionKind = existingGoal.criterion.kind
                tempo = existingGoal.criterion.targetTempoBPM
                repetitions = existingGoal.criterion.targetCleanRepetitions
                sustainSeconds = existingGoal.criterion.targetSustainSeconds
                nextReviewAt = existingGoal.nextReviewAt
            }
        }
    }
}

private struct PracticeGoalAttemptEditor: View {
    private enum Field: Hashable { case reflection, nextAdjustment }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    let goal: PracticeGoal
    @State private var outcome: PracticeGoalAttemptOutcome?
    @State private var reflection = ""
    @State private var nextAdjustment = ""
    @State private var recordMeasurements = false
    @State private var recordTempo = false
    @State private var achievedTempo = PracticeGoalCriterion.tempoRange.lowerBound
    @State private var achievedRepetitions = 0
    @State private var achievedSustainSeconds = 0
    @State private var nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: goal.passage)
                    Text(verbatim: goal.criterion.summary)
                        .foregroundStyle(BTTheme.muted)
                } header: {
                    Text("Self-assessed attempt")
                } footer: {
                    Text("Choose the outcome yourself. This goal is not automatically detected by BrassTune.")
                }
                Picker("Outcome", selection: $outcome) {
                    Text("Choose outcome").tag(PracticeGoalAttemptOutcome?.none)
                    ForEach(PracticeGoalAttemptOutcome.allCases) { outcome in
                        Text(verbatim: outcome.title).tag(Optional(outcome))
                    }
                }
                .accessibilityIdentifier("practiceGoals.outcome")
                Section("What you achieved") {
                    Toggle("Record measurements", isOn: $recordMeasurements)
                        .accessibilityIdentifier("practiceGoals.recordMeasurements")
                    if recordMeasurements {
                        if goal.criterion.kind == .cleanRepetitions {
                            Toggle("Record tempo", isOn: $recordTempo)
                                .accessibilityIdentifier("practiceGoals.recordTempo")
                            if recordTempo {
                                Stepper(value: $achievedTempo, in: PracticeGoalCriterion.tempoRange, step: 2) {
                                    Text(verbatim: NativeLocalization.format("Tempo: %@ BPM", achievedTempo.formatted(.number.locale(NativeLocalization.language.locale))))
                                }
                            }
                            Stepper(value: $achievedRepetitions, in: PracticeGoalAttempt.repetitionRange) {
                                Text(verbatim: NativeLocalization.format("Clean repetitions: %@", achievedRepetitions.formatted(.number.locale(NativeLocalization.language.locale))))
                            }
                        } else {
                            Stepper(value: $achievedSustainSeconds, in: PracticeGoalAttempt.sustainSecondsRange) {
                                Text(verbatim: NativeLocalization.format("Sustain: %@ seconds", achievedSustainSeconds.formatted(.number.locale(NativeLocalization.language.locale))))
                            }
                        }
                    }
                    Text(verbatim: NativeLocalization.string(recordMeasurements ? "Enter your own observation. BrassTune does not measure or verify this result automatically." : "Measurements are optional. Add only the values you observed yourself."))
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                }
                Section("Revisit") {
                    DatePicker("Review this goal", selection: $nextReviewAt, displayedComponents: .date)
                        .accessibilityIdentifier("practiceGoals.nextReview")
                }
                Section("Reflection") {
                    TextEditor(text: $reflection)
                        .frame(minHeight: 90)
                        .focused($focusedField, equals: .reflection)
                        .accessibilityLabel("Reflection")
                        .accessibilityIdentifier("practiceGoals.reflection")
                }
                Section("Next adjustment") {
                    TextEditor(text: $nextAdjustment)
                        .frame(minHeight: 90)
                        .focused($focusedField, equals: .nextAdjustment)
                        .accessibilityLabel("Next adjustment")
                        .accessibilityIdentifier("practiceGoals.nextAdjustment")
                }
            }
            .navigationTitle("Log attempt")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("practiceGoals.dismissKeyboard")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let outcome else { return }
                        let saved = model.logPracticeGoalAttempt(
                            goalID: goal.id,
                            outcome: outcome,
                            reflection: reflection,
                            nextAdjustment: nextAdjustment,
                            achievedTempoBPM: recordMeasurements && recordTempo && goal.criterion.kind == .cleanRepetitions ? achievedTempo : nil,
                            achievedCleanRepetitions: recordMeasurements && goal.criterion.kind == .cleanRepetitions ? achievedRepetitions : nil,
                            achievedSustainSeconds: recordMeasurements && goal.criterion.kind == .sustainedTone ? achievedSustainSeconds : nil,
                            nextReviewAt: nextReviewAt
                        )
                        if saved { dismiss() } else { limitReached = true }
                    }
                    .disabled(outcome == nil || reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAdjustment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Attempt limit reached", isPresented: $limitReached) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This goal already has 50 saved self-assessments. Its history is preserved; create another goal to continue logging, or export your local data before deleting this one.")
            }
        }
    }
}

private struct WeeklyGoalEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var sessions: Int

    init() {
        _minutes = State(initialValue: 15)
        _sessions = State(initialValue: 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $minutes, in: 5...600, step: 5) {
                    Text(verbatim: NativeLocalization.format("Goal: %@ minutes", String(minutes)))
                }
                    .accessibilityIdentifier("progress.goalMinutes")
                Section {
                    Stepper(value: $sessions, in: 1...WeeklyPracticeGoal.maximumTargetSessions) {
                        Text(verbatim: NativeLocalization.format("Goal: %@ sessions", String(sessions)))
                    }
                    .accessibilityLabel(NativeLocalization.string("Weekly session goal"))
                    .accessibilityValue(NativeLocalization.format("%@ completed practice sessions", String(sessions)))
                    .accessibilityHint(NativeLocalization.string("Choose from 1 to 168 completed practice sessions for this week."))
                    .accessibilityIdentifier("progress.goalSessions")
                } header: {
                    Text(verbatim: NativeLocalization.string("Weekly session target"))
                } footer: {
                    Text(verbatim: NativeLocalization.string("Only completed sessions with recorded practice time count toward this target."))
                }
            }
            .navigationTitle("Weekly goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateWeeklyGoal(minutes: minutes, sessions: sessions)
                        dismiss()
                    }
                }
            }
            .onAppear {
                minutes = model.practiceFeatures.weeklyGoal.targetMinutes
                sessions = model.practiceFeatures.weeklyGoal.targetSessions
            }
        }
    }
}

struct WeakTransitionCard: View {
    @EnvironmentObject private var model: AppModel
    let beginPersonalDrill: (PlayAlongExercise) -> Void

    var body: some View {
        BTCard {
            if let insight = model.weakTransitionInsight {
                BTSectionHeader(title: "Weak-transition drill", subtitle: .verbatim(insight.explanation))
                Text(verbatim: NativeLocalization.preserve(insight.exercise.writtenNotes.joined(separator: "  ")))
                    .font(.title3.monospaced().weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    beginPersonalDrill(insight.exercise)
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
                    Text(verbatim: mood.title).tag(mood)
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
            Button {
                model.saveReflection(sessionID: sessionID, mood: mood, note: note)
                saved = true
            } label: {
                Text(verbatim: NativeLocalization.string(saved ? "Saved" : "Save reflection"))
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
        let writtenMIDIs = PracticePitchMath.writtenMIDIs(
            writtenMIDI: settings.writtenMIDINote,
            interval: settings.interval,
            voicing: settings.voicing
        )
        let notesLabel = writtenMIDIs
            .map(PracticePitchMath.noteLabel(writtenMIDI:))
            .joined(separator: " + ")
        VStack(spacing: 0) {
        BTScreen {
            BTCard(tint: BTTheme.surfaceWarm) {
                Text(verbatim: NativeLocalization.preserve(notesLabel))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.55)
                    .accessibilityLabel(Text(verbatim: NativeLocalization.format("Written notes: %@", notesLabel)))
                    .accessibilityIdentifier("drone.targetNote")

            }

            BTCard {
                BTSectionHeader(title: "Reference")
                Stepper(value: Binding(
                    get: { model.practiceFeatures.droneSettings.writtenMIDINote },
                    set: { value in
                        var updated = model.practiceFeatures.droneSettings
                        updated.writtenMIDINote = value
                        model.updateDroneSettings(updated)
                    }
                ), in: 36...84)
                {
                    Text(verbatim: NativeLocalization.format(
                        "Written note: %@",
                        PracticePitchMath.noteLabel(writtenMIDI: settings.writtenMIDINote)
                    ))
                }
                .accessibilityIdentifier("drone.noteStepper")

                Menu {
                    ForEach(DroneVoicing.allCases) { voicing in
                        Button(voicing.title) {
                            var updated = model.practiceFeatures.droneSettings
                            updated.voicing = voicing
                            model.updateDroneSettings(updated)
                        }
                    }
                } label: {
                    droneSelectionLabel(title: "Voicing", selected: settings.voicing.title)
                }
                .btMinimumInteractiveSize(alignment: .leading)
                .accessibilityLabel("Voicing")
                .accessibilityValue(settings.voicing.title)
                .accessibilityIdentifier("drone.voicing")

                if settings.voicing == .interval {
                    Menu {
                        ForEach(TuningInterval.allCases) { interval in
                            Button(interval.title) {
                            var updated = model.practiceFeatures.droneSettings
                                updated.interval = interval
                                model.updateDroneSettings(updated)
                            }
                        }
                    } label: {
                        droneSelectionLabel(title: "Interval", selected: settings.interval.title)
                    }
                    .btMinimumInteractiveSize(alignment: .leading)
                    .accessibilityLabel("Interval")
                    .accessibilityValue(settings.interval.title)
                    .accessibilityIdentifier("drone.interval")
                }

                Menu {
                    ForEach(DroneTemperament.allCases) { temperament in
                        Button(temperament.title) {
                            var updated = model.practiceFeatures.droneSettings
                            updated.temperament = temperament
                            model.updateDroneSettings(updated)
                        }
                    }
                } label: {
                    droneSelectionLabel(title: "Temperament", selected: settings.temperament.title)
                }
                .btMinimumInteractiveSize(alignment: .leading)
                .accessibilityLabel("Temperament")
                .accessibilityValue(settings.temperament.title)
                .accessibilityIdentifier("drone.temperament")

                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(verbatim: NativeLocalization.string("How the tuning references differ"))
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: NativeLocalization.string("Equal temperament spaces an octave into 12 equal semitone steps. Just intonation uses simple ratios from the selected root, so an interval or chord can differ slightly from equal temperament."))
                    Text(verbatim: NativeLocalization.string("Your tuner cents use equal temperament, so a just third or fifth can show a non-zero value."))
                    Text(verbatim: NativeLocalization.string("Use the drone to hear beat speed and color, then adjust for the musical setting. It is a listening reference, not an absolute in-tune verdict."))
                }
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("drone.temperamentExplanation")

                Text("Volume").font(.subheadline.weight(.semibold))
                Slider(value: Binding(
                    get: { model.practiceFeatures.droneSettings.volume },
                    set: { value in
                        var updated = model.practiceFeatures.droneSettings
                        updated.volume = value
                        model.updateDroneSettings(updated)
                    }
                ), in: NativeToneOutputPolicy.minimumUserVolume...NativeToneOutputPolicy.maximumUserVolume)
                .accessibilityLabel("Volume")
                .accessibilityIdentifier("drone.volume")
            }

            BTCard(tint: BTTheme.surfaceWarm) {
                Label("Compare intervals by ear", systemImage: "ear")
                    .font(.headline)
                Text("Choose an interval, then press Play. Listen to the two notes, switch temperament, and listen again. Try singing or playing the upper note with the root.")
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    ForEach([TuningInterval.majorThird, .perfectFifth]) { interval in
                        Button(interval.title) {
                            model.stopDrone()
                            var updated = model.practiceFeatures.droneSettings
                            updated.voicing = .interval
                            updated.interval = interval
                            model.updateDroneSettings(updated, restartIfPlaying: false)
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("drone.exercise.\(interval.rawValue)")
                    }
                }
                if settings.voicing == .interval,
                   settings.interval == .majorThird || settings.interval == .perfectFifth {
                    Text(verbatim: NativeLocalization.format(
                        "Just interval: %@ cents relative to equal temperament.",
                        DroneListeningExercise.justOffsetLabel(for: settings.interval)
                    ))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .accessibilityIdentifier("drone.exercise.offset")
                }
            }
            .accessibilityIdentifier("drone.listeningExercise")

            BTCard(tint: BTTheme.surfaceWarm) {
                Label("First drone exercise", systemImage: "ear")
                    .font(.headline)
                Text("Choose one comfortable note, listen for two calm breaths, then match it softly. Adjust by listening for a steadier sound; the drone does not score your pitch.")
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("drone.firstExercise")

            Label("Start quietly. Stop if the sound feels uncomfortable, and prefer headphones for microphone practice.", systemImage: "headphones")
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)


            if let notice = audioEngine.audioNotice {
                Text(verbatim: notice)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                audioEngine.tonePlaying ? model.stopDrone() : model.startDrone()
            } label: {
                Label {
                    Text(verbatim: NativeLocalization.string(audioEngine.tonePlaying ? "Stop reference tone" : "Play reference tone"))
                } icon: {
                    Image(systemName: audioEngine.tonePlaying ? "stop.fill" : "play.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
            .accessibilityIdentifier("drone.toggle")
                .padding(.horizontal, BTSpacing.lg)
                .padding(.vertical, BTSpacing.sm)
                .background(.bar)
        }
        }
        .navigationTitle("Drone and intervals")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.droneInterval")
        .onDisappear { model.stopDrone() }
    }

    private func droneSelectionLabel(title: String, selected: String) -> some View {
        HStack(spacing: BTSpacing.sm) {
            Text(verbatim: title)
                .font(.headline)
            Spacer()
            Text(verbatim: selected)
                .foregroundStyle(BTTheme.muted)
            Image(systemName: "chevron.up.chevron.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BTTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

enum DroneListeningExercise {
    static func justOffsetCents(for interval: TuningInterval) -> Double {
        1200 * log2(interval.justIntonationRatio) - Double(interval.rawValue) * 100
    }

    static func justOffsetLabel(for interval: TuningInterval) -> String {
        let rounded = Int(justOffsetCents(for: interval).rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
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
                    BTSectionHeader(title: .verbatim(pack.displayName), subtitle: .verbatim(pack.displayDetail))
                    Text(verbatim: NativeLocalization.format(
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
                    eyebrow: .verbatim(pack.displayName),
                    title: block.map { .verbatim(pack.displayTitle(for: $0)) } ?? "Focused workspace",
                    subtitle: block.map { .verbatim(pack.displayInstruction(for: $0)) } ?? "Start when you are ready. Only the current block is shown.",
                    trailing: block.map { .verbatim(timeLabel(max(0, $0.durationSeconds - elapsed))) }
                )
                .accessibilityFocused($blockFocused)

                if checkpoint == nil || checkpoint?.completed == true {
                    BTCard {
                        BTSectionHeader(
                            title: checkpoint?.completed == true ? "Pack complete" : "Ready to focus",
                            subtitle: .verbatim(pack.displayDetail)
                        )
                        Button {
                            model.startWorkspace(pack: pack, now: context.date)
                        } label: {
                            Text(verbatim: NativeLocalization.string(checkpoint?.completed == true ? "Start again" : "Start pack"))
                        }
                        .buttonStyle(BTPrimaryButtonStyle())
                        .accessibilityIdentifier("workspace.startPack")
                    }
                } else if let block, let checkpoint {
                    BTCard(tint: BTTheme.surfaceWarm) {
                        Text(verbatim: NativeLocalization.format(
                            "Block %@ of %@",
                            String(checkpoint.blockIndex + 1),
                            String(pack.blocks.count)
                        ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BTTheme.muted)
                        Label {
                            Text(verbatim: block.kind.title)
                        } icon: {
                            Image(systemName: icon(for: block.kind))
                        }
                            .font(.title2.weight(.bold))
                        ProgressView(value: elapsed, total: block.durationSeconds)
                            .accessibilityLabel("Block progress")
                            .accessibilityValue(NativeLocalization.format(
                                "%@ of %@ seconds",
                                String(Int(elapsed)),
                                String(Int(block.durationSeconds))
                            ))

                        if block.kind == .playAlong, let session = model.playAlongSession, model.playAlongPhase == .running {
                            Text(verbatim: NativeLocalization.format(
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
                            Label {
                                Text(verbatim: NativeLocalization.string(elapsed > 0 ? "Resume block" : "Start block"))
                            } icon: {
                                Image(systemName: "play.fill")
                            }
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
