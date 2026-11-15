// Conteúdo do painel: histórico em cartões horizontais, em três direções visuais (tokens). Superfície opaca, borda ou
// sombra, cor só na seleção e nos dados, nada abaixo de 11 px, números tabulares.
import AppKit
import SwiftUI

public final class PainelModelo: ObservableObject {
    @Published public var itens: [Item] = []
    @Published public var selecionado = 0
    @Published public var direcao: Direcao = .fio
    /// Busca e filtros (Fase 3). Mudar qualquer um recarrega na hora; com tudo vazio é o histórico normal.
    @Published public var busca = "" { didSet { if busca != oldValue { selecionado = 0; recarregar() } } }
    @Published public var filtro = Filtro() { didSet { if filtro != oldValue { selecionado = 0; recarregar() } } }
    public var buscando: Bool { !Historico.termos(busca).isEmpty || !filtro.vazio }

    /// Pinboards (Fase 4). nil = Histórico.
    @Published public private(set) var pinboards: [Pinboard] = []
    @Published public var pinboardAtual: String? { didSet { if pinboardAtual != oldValue { selecionado = 0; recarregar() } } }
    /// Aba em edição de nome: "novo" para criar, o id para renomear.
    @Published public var nomeEmEdicao: String?
    @Published public var rascunhoNome = ""
    /// Ações que dependem do app (colar, editar, pilha), ligadas pelo AppDelegate.
    public var acoes = AcoesCartao()
    /// Muda a cada recarga e é a identidade da lista inteira: força o SwiftUI a refazer todos os cartões. Sem isso o
    /// painel reabria com o desenho antigo (cartões identificados pela posição não eram redesenhados).
    @Published public private(set) var geracao = UUID()
    public let historico: Historico?
    private var cacheMini: [String: NSImage] = [:]

    public init(historico: Historico?) { self.historico = historico }

    public func recarregar() {
        pinboards = (try? historico?.pinboards()) ?? []
        if let pb = pinboardAtual, !pinboards.contains(where: { $0.id == pb }) { pinboardAtual = nil; return }
        if let pb = pinboardAtual {
            itens = (try? historico?.buscar(busca, filtro: filtro, pinboard: pb)) ?? []
        } else {
            itens = (buscando ? try? historico?.buscar(busca, filtro: filtro) : try? historico?.recentes()) ?? []
        }
        selecionado = min(selecionado, max(0, itens.count - 1))
        geracao = UUID()
    }

    public func mover(_ delta: Int) {
        guard !itens.isEmpty else { return }
        selecionado = max(0, min(itens.count - 1, selecionado + delta))
    }

    public var atual: Item? { itens.indices.contains(selecionado) ? itens[selecionado] : nil }

    /// Tab: Todos → Texto → Imagem → Link → Arquivo → Cor → Todos (⇧Tab volta).
    public static let ciclo: [Set<TipoItem>] = [[], [.texto, .richText], [.imagem], [.link], [.arquivo], [.cor]]
    public func proximoTipo(_ passo: Int = 1) {
        let i = Self.ciclo.firstIndex(of: filtro.tipos) ?? 0
        filtro.tipos = Self.ciclo[(i + passo + Self.ciclo.count) % Self.ciclo.count]
    }

    /// ⌘← / ⌘→: Histórico → pinboards → Histórico.
    public func trocarAba(_ passo: Int) {
        let abas: [String?] = [nil] + pinboards.map { Optional($0.id) }
        let i = abas.firstIndex(of: pinboardAtual) ?? 0
        pinboardAtual = abas[(i + passo + abas.count) % abas.count]
    }

    public var nomePinboardAtual: String? { pinboards.first { $0.id == pinboardAtual }?.nome }

    /// Enter numa aba em edição: cria ou renomeia. Devolve false se o nome estava vazio.
    @discardableResult
    public func confirmarNome() -> Bool {
        guard let alvo = nomeEmEdicao, let h = historico else { return false }
        defer { nomeEmEdicao = nil; rascunhoNome = "" }
        if alvo == "novo" {
            guard let novo = try? h.criarPinboard(rascunhoNome) else { return false }
            recarregar(); pinboardAtual = novo.id
        } else {
            guard (try? h.renomearPinboard(alvo, para: rascunhoNome)) != nil else { return false }
            recarregar()
        }
        return true
    }

