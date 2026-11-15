// Editor de item (⌘E) e de item novo (⌘N), e a janelinha da fila de colagem. Nos tokens da direção escolhida.
import AppKit
import SwiftUI

/// Janela que aceita teclado de verdade (o editor precisa digitar), sem ativar o Colar.
public final class JanelaEditor: NSPanel {
    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        sharingType = .none
    }
    public override var canBecomeKey: Bool { true }

    public func posicionar(acima painel: NSWindow) {
        let tela = painel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        setFrame(NSRect(x: tela.midX - 280, y: painel.frame.maxY + 12, width: 560, height: 380), display: false)
    }
}

public struct EditorView: View {
    public enum Modo { case editar(Item), novo(pinboard: String?, nomePinboard: String?) }
    let modo: Modo
    let t: Direcao.Tokens
    let salvar: (_ titulo: String, _ conteudo: String?) -> String?   // devolve a mensagem de erro, ou nil
    let cancelar: () -> Void

    @State private var titulo: String
    @State private var conteudo: String
    @State private var erro: String?
    @FocusState private var foco: Campo?
    enum Campo { case titulo, conteudo }

    public init(modo: Modo, direcao: Direcao, salvar: @escaping (String, String?) -> String?, cancelar: @escaping () -> Void) {
        self.modo = modo
        self.t = direcao.t
        self.salvar = salvar
        self.cancelar = cancelar
        switch modo {
        case .editar(let it): _titulo = State(initialValue: it.titulo ?? ""); _conteudo = State(initialValue: it.texto ?? "")
        case .novo: _titulo = State(initialValue: ""); _conteudo = State(initialValue: "")
        }
    }

    private var conteudoEditavel: Bool {
        if case .editar(let it) = modo { return ![.imagem, .arquivo].contains(it.tipo) }
        return true
    }

    private var cabecalho: String {
        switch modo {
        case .editar(let it): return "Editar \(it.tipo.nome.lowercased())"
        case .novo(_, let nome): return nome.map { "Novo item em \($0)" } ?? "Novo item no histórico"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cabecalho).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.tinta)
            VStack(alignment: .leading, spacing: 4) {
                Text("Título").font(.system(size: 12)).foregroundStyle(t.apoio)
                TextField("", text: $titulo, prompt: Text("Opcional").foregroundStyle(t.apoio))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(t.tinta)
                    .padding(8).background(t.faixa, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.borda, lineWidth: 1))
                    .focused($foco, equals: .titulo)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(conteudoEditavel ? "Conteúdo" : "Conteúdo (imagem e arquivo: só o título muda)")
                    .font(.system(size: 12)).foregroundStyle(t.apoio)
                TextEditor(text: $conteudo)
                    .font(.system(size: 13)).foregroundStyle(t.tinta).scrollContentBackground(.hidden)
                    .padding(6).background(t.faixa, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.borda, lineWidth: 1))
                    .disabled(!conteudoEditavel).opacity(conteudoEditavel ? 1 : 0.55)
                    .focused($foco, equals: .conteudo)
            }
            HStack {
                if let erro { Text(erro).font(.system(size: 12)).foregroundStyle(Color(hex: "#B5452F")!) }
                Spacer()
                Button("Cancelar", action: cancelar).keyboardShortcut(.cancelAction)
                Button("Salvar") {
                    erro = salvar(titulo, conteudoEditavel ? conteudo : nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            Text("⌘↩ salva · Esc cancela").font(.system(size: 11)).foregroundStyle(t.apoio)
        }
        .padding(18)
        .background(t.cartao, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.borda, lineWidth: 1))
        .onAppear { foco = { if case .novo = modo { return .conteudo }; return .titulo }() }
    }
}

// MARK: Fila de colagem

public final class JanelaPilha: NSPanel {
    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        sharingType = .none
        isMovableByWindowBackground = true
    }
    public override var canBecomeKey: Bool { false }   // nunca rouba o teclado de quem está colando

    /// Canto superior direito da tela do mouse.
    public func posicionar() {
        let mouse = NSEvent.mouseLocation
        let tela = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
        setFrame(NSRect(x: tela.maxX - 300, y: tela.maxY - 340, width: 280, height: 320), display: false)
    }
}

public struct PilhaView: View {
    let itens: [Item]
    let colados: Int
    let t: Direcao.Tokens
    let encerrar: () -> Void

    public init(itens: [Item], colados: Int, direcao: Direcao, encerrar: @escaping () -> Void) {
        self.itens = itens; self.colados = colados; self.t = direcao.t; self.encerrar = encerrar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fila de colagem").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.tinta)
                Spacer()
                Text(colados == 0 ? "\(itens.count) na fila" : "\(colados) colados · \(itens.count) na fila")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(t.apoio)
            }
            if itens.isEmpty {
                Text("Copie o que quer colar em sequência. Cada ⌘V cola o próximo, na ordem em que você copiou.")
                    .font(.system(size: 12)).foregroundStyle(t.apoio).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(itens.enumerated()), id: \.element.id) { i, it in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(i == 0 ? t.selecao : t.apoio).frame(width: 16, alignment: .trailing)
                            Text(it.titulo ?? (it.tipo == .imagem ? "Imagem \(it.largura ?? 0) × \(it.altura ?? 0)" : (it.texto ?? "")))
                                .font(.system(size: 12, weight: i == 0 ? .semibold : .regular)).foregroundStyle(t.tinta).lineLimit(2)
                        }
                    }
                }
            }
            HStack {
                Text("⌘V cola o 1 · ⇧⌘C encerra").font(.system(size: 11)).foregroundStyle(t.apoio)
                Spacer()
                Button("Encerrar", action: encerrar).buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(t.selecao)
            }
        }
        .padding(14)
        .background(t.cartao, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.selecao.opacity(0.6), lineWidth: 1.5))
    }
}
