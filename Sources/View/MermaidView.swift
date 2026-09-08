import SwiftUI
import WebKit

/// 不拦截滚动事件的 WKWebView
class NonScrollableWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// 使用 WKWebView + mermaid.js 渲染 Mermaid 流程图
struct MermaidView: NSViewRepresentable {
    let content: String
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "heightCallback")
        config.userContentController = userContentController

        let webView = NonScrollableWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
                mermaid.initialize({
                    startOnLoad: false,
                    theme: 'dark',
                    themeVariables: {
                        darkMode: true,
                        background: 'transparent',
                        primaryColor: '#3a7bd5',
                        primaryTextColor: '#fff',
                        primaryBorderColor: '#5a9de6',
                        lineColor: '#8ab4f8',
                        secondaryColor: '#2d5aa0',
                        tertiaryColor: '#1a3a6e'
                    }
                });
                try {
                    const { svg } = await mermaid.render('mermaid-svg', `\(escapedContent)`);
                    document.getElementById('output').innerHTML = svg;
                    setTimeout(() => {
                        const h = document.getElementById('output').scrollHeight;
                        window.webkit.messageHandlers.heightCallback.postMessage(h);
                    }, 100);
                } catch (e) {
                    document.getElementById('output').innerHTML = '<pre style="color:#ff6b6b;">' + e.message + '</pre>';
                    window.webkit.messageHandlers.heightCallback.postMessage(80);
                }
            </script>
            <style>
                body { margin: 0; padding: 8px; background: transparent; overflow: hidden; }
                #output { background: transparent; }
                #output svg { max-width: 100%; }
            </style>
        </head>
        <body>
            <div id="output"></div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidView

        init(_ parent: MermaidView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = max(height + 16, 60)
                }
            }
        }
    }
}

/// 独立的 Mermaid 容器视图（含动态高度状态）
struct MermaidContainerView: View {
    let content: String
    @State private var height: CGFloat = 200

    var body: some View {
        MermaidView(content: content, dynamicHeight: $height)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }
}