    /// Esc: limpa a busca e os filtros; devolve false se já estava limpo (aí o Esc fecha o painel).
    public func limparBusca() -> Bool {
        if nomeEmEdicao != nil { nomeEmEdicao = nil; rascunhoNome = ""; return true }
        guard !busca.isEmpty || !filtro.vazio else { return false }
        busca = ""; filtro = Filtro()
        return true
    }

    func miniatura(_ item: Item) -> NSImage? {
        guard let h = item.miniatura ?? item.linkImagem else { return nil }
        if let c = cacheMini[h] { return c }
        guard let url = historico?.urlBlob(h), let img = NSImage(contentsOf: url) else { return nil }
        cacheMini[h] = img
        return img
    }
}

/// O que o menu de contexto de um cartão pede ao app.
public struct AcoesCartao {
    public var colar: (Int, Bool) -> Void = { _, _ in }
    public var editar: (Item) -> Void = { _ in }
    public var pilha: (Item) -> Void = { _ in }
    public var apagar: (Item) -> Void = { _ in }
    public init() {}
}

/// Direção visual do painel. Cada uma é um conjunto de tokens; a escolhida vira a padrão.
public enum Direcao: String, CaseIterable {
    case vitrine, carvao, fio

    struct Tokens {
        let chao: Color, cartao: Color, borda: Color, tinta: Color, apoio: Color, faixa: Color
        let selecao: Color, raio: CGFloat, sombra: Bool, temFio: Bool
    }

    var t: Tokens {
        switch self {
        case .vitrine:   // papel opaco, cartão branco com borda fina, tinta quase preta na seleção
            return Tokens(chao: Color(hex: "#F3F2EE")!, cartao: .white, borda: Color(hex: "#E4E1DA")!,
                          tinta: Color(hex: "#17181A")!, apoio: Color(hex: "#6E6B66")!, faixa: Color(hex: "#F7F6F3")!,
                          selecao: Color(hex: "#17181A")!, raio: 12, sombra: false, temFio: false)
        case .carvao:    // carvão neutro (preto puro fica pesado demais), âmbar só na seleção
            return Tokens(chao: Color(hex: "#161616")!, cartao: Color(hex: "#1F1F1F")!, borda: Color(hex: "#2C2C2C")!,
                          tinta: Color(hex: "#EDEDED")!, apoio: Color(hex: "#9A9A9A")!, faixa: Color(hex: "#252525")!,
                          selecao: Color(hex: "#E8B45A")!, raio: 12, sombra: false, temFio: false)
        case .fio:       // o colar: fio dourado passando pelo topo dos cartões, cada um preso por um nó
            return Tokens(chao: Color(hex: "#EFECE6")!, cartao: Color(hex: "#FFFDF9")!, borda: Color(hex: "#E2DCD1")!,
                          tinta: Color(hex: "#1D1B18")!, apoio: Color(hex: "#76706A")!, faixa: Color(hex: "#F6F2EA")!,
                          selecao: Color(hex: "#C8923A")!, raio: 14, sombra: true, temFio: true)
        }
    }
}

public struct PainelView: View {
    @ObservedObject var modelo: PainelModelo
    let aoEscolher: (Int) -> Void

    public init(modelo: PainelModelo, aoEscolher: @escaping (Int) -> Void) {
        self.modelo = modelo
        self.aoEscolher = aoEscolher
    }

    private var t: Direcao.Tokens { modelo.direcao.t }
    static let largura: CGFloat = 216, espaco: CGFloat = 18

