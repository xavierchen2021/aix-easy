import SwiftUI
import MarkdownUI

// MARK: - AI 聊天暗色 Markdown 主题

@MainActor
enum MarkdownDarkTheme {
    /// 用于列表视图的 13pt 暗色主题
    static let small = Theme()
        .text { ForegroundColor(.white); FontSize(13) }
        .code { FontFamilyVariant(.monospaced); FontSize(.em(0.9)); ForegroundColor(Color(red: 0.6, green: 0.9, blue: 0.6)) }
        .strong { FontWeight(.bold) }
        .emphasis { FontStyle(.italic) }
        .link { ForegroundColor(Color(red: 0.4, green: 0.7, blue: 1.0)) }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(18); FontWeight(.bold); ForegroundColor(.white) }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(16); FontWeight(.bold); ForegroundColor(.white) }
                .markdownMargin(top: 10, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(14); FontWeight(.semibold); ForegroundColor(.white) }
                .markdownMargin(top: 8, bottom: 4)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 8)
        }
        .codeBlock { configuration in
            if configuration.language == "mermaid" {
                MermaidContainerView(content: configuration.content)
                    .markdownMargin(top: 4, bottom: 8)
            } else {
                configuration.label
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(12); ForegroundColor(Color(red: 0.85, green: 0.85, blue: 0.85)) }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .markdownMargin(top: 4, bottom: 8)
            }
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(Color.white.opacity(0.7)) }
                    .padding(.leading, 8)
            }
            .markdownMargin(top: 4, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2)
        }

    /// 用于大窗口的 14pt 暗色主题
    static let large = Theme()
        .text { ForegroundColor(.white); FontSize(14) }
        .code { FontFamilyVariant(.monospaced); FontSize(.em(0.9)); ForegroundColor(Color(red: 0.6, green: 0.9, blue: 0.6)) }
        .strong { FontWeight(.bold) }
        .emphasis { FontStyle(.italic) }
        .link { ForegroundColor(Color(red: 0.4, green: 0.7, blue: 1.0)) }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(20); FontWeight(.bold); ForegroundColor(.white) }
                .markdownMargin(top: 14, bottom: 8)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(18); FontWeight(.bold); ForegroundColor(.white) }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(16); FontWeight(.semibold); ForegroundColor(.white) }
                .markdownMargin(top: 10, bottom: 4)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 10)
        }
        .codeBlock { configuration in
            if configuration.language == "mermaid" {
                MermaidContainerView(content: configuration.content)
                    .markdownMargin(top: 4, bottom: 10)
            } else {
                configuration.label
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(13); ForegroundColor(Color(red: 0.85, green: 0.85, blue: 0.85)) }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .markdownMargin(top: 4, bottom: 10)
            }
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(Color.white.opacity(0.7)) }
                    .padding(.leading, 8)
            }
            .markdownMargin(top: 4, bottom: 10)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 3)
        }
}
