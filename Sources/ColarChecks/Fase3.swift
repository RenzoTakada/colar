// Checks da Fase 3: busca (FTS5 sem acento, prefixo, E entre palavras, nome do app), filtros de tipo e período,
// OCR nas imagens, migração v2 → v3 com o índice reconstruído, consulta com sintaxe FTS não quebra.
// Dados de exemplo: uma imagem com texto para o OCR, um texto com acento, um link com título, itens de apps diferentes.
import AppKit
import ColarCore
import UniformTypeIdentifiers

/// PNG com texto escuro sobre fundo claro, para o OCR ler.
func pngComTexto(_ linhas: [String], largura: Int = 740, altura: Int = 400) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: largura, pixelsHigh: altura, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: largura, height: altura).fill()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.black]
    for (i, l) in linhas.enumerated() {
        (l as NSString).draw(at: NSPoint(x: 30, y: altura - 70 - i * 56), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func fase3() {
    print("\n== Fase 3")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colar-f3-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let h = try? Historico(diretorio: dir, aparelho: "Mac de teste") else { check("abre o histórico", false); return }
    let versao = (try? h.db.consultar("PRAGMA user_version"))?.first?.inteiro("user_version")
    check("banco novo em user_version 4 (fts da v3 incluído)", versao == 4, "\(String(describing: versao))")

    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.f3"))
    defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)
    let agora = Date()
    @discardableResult
    func copiar(_ tipos: [(String, Data)], diasAtras: Double = 0) -> String? {
        pb.clearContents()
        let it = NSPasteboardItem()
        // Origem explícita em todo item: sem ela o app de origem é o que estiver na frente na hora do teste, e a busca
        // pelo nome do app passaria a depender da tela de quem roda (ex.: "whatsapp" com o WhatsApp aberto).
        let comOrigem = tipos.contains { $0.0 == Coletor.tipoOrigem } ? tipos : tipos + [(Coletor.tipoOrigem, Data("com.apple.TextEdit".utf8))]
        for (t, d) in comOrigem { it.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        pb.writeObjects([it])
        if case .gravado(.novo(let id)) = col.processar(col.foto()!, agora: agora.addingTimeInterval(-diasAtras * 86_400)) { return id }
        return nil
    }
    let txt = "public.utf8-plain-text", origem = Coletor.tipoOrigem
    let idPlanilha = copiar([(txt, Data("\"A equipe ainda controla tudo em planilha, caderno e WhatsApp?\"".utf8)), (origem, Data("com.apple.Terminal".utf8))])
    let idAcento = copiar([(txt, Data("Colar: acentuação área, ação, pão".utf8))], diasAtras: 10)
    let idVelho = copiar([(txt, Data("caderno antigo de 40 dias".utf8))], diasAtras: 40)
    let idLink = copiar([(txt, Data("https://example.com/guia-de-atalhos".utf8)), (origem, Data("com.google.Chrome".utf8))])
    if let idLink { try? h.definirPreviaLink(idLink, titulo: "Guia de atalhos do teclado - Exemplo", imagem: nil) }
    let idImg = copiar([(UTType.png.identifier, pngComTexto(["Você já conferiu a lista?", "Pedido número 42, digitado"])),
                        (origem, Data("com.google.Chrome".utf8))])

    func ids(_ q: String, _ f: Filtro = Filtro()) -> [String] { ((try? h.buscar(q, filtro: f, agora: agora)) ?? []).map(\.id) }

    check("busca por palavra acha o texto (\"planilha\")", ids("planilha") == [idPlanilha].compactMap { $0 })
    check("busca por prefixo (\"plan\")", ids("plan").contains(idPlanilha ?? "-"))
    check("duas palavras = E (\"caderno whatsapp\" acha só a planilha)", ids("caderno whatsapp") == [idPlanilha].compactMap { $0 })
    check("sem acento acha com acento (\"acentuacao area\")", ids("acentuacao area") == [idAcento].compactMap { $0 })
    check("com acento acha também (\"área\")", ids("área") == [idAcento].compactMap { $0 })
    check("maiúscula não importa (\"PLANILHA\")", ids("PLANILHA") == [idPlanilha].compactMap { $0 })
    check("título do link entra na busca (\"guia atalhos\")", ids("guia atalhos") == [idLink].compactMap { $0 })
    check("nome do app entra na busca (\"chrome\" acha link e imagem)", Set(ids("chrome")) == Set([idLink, idImg].compactMap { $0 }))
    check("palavra que não existe não acha nada", ids("inexistentezzz").isEmpty)
    for q in ["\"planilha", "plan*", "-caderno", "(planilha OR", "NEAR(a b)", "\"\"", "'; DROP TABLE item; --"] {
        check("consulta com sintaxe FTS não quebra: \(q)", (try? h.buscar(q)) != nil)
    }
    check("mais recentes primeiro", ids("caderno") == [idPlanilha, idVelho].compactMap { $0 })

    // Filtros.
    check("filtro tipo Imagem", ids("", Filtro(tipos: [.imagem])) == [idImg].compactMap { $0 })
    check("filtro tipo Link + busca", ids("exemplo", Filtro(tipos: [.link])) == [idLink].compactMap { $0 })
    check("filtro 7 dias tira os de 10 e 40 dias", !ids("", Filtro(periodo: .semana)).contains(idAcento ?? "-")
          && !ids("", Filtro(periodo: .semana)).contains(idVelho ?? "-"))
    check("filtro 30 dias inclui o de 10 e tira o de 40", ids("", Filtro(periodo: .mes)).contains(idAcento ?? "-")
          && !ids("", Filtro(periodo: .mes)).contains(idVelho ?? "-"))
    check("filtro Hoje começa à meia-noite", Filtro(periodo: .hoje).desde(agora) == Calendar.current.startOfDay(for: agora))

    // OCR (Vision local): a imagem passa a ser achada pelo texto que tem dentro.
    check("imagem nova fica pendente de OCR", ((try? h.pendentesOCR()) ?? []).map(\.id) == [idImg].compactMap { $0 })
    check("antes do OCR, \"conferiu\" não acha a imagem", !ids("conferiu").contains(idImg ?? "-"))
    let reps = idImg.flatMap { try? h.representacoes(de: $0) } ?? []
    let lido = reps.first.flatMap { OCR.texto(de: $0.dados) } ?? ""
    check("OCR lê \"Você já conferiu a lista?\"", lido.contains("Você já conferiu a lista?"), "leu: \(lido.replacingOccurrences(of: "\n", with: " | "))")
    if let idImg { try? h.definirOCR(idImg, texto: lido) }
    check("depois do OCR, \"conferiu\" acha a imagem", ids("conferiu") == [idImg].compactMap { $0 })
    check("OCR sem acento (\"voce digitado\")", ids("voce digitado") == [idImg].compactMap { $0 })
    check("imagem lida sai da fila de OCR", ((try? h.pendentesOCR()) ?? []).isEmpty)
    check("OCR de imagem sem texto devolve vazio", OCR.texto(de: png(400, 300)) == "")

    // Índice acompanha apagar: item apagado de vez sai da busca.
    try? h.apagar(idPlanilha ?? "")
    _ = try? h.aplicarRetencao(.sempre)
    check("item apagado sai da busca", !ids("planilha").contains(idPlanilha ?? "-"))
    let fts = (try? h.db.consultar("INSERT INTO item_fts(item_fts) VALUES('integrity-check')")) != nil
    check("índice FTS íntegro (integrity-check)", fts)
}