    public var body: some View {
        VStack(spacing: 0) {
            BarraBusca(modelo: modelo, t: t)
            cartoes
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.chao, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(t.borda, lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var cartoes: some View {
        ScrollViewReader { rolagem in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    if t.temFio { Fio(quantos: modelo.itens.count, selecionado: modelo.selecionado, cor: t.selecao) }
                    LazyHStack(alignment: .top, spacing: Self.espaco) {
                        if modelo.itens.isEmpty {
                            Text(modelo.buscando ? "Nada encontrado."
                                 : modelo.pinboardAtual != nil ? "Pinboard vazio. Arraste um cartão do Histórico até a aba dele, ou ⌘N para criar um item."
                                 : "Nada copiado ainda. Copie algo e abra de novo.")
                                .font(.system(size: 14)).foregroundStyle(t.apoio).frame(height: 220)
                        }
                        // Identidade = id do item (nunca a posição: com .id(indice) o SwiftUI reaproveitava o cartão antigo).
                        ForEach(Array(modelo.itens.enumerated()), id: \.element.id) { indice, item in
                            Cartao(item: item, mini: modelo.miniatura(item), numero: indice + 1,
                                   selecionado: indice == modelo.selecionado, t: t)
                                .draggable(item.id)
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let pb = modelo.pinboardAtual, let id = ids.first, id != item.id else { return false }
                                    try? modelo.historico?.reordenar(id, antesDe: item.id, em: pb)
                                    modelo.recarregar(); return true
                                }
                                .contextMenu { MenuCartao(modelo: modelo, item: item, indice: indice) }
                                .offset(y: t.temFio && indice == modelo.selecionado ? 8 : 0)
                                .animation(.easeOut(duration: 0.18), value: modelo.selecionado)
                                .onTapGesture(count: 2) { aoEscolher(indice) }
                                .onTapGesture { modelo.selecionado = indice }
                        }
                    }
                    .padding(.top, t.temFio ? 30 : 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .id(modelo.geracao)
            }
            .onChange(of: modelo.selecionado) { _, novo in
                guard modelo.itens.indices.contains(novo) else { return }
                withAnimation(.easeOut(duration: 0.15)) { rolagem.scrollTo(modelo.itens[novo].id, anchor: .center) }
            }
        }
    }
}

/// Barra de busca: o campo já vem focado ao abrir (digitar busca), filtros de tipo e período, contagem.
struct BarraBusca: View {
    @ObservedObject var modelo: PainelModelo
    let t: Direcao.Tokens
    @FocusState private var foco: Bool

    private static let tipos: [(String, Set<TipoItem>)] = [("Todos", []), ("Texto", [.texto, .richText]), ("Imagem", [.imagem]),
                                                          ("Link", [.link]), ("Arquivo", [.arquivo]), ("Cor", [.cor])]
    private static let periodos: [(String, Filtro.Periodo)] = [("Qualquer data", .qualquer), ("Hoje", .hoje),
                                                              ("7 dias", .semana), ("30 dias", .mes)]

    var body: some View {
        HStack(spacing: 14) {
            Abas(modelo: modelo, t: t)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(t.apoio)
                TextField("", text: $modelo.busca, prompt: Text("Digite para buscar").foregroundStyle(t.apoio))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(t.tinta)
                    .focused($foco).frame(width: 200)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(t.cartao, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.borda, lineWidth: 1))

            grupo(Self.tipos.map { nome, tipos in (nome, modelo.filtro.tipos == tipos, { modelo.filtro.tipos = tipos }) })
            grupo(Self.periodos.map { nome, p in (nome, modelo.filtro.periodo == p, { modelo.filtro.periodo = p }) })
            Spacer(minLength: 0)
            Text(contagem).font(.system(size: 12).monospacedDigit()).foregroundStyle(t.apoio)
        }
        .padding(.horizontal, 24).padding(.top, 14)
        .onAppear { foco = true }
        .onChange(of: modelo.nomeEmEdicao) { _, novo in if novo == nil { foco = true } }
    }

    private var contagem: String {
        let n = modelo.itens.count
        return n == 1 ? "1 item" : "\(n) itens"
    }

    /// Botões de filtro: texto cinza, o ativo em tinta com fundo do cartão (sem cor de marca; app-screens §13).
    private func grupo(_ opcoes: [(String, Bool, () -> Void)]) -> some View {
        HStack(spacing: 2) {
            ForEach(opcoes.indices, id: \.self) { i in
                let (nome, ativo, acao) = opcoes[i]
                Button(action: acao) {
                    Text(nome).font(.system(size: 12, weight: ativo ? .semibold : .regular))
                        .foregroundStyle(ativo ? t.tinta : t.apoio)
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(ativo ? t.cartao : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ativo ? t.borda : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Abas: Histórico, os pinboards (bolinha de cor) e "+". Soltar um cartão numa aba fixa o item nela.
struct Abas: View {
    @ObservedObject var modelo: PainelModelo
    let t: Direcao.Tokens
    @FocusState private var focoNome: Bool

    var body: some View {
        HStack(spacing: 2) {
            aba(nome: "Histórico", cor: nil, ativo: modelo.pinboardAtual == nil) { modelo.pinboardAtual = nil }
            ForEach(modelo.pinboards) { pb in
                if modelo.nomeEmEdicao == pb.id { campoNome } else {
                    aba(nome: pb.nome, cor: Color(hex: pb.cor), ativo: modelo.pinboardAtual == pb.id) { modelo.pinboardAtual = pb.id }
                        .dropDestination(for: String.self) { ids, _ in
                            for id in ids { try? modelo.historico?.fixar(id, em: pb.id) }
                            modelo.recarregar(); return true
                        }
                        .contextMenu {
                            Button("Renomear…") { modelo.rascunhoNome = pb.nome; modelo.nomeEmEdicao = pb.id }
                            Menu("Cor") {
                                ForEach(Historico.coresPinboard, id: \.self) { c in
                                    Button(c == pb.cor ? "● \(nomeCor(c))" : nomeCor(c)) {
                                        try? modelo.historico?.mudarCorPinboard(pb.id, para: c); modelo.recarregar()
                                    }
                                }
                            }
                            Divider()
                            Button("Apagar pinboard (os itens ficam no histórico)") {
                                try? modelo.historico?.apagarPinboard(pb.id); modelo.recarregar()
                            }
                        }
                }
            }
            if modelo.nomeEmEdicao == "novo" { campoNome } else {
                Button { modelo.rascunhoNome = ""; modelo.nomeEmEdicao = "novo" } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(t.apoio)
                        .frame(width: 26, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Novo pinboard")
            }
        }
    }

    private func nomeCor(_ hex: String) -> String {
        ["#B5452F": "Vermelho", "#C8923A": "Dourado", "#3F7D5A": "Verde", "#1D5BD8": "Azul", "#2E7C86": "Petróleo",
         "#6E6B66": "Cinza"][hex] ?? hex
    }

    private var campoNome: some View {
        TextField("", text: $modelo.rascunhoNome, prompt: Text("Nome do pinboard").foregroundStyle(t.apoio))
            .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(t.tinta)
            .padding(.horizontal, 8).frame(width: 150, height: 24)
            .background(t.cartao, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.selecao, lineWidth: 1))
            .focused($focoNome).onAppear { focoNome = true }
            .onSubmit { modelo.confirmarNome() }
    }

    private func aba(nome: String, cor: Color?, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                if let cor { Circle().fill(cor).frame(width: 8, height: 8) }
                Text(nome).font(.system(size: 12, weight: ativo ? .semibold : .regular)).foregroundStyle(ativo ? t.tinta : t.apoio)
            }
            .padding(.horizontal, 9).frame(height: 24)
            .background(ativo ? t.cartao : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ativo ? t.borda : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Menu do botão direito num cartão.
struct MenuCartao: View {
    @ObservedObject var modelo: PainelModelo
    let item: Item
    let indice: Int

    var body: some View {
        Button("Colar") { modelo.acoes.colar(indice, false) }
        if ![.imagem, .arquivo].contains(item.tipo) { Button("Colar sem formatação") { modelo.acoes.colar(indice, true) } }
        Divider()
        Menu("Fixar em") {
            let ja = (try? modelo.historico?.pinboardsDo(item.id)) ?? []
            ForEach(modelo.pinboards) { pb in
                Button(ja.contains(pb.id) ? "✓ \(pb.nome)" : pb.nome) {
                    try? modelo.historico?.fixar(item.id, em: pb.id); modelo.recarregar()
                }
            }
            if !modelo.pinboards.isEmpty { Divider() }
            Button("Novo pinboard…") { modelo.rascunhoNome = ""; modelo.nomeEmEdicao = "novo" }
        }
        if let pb = modelo.pinboardAtual {
            Button("Remover deste pinboard") { try? modelo.historico?.desafixar(item.id, de: pb); modelo.recarregar() }
        }
        Button("Editar…  ⌘E") { modelo.acoes.editar(item) }
        Button("Pôr na fila de colagem  ⌥↩") { modelo.acoes.pilha(item) }
        Divider()
        Button("Apagar  ⌘⌫") { modelo.acoes.apagar(item) }
    }
}

/// O fio do colar: uma curva rasa passando pelo topo de cada cartão, com um nó em cada um. No cartão escolhido o fio
/// desce junto (o cartão "pesa").
struct Fio: View {
    let quantos: Int
    let selecionado: Int
    let cor: Color

    var body: some View {
        Canvas { ctx, tamanho in
            guard quantos > 0 else { return }
            let passo = PainelView.largura + PainelView.espaco
            let y0: CGFloat = 20
            var caminho = Path()
            caminho.move(to: CGPoint(x: -24, y: y0))
            for i in 0..<quantos {
                let x = CGFloat(i) * passo + PainelView.largura / 2
                let y = y0 + (i == selecionado ? 8 : 0) + 4
                let anterior = i == 0 ? CGPoint(x: -24, y: y0) : CGPoint(x: CGFloat(i - 1) * passo + PainelView.largura / 2,
                                                                           y: y0 + (i - 1 == selecionado ? 8 : 0) + 4)
                caminho.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: (anterior.x + x) / 2, y: max(anterior.y, y) + 7))
            }
            let ultimo = CGFloat(quantos - 1) * passo + PainelView.largura / 2
            caminho.addQuadCurve(to: CGPoint(x: tamanho.width + 24, y: y0), control: CGPoint(x: (ultimo + tamanho.width) / 2, y: y0 + 10))
            ctx.stroke(caminho, with: .color(cor.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            for i in 0..<quantos {
                let x = CGFloat(i) * passo + PainelView.largura / 2
                let y = y0 + (i == selecionado ? 8 : 0) + 4
                let r: CGFloat = i == selecionado ? 5 : 3.5
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(cor))
            }
        }
        .frame(height: 40)
        .allowsHitTesting(false)
    }
}

struct Cartao: View {
    let item: Item
    let mini: NSImage?
    let numero: Int
    let selecionado: Bool
    let t: Direcao.Tokens

    private static let relativo: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: t.raio, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            cabecalho
            Rectangle().fill(t.borda).frame(height: 1)
            corpo.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(rodape).font(.system(size: 11).monospacedDigit()).foregroundStyle(t.apoio).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 9).padding(.top, 4)
        }
        .frame(width: PainelView.largura, height: 224)
        .background(t.cartao, in: forma)
        .clipShape(forma)
        .overlay(forma.strokeBorder(selecionado ? t.selecao : t.borda, lineWidth: selecionado ? 2 : 1))
        .shadow(color: .black.opacity(t.sombra ? 0.07 : 0), radius: 5, y: 2)
    }

    private var cabecalho: some View {
        HStack(alignment: .center, spacing: 8) {
            if let icone { Image(nsImage: icone).resizable().frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.titulo ?? item.tipo.nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.tinta).lineLimit(1)
                Text(Self.relativo.localizedString(for: item.usadoEm, relativeTo: Date()))
                    .font(.system(size: 11)).foregroundStyle(t.apoio)
            }
            Spacer(minLength: 0)
            if numero <= 9 {
                Text("⌘\(numero)").font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(selecionado ? t.selecao : t.apoio)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(t.faixa)
        .help(item.appNome ?? "")
    }

    @ViewBuilder private var corpo: some View {
        switch item.tipo {
        case .imagem:
            if let mini {
                Image(nsImage: mini).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(10)
            } else {
                Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(t.apoio).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .cor:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: item.texto ?? "") ?? .gray).frame(height: 84)
                Text(item.texto ?? "").font(.system(size: 13, design: .monospaced)).foregroundStyle(t.tinta)
            }.padding(12)
        case .arquivo:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "doc").font(.system(size: 20)).foregroundStyle(t.apoio)
                Text(item.texto ?? "").font(.system(size: 12)).foregroundStyle(t.tinta).lineLimit(6)
            }.padding(12)
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                if let mini {
                    // Quadro fixo primeiro, imagem por cima e recortada: com .fill direto, a imagem alargava o cartão
                    // e empurrava o texto para fora pela esquerda (título cortado na borda).
                    Color.clear.frame(height: 78).frame(maxWidth: .infinity)
                        .overlay(Image(nsImage: mini).resizable().aspectRatio(contentMode: .fill))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text(item.linkTitulo ?? URL(string: item.texto ?? "")?.host ?? "")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(t.tinta).lineLimit(2)
                Text(URL(string: item.texto ?? "")?.host ?? item.texto ?? "").font(.system(size: 11)).foregroundStyle(t.apoio).lineLimit(1)
            }.padding(10)
        case .texto, .richText:
            Text(item.texto ?? "").font(.system(size: 12)).foregroundStyle(t.tinta).lineSpacing(2).lineLimit(9).padding(12)
        }
    }

    private var rodape: String {
        switch item.tipo {
        case .imagem: if let l = item.largura, let a = item.altura { return "\(l) × \(a)" }; return "Imagem"
        case .arquivo: return item.tamanho == 1 ? "1 arquivo" : "\(item.tamanho) arquivos"
        case .cor: return "Cor"
        case .link: return "Link"
        default: return "\(item.tamanho) caracteres"
        }
    }

    private var icone: NSImage? {
        guard let b = item.appBundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

extension Color {
    init?(hex: String) {
        let h = hex.replacingOccurrences(of: "#", with: "")
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
