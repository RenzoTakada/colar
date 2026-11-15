// Checks da Fase 4: pinboards, edição, item novo,
// retenção e "apagar histórico" poupando fixados, migração v3 → v4, fila de colagem e detecção do ⌘V.
// Dados de exemplo neutros; tipos e regras são os do app.
import AppKit
import Carbon
import ColarCore

func fase4() {
    print("\n== Fase 4")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colar-f4-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let h = try? Historico(diretorio: dir, aparelho: "Mac de teste") else { check("abre o histórico", false); return }
    check("banco novo em user_version 4", (try? h.db.consultar("PRAGMA user_version"))?.first?.inteiro("user_version") == 4)

    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.f4"))
    defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)
    func copiar(_ s: String, diasAtras: Double = 0) -> String {
        pb.clearContents(); pb.setString(s, forType: .string)
        if case .gravado(let r) = col.processar(col.foto()!, agora: Date().addingTimeInterval(-diasAtras * 86_400)) {
            switch r { case .novo(let id), .repetido(let id): return id }
        }
        return ""
    }
    let guia = copiar("https://example.com/guia-de-atalhos", diasAtras: 40)
    let planilha = copiar("\"A equipe ainda controla tudo em planilha, caderno e WhatsApp?\"")
    let alternativa = copiar("Outra opção é")

    // Criar, renomear, cor.
    let links = try? h.criarPinboard("Links úteis", cor: "#B5452F")
    check("cria pinboard com nome e cor", links?.nome == "Links úteis" && links?.cor == "#B5452F")
    check("nome vazio é recusado", (try? h.criarPinboard("   ")) == nil)
    let trabalho = try? h.criarPinboard("Trabalho")
    check("cor automática da paleta no 2º pinboard", trabalho?.cor == Historico.coresPinboard[1])
    check("pinboards na ordem de criação", ((try? h.pinboards()) ?? []).map(\.nome) == ["Links úteis", "Trabalho"])
    try? h.renomearPinboard(trabalho!.id, para: "  Projetos  ")
    check("renomear tira espaços", ((try? h.pinboards()) ?? []).last?.nome == "Projetos")

    // Fixar: idempotente, contagem, ordem, desafixar mantém no histórico.
    guard let L = links?.id else { return }
    try? h.fixar(guia, em: L); try? h.fixar(planilha, em: L); try? h.fixar(guia, em: L)
    let dentro = ((try? h.buscar("", pinboard: L)) ?? []).map(\.id)
    check("fixar 2x mantém uma vez só, na ordem em que entrou", dentro == [guia, planilha], "\(dentro)")
    check("contagem do pinboard", ((try? h.pinboards()) ?? []).first?.quantos == 2)
    check("fixar item inexistente dá erro", (try? h.fixar("nao-existe", em: L)) == nil)
    try? h.reordenar(planilha, antesDe: guia, em: L)
    check("reordenar põe a planilha antes do link", ((try? h.buscar("", pinboard: L)) ?? []).map(\.id) == [planilha, guia])
    check("busca dentro do pinboard (\"guia\")", ((try? h.buscar("guia", pinboard: L)) ?? []).map(\.id) == [guia])
    try? h.desafixar(planilha, de: L)
    check("desafixar tira do pinboard", ((try? h.buscar("", pinboard: L)) ?? []).map(\.id) == [guia])
    check("desafixar deixa no histórico", ((try? h.recentes()) ?? []).contains { $0.id == planilha })

    // Retenção e "apagar histórico" poupam fixados (o link tem 40 dias e retenção é Mês).
    _ = try? h.aplicarRetencao(.mes)
    check("retenção não apaga item fixado de 40 dias", (try? h.item(id: guia)) != nil)
    try? h.apagarTudo()
    check("apagar histórico esvazia o histórico", ((try? h.recentes()) ?? []).isEmpty)
    check("apagar histórico mantém o fixado no pinboard", ((try? h.buscar("", pinboard: L)) ?? []).map(\.id) == [guia])
    check("item não fixado foi apagado de vez", (try? h.item(id: alternativa)) == nil)

    // Item novo: no histórico, ou só no pinboard; conteúdo repetido reaproveita.
    let novoHist = try? h.criarItem("Para testar de novo")
    check("item novo vai para o histórico", ((try? h.recentes()) ?? []).first?.id == novoHist)
    let soNoPb = try? h.criarItem("#E8B45A", pinboard: L)
    let cor = soNoPb.flatMap { try? h.item(id: $0) }
    check("item novo num pinboard detecta cor e fica só nele", cor?.tipo == .cor
          && !((try? h.recentes()) ?? []).contains { $0.id == soNoPb } && ((try? h.buscar("", pinboard: L)) ?? []).contains { $0.id == soNoPb })
    let deNovo = try? h.criarItem("Para testar de novo", pinboard: L)
    check("criar no pinboard com conteúdo que já existe fixa o existente", deNovo == novoHist)
    check("conteúdo vazio é recusado", (try? h.criarItem("  \n ")) == nil)

    // Editar.
    if let novoHist {
        try? h.atualizarItem(novoHist, titulo: "Lembrete")
        check("título gravado", (try? h.item(id: novoHist))?.titulo == "Lembrete")
        try? h.atualizarItem(novoHist, conteudo: "https://example.org/produto")
        let ed = try? h.item(id: novoHist)
        check("editar conteúdo refaz o tipo (texto → link)", ed?.tipo == .link && ed?.texto == "https://example.org/produto")
        check("editar conteúdo troca os dados para colar", ((try? h.representacoes(de: novoHist)) ?? []).map { String(data: $0.dados, encoding: .utf8) } == ["https://example.org/produto"])
        check("busca acha pelo conteúdo novo", ((try? h.buscar("produto")) ?? []).map(\.id) == [novoHist])
        check("título vazio limpa", { try? h.atualizarItem(novoHist, titulo: ""); return (try? h.item(id: novoHist))?.titulo == nil }())
        if let soNoPb {
            check("editar para conteúdo que já existe é recusado", {
                do { try h.atualizarItem(soNoPb, conteudo: "https://example.org/produto"); return false }
                catch let e as ErroEdicao { if case .conteudoDuplicado = e { return true }; return false } catch { return false }
            }())
        }
    }
    pb.clearContents(); pb.setData(png(729, 461), forType: .png)
    if case .gravado(.novo(let img)) = col.processar(col.foto()!) {
        check("imagem: conteúdo não editável", (try? h.atualizarItem(img, conteudo: "x")) == nil)
        try? h.atualizarItem(img, titulo: "Print do formulário")
        check("imagem: título editável", (try? h.item(id: img))?.titulo == "Print do formulário")
    }

    // Apagar pinboard: fixados ficam no histórico; os que só existiam nele somem.
    try? h.apagarPinboard(L)
    check("apagar pinboard remove o pinboard", ((try? h.pinboards()) ?? []).map(\.nome) == ["Projetos"])
    check("item só do pinboard some junto", soNoPb.flatMap { try? h.item(id: $0) } == nil)
    check("item fixado que estava no histórico fica", novoHist.flatMap { try? h.item(id: $0) } != nil)

    // Fila de colagem.
    let p = PilhaColagem()
    p.adicionar("a")
    check("pilha desligada não recebe", p.vazia)
    p.ativa = true
    p.adicionar("a"); p.adicionar("a"); p.adicionar("b"); p.adicionar("c")
    check("pilha ignora o mesmo item duas vezes seguidas", p.ids == ["a", "b", "c"])
    check("pilha cola na ordem em que entrou", [p.proximo(), p.proximo()] == ["a", "b"] && p.colados == 2)
    p.ativa = false
    check("desligar esvazia a pilha", p.vazia && p.proximo() == nil)

    // Detecção do ⌘V (só ⌘V puro na tecla do layout; nada de ⇧⌘V, ⌥⌘V ou repetição).
    let fonte = CGEventSource(stateID: .privateState)
    func evento(_ k: CGKeyCode, _ f: CGEventFlags, repeticao: Bool = false) -> CGEvent {
        let e = CGEvent(keyboardEventSource: fonte, virtualKey: k, keyDown: true)!
        e.flags = f
        if repeticao { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return e
    }
    let v = CGKeyCode(kVK_ANSI_V)
    check("⌘V é ⌘V", EscutaCmdV.ehCmdV(evento(v, .maskCommand), vKeyCode: v))
    check("⇧⌘V (abre o Colar) não é ⌘V", !EscutaCmdV.ehCmdV(evento(v, [.maskCommand, .maskShift]), vKeyCode: v))
    check("⌥⌘V não é ⌘V", !EscutaCmdV.ehCmdV(evento(v, [.maskCommand, .maskAlternate]), vKeyCode: v))
    check("V sem ⌘ não é ⌘V", !EscutaCmdV.ehCmdV(evento(v, []), vKeyCode: v))
    check("⌘V segurado (repetição) não conta", !EscutaCmdV.ehCmdV(evento(v, .maskCommand, repeticao: true), vKeyCode: v))
    check("⌘C não é ⌘V", !EscutaCmdV.ehCmdV(evento(CGKeyCode(kVK_ANSI_C), .maskCommand), vKeyCode: v))
    let doColar = evento(v, .maskCommand); doColar.setIntegerValueField(.eventSourceUserData, value: Paster.marcaEvento)
    check("⌘V postado pelo próprio Colar não puxa a fila", !EscutaCmdV.ehCmdV(doColar, vKeyCode: v))
    check("no Dvorak o ⌘V é a tecla 47", EscutaCmdV.ehCmdV(evento(47, .maskCommand), vKeyCode: 47))
}
