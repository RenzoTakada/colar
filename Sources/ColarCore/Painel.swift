// Painel inferior do Colar. NSPanel com .nonactivatingPanel: recebe o teclado (setas, Enter, Esc) sem ativar o Colar,
// então o app de baixo continua sendo o app da frente e é nele que o Cmd+V cai.
// sharingType = .none: a janela não aparece em print, gravação nem compartilhamento de tela (opção no menu).
import AppKit
import SwiftUI

public final class ColarPanel: NSPanel {
    public static let altura: CGFloat = 340   // 300 + a barra de busca da Fase 3

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.altura),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        sharingType = .none
        animationBehavior = .utilityWindow
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Foto do que o painel está desenhando agora (pelo próprio desenho da janela, então funciona mesmo com
    /// sharingType .none). Para diagnóstico (colar://foto).
    @discardableResult
    public func fotografar(para url: URL) -> Bool {
        guard let v = contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return false }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? png.write(to: url)) != nil
    }

    /// A ferramenta de print do macOS (⌘⇧4/⌘⇧5) está na tela? O clique dela não deve fechar o painel.
    public static func printDoSistemaAtivo() -> Bool {
        guard let janelas = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return janelas.contains { ($0[kCGWindowOwnerName as String] as? String) == "screencaptureui" }
    }

    /// Base da tela onde está o mouse, largura inteira da área útil (sem Dock e barra de menus).
    public func posicionar() {
        let mouse = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = tela?.visibleFrame else { return }
        setFrame(NSRect(x: area.minX, y: area.minY, width: area.width, height: Self.altura), display: false)
    }
}

