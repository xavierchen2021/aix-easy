
import SwiftUI

struct SymbolPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedSymbol: String
    @State private var searchText = ""
    @State private var hoveredSymbol: String?
    
    // Grid layout configuration
    private let columns = [
        GridItem(.adaptive(minimum: 40, maximum: 50), spacing: 12)
    ]
    
    var filteredCategories: [SFSymbolCategory] {
        if searchText.isEmpty {
            return SFSymbols.allCategories
        } else {
            // Filter categories to only include matching symbols
            return SFSymbols.allCategories.compactMap { category in
                let matchingSymbols = category.symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
                if matchingSymbols.isEmpty { return nil }
                return SFSymbolCategory(name: category.name, icon: category.icon, symbols: matchingSymbols)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索图标...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if filteredCategories.isEmpty {
                        HStack {
                            Spacer()
                            Text(L10n.tr("symbolPicker.noMatch"))
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                            Spacer()
                        }
                    } else {
                        ForEach(filteredCategories, id: \.id) { category in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundColor(.accentColor)
                                    Text(category.name)
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(category.symbols, id: \.self) { symbol in
                                        SymbolItem(
                                            symbol: symbol, 
                                            isSelected: selectedSymbol == symbol, 
                                            action: {
                                                selectedSymbol = symbol
                                                // Give a small feedback or close
                                                // presentationMode.wrappedValue.dismiss() // Optional: auto close?
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SymbolItem: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
            }
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(symbol)
    }
}
