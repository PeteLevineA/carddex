import SwiftUI
import CarddexCore
import CarddexCatalog
import CarddexHolofoil

#if canImport(MetalKit) && canImport(UIKit)
import MetalKit

public struct HolofoilTab: View {

    @State private var holofoilCards: [HolofoilCatalogCard] = []
    @State private var selection: HolofoilCatalogCard?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(holofoilCards) { card in
                        Button {
                            selection = card
                        } label: {
                            HolofoilCardThumbnail(card: card)
                                .frame(width: 220, height: 308)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Holofoil")
            .task {
                holofoilCards = await CatalogStore.shared.allHolofoilCards()
                if selection == nil { selection = holofoilCards.first }
            }
            .sheet(item: $selection) { card in
                HolofoilSceneView(card: card)
                    .ignoresSafeArea()
            }
        }
    }
}

struct HolofoilCardThumbnail: View {
    let card: HolofoilCatalogCard
    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(Text(card.name).padding())
            Text(card.set ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// MTKView wrapped in SwiftUI. The Metal renderer mirrors the GLSL one used
/// by the web viewer at `apps/web/src/render/CardScene.js`.
struct HolofoilSceneView: UIViewRepresentable {
    let card: HolofoilCatalogCard

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        let loader = HolofoilTextureLoader(source: .mainBundle)
        let renderer = HolofoilRenderer(view: view, card: card, textureLoader: loader)
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: HolofoilRenderer?
    }
}
#else
public struct HolofoilTab: View {
    public init() {}
    public var body: some View {
        Text("Holofoil rendering requires Metal.")
    }
}
#endif
