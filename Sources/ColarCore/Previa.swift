// Prévia grande do item selecionado (Espaço no painel; plano F9). Janela própria não ativadora acima do painel, nos
// tokens da direção escolhida. Não usa o QLPreviewPanel porque ele exige o app ativo e a cadeia de responders.
import AppKit
import SwiftUI

public final class PreviaPanel: NSPanel {
    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        sharingType = .none
    }

    public override var canBecomeKey: Bool { false }   // o teclado continua no painel de baixo

    /// Centraliza acima do painel do Colar, na mesma tela.
    public func posicionar(acima painel: NSWindow) {
        let tela = painel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let l = min(760, tela.width - 80), a = min(480, tela.height - painel.frame.height - 60)
        setFrame(NSRect(x: tela.midX - l / 2, y: painel.frame.maxY + 12, width: l, height: a), display: false)
    }
}

/// Conteúdo completo de um item para a prévia.
public struct ConteudoPrevia {
    public let item: Item
    public let imagem: NSImage?
    public let linkImagem: NSImage?

    public init(item: Item, historico: Historico) {
        self.item = item
        let reps = (try? historico.representacoes(de: item.id)) ?? []
        if item.tipo == .imagem, let r = reps.first(where: { Coletor.utiImagem.contains($0.uti) }) {
            imagem = NSImage(data: r.dados)
        } else { imagem = nil }
        linkImagem = item.linkImagem.flatMap { historico.blob($0) }.flatMap { NSImage(data: $0) }
    }
}

public struct PreviaView: View {
    let conteudo: ConteudoPrevia
    let direcao: Direcao

    public init(conteudo: ConteudoPrevia, direcao: Direcao) { self.conteudo = conteudo; self.direcao = direcao }

    private var t: Direcao.Tokens { direcao.t }
    private var item: Item { conteudo.item }

    private static let data: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateStyle = .medium; f.timeStyle = .short
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(item.tipo.nome).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.tinta)
                Text(meta).font(.system(size: 12).monospacedDigit()).foregroundStyle(t.apoio).lineLimit(1)
                Spacer()
                Text("Espaço fecha").font(.system(size: 11)).foregroundStyle(t.apoio)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(t.faixa)
            Rectangle().fill(t.borda).frame(height: 1)
            corpo.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(t.cartao, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.borda, lineWidth: 1))
    }

    private var meta: String {
        var partes = [item.appNome ?? item.appBundle ?? "", Self.data.string(from: item.usadoEm)]
        switch item.tipo {
        case .imagem: if let l = item.largura, let a = item.altura { partes.append("\(l) × \(a)") }
        case .arquivo: partes.append(item.tamanho == 1 ? "1 arquivo" : "\(item.tamanho) arquivos")
        default: partes.append("\(item.tamanho) caracteres")
        }
        return partes.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var corpo: some View {
        switch item.tipo {
        case .imagem:
            if let img = conteudo.imagem {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
            }
        case .cor:
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: item.texto ?? "") ?? .gray)
                Text(item.texto ?? "").font(.system(size: 20, design: .monospaced)).foregroundStyle(t.tinta).textSelection(.enabled)
            }.padding(18)
        case .link:
            VStack(alignment: .leading, spacing: 12) {
                if let img = conteudo.linkImagem {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let titulo = item.linkTitulo { Text(titulo).font(.system(size: 18, weight: .semibold)).foregroundStyle(t.tinta) }
                Text(item.texto ?? "").font(.system(size: 13)).foregroundStyle(t.apoio).textSelection(.enabled)
            }.padding(18)
        case .arquivo, .texto, .richText:
            ScrollView {
                Text(item.texto ?? "").font(.system(size: 14)).foregroundStyle(t.tinta).lineSpacing(3)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        }
    }
}
