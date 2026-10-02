//
//  ScreenshotView.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

/// ScreenshotView keeps subject selection above the two actions, within the
/// existing 144-point notch. Additional controls occupy its right side without
/// a separate window or popover; the subject picker stays centered.
struct ScreenshotView: View {

    @Bindable var page: ScreenshotPage
    let context: NotchContextualPageContext

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDestinations = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                targetPicker
                    .frame(height: 36)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    actionButton(.capture, title: "Capture", symbol: "camera.viewfinder")
                    actionButton(.recording, title: "Record", symbol: "record.circle")
                }
            }
            .padding(.top, max(36, context.centerObstructionFrame.maxY + 6))
            .padding(.bottom, page.errorMessage == nil ? 12 : 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if page.showsOptions {
                options
                    .frame(width: 82, alignment: .top)
                    .padding(.top, max(36, context.centerObstructionFrame.maxY + 6))
                    .padding(.trailing, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            shoulderButton(
                symbol: "xmark",
                title : String(localized: "Close Screen Capture")
            ) {
                page.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("screenshot.close")
            .padding(.leading, 12)
            .padding(.top, 6)

            shoulderButton(
                symbol: "plus",
                title : String(localized: "Capture Options"),
                active: page.showsOptions
            ) {
                showsDestinations = false
                page.showsOptions.toggle()
            }
            .accessibilityIdentifier("screenshot.options")
            .padding(.trailing, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let message = page.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var targetPicker: some View {
        HStack(spacing: 0) {
            ForEach(ScreenshotTarget.allCases, id: \.self) { target in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { page.options.target = target }
                } label: {
                    Image(systemName: target.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(page.options.target == target ? 1 : 0.6))
                        .frame(width: 68, height: 30)
                        .background {
                            if page.options.target == target {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "screenshot.selection", in: selection)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help(target.title)
                .accessibilityLabel(target.title)
                .accessibilityAddTraits(page.options.target == target ? .isSelected : [])
                .accessibilityIdentifier("screenshot.target." + target.rawValue)
            }
        }
        .padding(3)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var options: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button { showsDestinations.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showsDestinations ? "folder.fill" : "folder")
                            .font(.system(size: 15))
                            .rotation3DEffect(
                                .degrees(showsDestinations && !reduceMotion ? -25 : 0),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .bottom
                            )
                    }
                    .frame(width: 28, height: 24)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsDestinations)
                .help(String(localized: "Save in \(page.options.directoryName). The last folder is remembered."))
                .accessibilityLabel(String(localized: "Save Location"))
                .accessibilityIdentifier("screenshot.destination")

                ScreenshotTimerButton(
                    seconds: page.options.delaySeconds,
                    onCycle: { page.options.cycleDelay() },
                    onStep : { page.options.adjustDelay(by: $0) }
                )
                .frame(width: 48, height: 24)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if showsDestinations {
                destinations
            } else {
                Grid(horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        optionButton(
                            "cursorarrow",
                            title: String(localized: "Include Pointer"),
                            value: $page.options.includesPointer
                        )
                        optionButton(
                            "macwindow",
                            title : String(localized: "Window Shadow"),
                            value : $page.options.includesWindowShadow,
                            shadow: true
                        )
                        .disabled(page.options.target != .window)
                        .help(page.options.target == .window
                              ? String(localized: "Include the window shadow")
                              : String(localized: "Shadow is available when selecting a window"))

                    }
                    GridRow {
                        optionButton(
                            "speaker.wave.2",
                            title: String(localized: "Record System Audio"),
                            value: $page.options.includesSystemAudio
                        )
                        optionButton(
                            "mic",
                            title: String(localized: "Record Microphone"),
                            value: $page.options.includesMicrophone
                        )
                    }
                    GridRow {
                        optionButton(
                            "cursorarrow.click",
                            title: String(localized: "Show Mouse Clicks"),
                            value: $page.options.showsMouseClicks
                        )
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var destinations: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                destinationButton("Desktop", symbol: "desktopcomputer", directory: .desktopDirectory)
                destinationButton("Documents", symbol: "doc", directory: .documentDirectory)
            }
            GridRow {
                destinationButton("Downloads", symbol: "arrow.down.circle", directory: .downloadsDirectory)
                Button {
                    showsDestinations = false
                    page.chooseDirectory()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Choose another save folder"))
                .accessibilityLabel(String(localized: "Choose Folder"))
            }
        }
    }

    private func destinationButton(
        _ title: LocalizedStringKey,
        symbol: String,
        directory: FileManager.SearchPathDirectory
    ) -> some View {
        Button {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                page.options.directoryPath = url.path
            }
            showsDestinations = false
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    private func optionButton(
        _ symbol: String,
        title: String,
        value: Binding<Bool>,
        shadow: Bool = false
    ) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .shadow(color: shadow ? .white.opacity(0.45) : .clear, radius: 0, x: 3, y: 3)
                .foregroundStyle(.white.opacity(value.wrappedValue ? 1 : 0.5))
                .frame(width: 28, height: 22)
                .background(value.wrappedValue ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(title + " · " + (value.wrappedValue ? String(localized: "On") : String(localized: "Off")))
        .accessibilityLabel(title)
        .accessibilityValue(value.wrappedValue ? String(localized: "On") : String(localized: "Off"))
    }

    private func actionButton(
        _ mode: ScreenshotMode,
        title: LocalizedStringKey,
        symbol: String
    ) -> some View {
        Button { page.perform(mode) } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mode == .capture ? Color(red: 0.65, green: 0.82, blue: 1) : Color(red: 1, green: 0.71, blue: 0.73))
                .frame(width: 100, height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!page.canCapture)
        .opacity(page.canCapture ? 1 : 0.4)
        .help(page.canCapture
              ? (mode == .capture ? String(localized: "Take a Screenshot") : String(localized: "Start Recording"))
              : String(localized: "Select Entire Screen to capture. Region and window selection are not available yet."))
        .accessibilityIdentifier(mode == .capture ? "screenshot.capture" : "screenshot.record")
    }

    private func shoulderButton(
        symbol: String,
        title: String,
        active: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(active ? 1 : 0.7))
                .frame(width: 28, height: 28)
                .background(active ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
