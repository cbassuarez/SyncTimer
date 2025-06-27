// ── 1) New Subview for Flash-Color Swatches ───────────────────────
struct FlashColorPicker: View {
    @Binding var selectedColor: Color
    @Binding var showCustom: Bool
    let presets: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flash Color")
                .font(.custom("Roboto-Regular", size: 16))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presets, id: \.self) { color in
                        let isSelected = (color == selectedColor)
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.primary : Color.clear,
                                                lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // “More…” button to open full picker
                    Button {
                        showCustom.toggle()
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 24))
                            .foregroundColor(selectedColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            .sheet(isPresented: $showCustom) {
                NavigationView {
                    ColorPicker("Pick Custom Flash Color", selection: $selectedColor)
                        .padding()
                        .navigationTitle("Custom Color")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showCustom = false }
                            }
                        }
                }
            }
        }
    }
}
