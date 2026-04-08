import SwiftUI

/// Gallery view showing all discovered creatures with their original sketch photos.
struct CollectionView: View {
    @Bindable var viewModel: CollectionViewModel
    let arViewModel: ARViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.creatures.isEmpty {
                    ContentUnavailableView(
                        "No Creatures Yet",
                        systemImage: "pencil.and.scribble",
                        description: Text("Draw a creature on paper and scan it to add it to your collection.")
                    )
                } else {
                    ScrollView {
                        // Stats header
                        HStack {
                            Label("\(viewModel.creatures.count) creatures", systemImage: "sparkles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.creatures) { creature in
                                CreatureCard(creature: creature, viewModel: viewModel)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .animation(.spring(duration: 0.4), value: viewModel.creatures.count)
                    }
                }
            }
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A single creature card in the collection grid.
struct CreatureCard: View {
    let creature: Creature
    let viewModel: CollectionViewModel
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 8) {
            // Sketch image
            Image(decorative: creature.sketchImage, scale: 1.0)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )

            // Name (tappable to edit)
            if isEditing {
                TextField("Nickname", text: $editText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.updateNickname(for: creature.id, nickname: editText)
                        isEditing = false
                    }
            } else {
                Text(creature.nickname ?? creature.type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .onTapGesture {
                        editText = creature.nickname ?? creature.type.displayName
                        isEditing = true
                    }
            }

            // Confidence + date
            HStack(spacing: 4) {
                Text("\(Int(creature.confidence * 100))%")
                    .foregroundStyle(confidenceColor)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(creature.discoveredAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var confidenceColor: Color {
        if creature.confidence >= 0.8 { return .green }
        if creature.confidence >= 0.5 { return .yellow }
        return .orange
    }
}

#Preview {
    CollectionView(viewModel: CollectionViewModel(), arViewModel: ARViewModel())
}
