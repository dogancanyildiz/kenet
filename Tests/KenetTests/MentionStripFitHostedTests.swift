#if os(macOS)
    import AppKit
    import EntityRecognition
    import SwiftUI
    import Testing

    @testable import Kenet

    /// Strip pieces laid out in a real window: the suggestion list's name label stays inside a
    /// narrow strip, and the quick entry chip strip, scrolled to its end, leaves its last chip
    /// out of the trailing fade.
    @MainActor
    @Suite(.serialized)
    struct MentionStripFitHostedTests {
        private let watchdog = HostedTestWatchdog()

        /// Frames the probes report, in the window's coordinates.
        @MainActor final class Frames {
            var values: [String: CGRect] = [:]
        }

        private static let longEntity = KnownEntity(
            file: "people/Mehmet Ali Karadeniz (üniversite).md", kind: .person, name: "Mehmet Ali Karadeniz",
            qualifier: "üniversite")

        private struct LabelProbe: View {
            let fit: MentionEntityLabel.Fit
            let size: DynamicTypeSize
            let frames: Frames

            var body: some View {
                VStack(alignment: .leading) {
                    MentionEntityLabel(entity: MentionStripFitHostedTests.longEntity, fit: fit)
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            frames.values["label"] = $0
                        }
                }
                .frame(width: MentionStripFitHostedTests.stripWidth, alignment: .leading)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    frames.values["strip"] = $0
                }
                .environment(\.dynamicTypeSize, size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        private static let stripWidth: CGFloat = 120

        private func measureLabel(fit: MentionEntityLabel.Fit, size: DynamicTypeSize) async throws -> (
            label: CGRect, strip: CGRect
        ) {
            let frames = Frames()
            let mount = HostedLayout.Mount(
                LabelProbe(fit: fit, size: size, frames: frames), size: CGSize(width: 600, height: 400))
            defer { mount.close() }
            await mount.settle()
            let label = try #require(frames.values["label"], "the label reported no frame")
            let strip = try #require(frames.values["strip"], "the strip reported no frame")
            return (label, strip)
        }

        /// D1: a suggestion row held to the strip's width; the name is cut, not pushed out.
        @Test func suggestionLabelStaysInsideTheStrip() async throws {
            let (label, strip) = try await measureLabel(fit: .wraps, size: .large)
            #expect(label.maxX <= strip.maxX + 0.5, "label \(label) runs past the strip \(strip)")
        }

        /// D1: at an accessibility size the suggestion wraps onto more lines instead of running out.
        @Test func suggestionLabelWrapsAtAccessibilitySizes() async throws {
            let (oneLine, _) = try await measureLabel(fit: .wraps, size: .large)
            let (label, strip) = try await measureLabel(fit: .wraps, size: .accessibility3)
            #expect(label.maxX <= strip.maxX + 0.5, "label \(label) runs past the strip \(strip)")
            #expect(label.height > oneLine.height * 1.5, "the long name did not wrap: \(label)")
        }

        private struct ActionProbe: View {
            let size: DynamicTypeSize
            let frames: Frames

            var body: some View {
                VStack(alignment: .leading) {
                    Button("Özel tip olarak ekle") {}
                        .buttonStyle(StripActionStyle())
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            frames.values["action"] = $0
                        }
                }
                // Narrower than the action's one line at any size: the Mac draws accessibility
                // sizes at the standard font, so only a narrow strip tells wrapping from overflow.
                .frame(width: 60, alignment: .leading)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    frames.values["strip"] = $0
                }
                .environment(\.dynamicTypeSize, size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        private func measureAction(size: DynamicTypeSize) async throws -> (action: CGRect, strip: CGRect) {
            let frames = Frames()
            let mount = HostedLayout.Mount(
                ActionProbe(size: size, frames: frames), size: CGSize(width: 600, height: 400))
            defer { mount.close() }
            await mount.settle()
            let action = try #require(frames.values["action"], "the action reported no frame")
            let strip = try #require(frames.values["strip"], "the strip reported no frame")
            return (action, strip)
        }

        /// At an accessibility size a strip action wraps inside the strip instead of running past
        /// the card (`fixedSize()` kept it on one line, wider than the strip).
        @Test func stripActionWrapsInsideTheStripAtAccessibilitySizes() async throws {
            let (action, strip) = try await measureAction(size: .accessibility3)
            #expect(action.maxX <= strip.maxX + 0.5, "action \(action) runs past the strip \(strip)")
        }

        /// The candidate row scrolls sideways: there the label keeps its full width on one line.
        @Test func candidateLabelKeepsItsFullWidth() async throws {
            let (label, strip) = try await measureLabel(fit: .oneLine, size: .large)
            #expect(label.width > strip.width, "the candidate label was cut: \(label)")
        }

        // MARK: - Chip strip fade (D2)

        private struct ChipStripProbe: View {
            let frames: Frames

            var body: some View {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { index in
                            Color.gray
                                .frame(width: 60, height: 24)
                                .onGeometryChange(for: CGRect.self) {
                                    $0.frame(in: .global)
                                } action: {
                                    frames.values["chip\(index)"] = $0
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .modifier(QuickEntryChipFade())
                .frame(width: 200, height: 40)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    frames.values["strip"] = $0
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        @Test func lastChipEndsBeforeTheFadeAtTheStripEnd() async throws {
            let frames = Frames()
            let mount = HostedLayout.Mount(ChipStripProbe(frames: frames), size: CGSize(width: 400, height: 200))
            defer { mount.close() }
            await mount.settle()
            let scroll = try #require(mount.views(NSScrollView.self).first, "the strip has no scroll view")
            let clip = scroll.contentView
            let documentWidth = try #require(scroll.documentView?.frame.width)
            // As far as the clip view lets it go: its insets (content margins) count.
            var end = clip.bounds
            end.origin.x = documentWidth * 2
            clip.scroll(to: clip.constrainBoundsRect(end).origin)
            scroll.reflectScrolledClipView(clip)
            await mount.settle()
            let strip = try #require(frames.values["strip"])
            let last = try #require(frames.values["chip7"])
            #expect(last.maxX <= strip.maxX + 0.5, "the strip did not reach its end: \(last) in \(strip)")
            #expect(
                last.maxX <= strip.maxX - QuickEntryChipFade.width + 0.5,
                "scrolled to the end, the last chip \(last) still lies in the fade of \(strip)")
        }
    }
#endif
