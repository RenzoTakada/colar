// Checks da Fase 1: captura, filtro, classificação, dedupe, colar fiel, retenção.
// Banco num diretório temporário e pasteboard nomeado: nada toca no histórico nem no clipboard reais.
// Tipos ignorados = convenção nspasteboard.org e tipos usados por gerenciadores de senha; imagens com dimensões de
// prints reais de tela (729 × 461 e 737 × 408); textos com acento, aspas, travessão e tabela em texto.
import AppKit
import ColarCore
import UniformTypeIdentifiers

func png(_ largura: Int, _ altura: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: largura, pixelsHigh: altura, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: largura, height: altura).fill()
    NSColor.white.setFill()
    NSRect(x: largura / 4, y: altura / 4, width: largura / 2, height: altura / 3).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func fase1() {
    print("\n== Fase 1")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colar-checks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let h = try? Historico(diretorio: dir, aparelho: "Mac de teste") else { check("abre o histórico", false); return }
    check("abre o histórico num diretório novo", true)
    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.fase1"))
    defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)

    /// Põe itens no pasteboard de teste e roda a captura como o timer faria.
    @discardableResult
    func copiar(_ itens: [[(String, Data)]], agora: Date = Date()) -> Coletor.Decisao {
        pb.clearContents()
        pb.writeObjects(itens.map { tipos in
            let it = NSPasteboardItem()
            for (t, d) in tipos { it.setData(d, forType: NSPasteboard.PasteboardType(t)) }
            return it
        })
        guard let f = col.foto() else { return .vazio }
        return col.processar(f, agora: agora)
    }
    func t(_ s: String) -> Data { Data(s.utf8) }
    let texto = "public.utf8-plain-text"
    func total() -> Int { (try? h.recentes(limite: 10_000).count) ?? -1 }

    /// Copia do jeito legado (declareTypes), como os apps antigos: é o único jeito de um tipo com espaço no nome entrar.
    func copiarLegado(_ tipos: [(String, Data)]) -> Coletor.Decisao {
        pb.declareTypes(tipos.map { NSPasteboard.PasteboardType($0.0) }, owner: nil)
        for (tp, d) in tipos { pb.setData(d, forType: NSPasteboard.PasteboardType(tp)) }
        guard let f = col.foto() else { return .vazio }
        return col.processar(f)
    }
    func idDe(_ d: Coletor.Decisao) -> String? {
        if case .gravado(.novo(let id)) = d { return id }
        if case .gravado(.repetido(let id)) = d { return id }
        return nil
    }

    // Filtro de privacidade: cada tipo ignorado, junto de um texto qualquer, não grava nada (jeito moderno e legado).
    for tipo in Coletor.tiposIgnorados.sorted() {
        let legado = copiarLegado([(texto, t("senha-de-teste-123")), (tipo, Data())])
        check("ignora \(tipo) (declareTypes)", { if case .ignorado = legado { return true }; return false }() && total() == 0, "\(legado)")
        if tipo.contains(" ") { continue }   // nome com espaço não é UTI válido: NSPasteboardItem recusa (conferido no macOS 27)
        let d = copiar([[(texto, t("senha-de-teste-123")), (tipo, Data())]])
        check("ignora \(tipo)", { if case .ignorado = d { return true }; return false }() && total() == 0, "\(d)")
    }

    // Texto real do print (com acentos, aspas e travessão).
    let frase = "- A reunião de sexta foi remarcada para às 15h (\"sala 2\"), e a pauta não mudou: revisão, orçamento e próximos passos."
    let d1 = copiar([[(texto, t(frase)), (Coletor.tipoOrigem, t("com.apple.Terminal"))]], agora: Date().addingTimeInterval(-120))
    let primeiro = idDe(d1).flatMap { try? h.item(id: $0) }
    check("grava texto novo", { if case .gravado(.novo) = d1 { return true }; return false }(), "\(d1)")
    check("texto guardado igual (\(frase.count) caracteres)", primeiro?.texto == frase && primeiro?.tamanho == frase.count)
    check("app de origem vem do org.nspasteboard.source", primeiro?.appBundle == "com.apple.Terminal")
    check("aparelho gravado", primeiro?.aparelho == "Mac de teste")

    // Dedupe: o mesmo texto de outro app (com HTML junto) sobe o item, não cria outro.
    let depois = Date().addingTimeInterval(-60)
    let d2 = copiar([[(texto, t(frase)), ("public.html", t("<p>\(frase)</p>"))]], agora: depois)
    check("mesmo texto de novo não duplica", { if case .gravado(.repetido) = d2 { return true }; return false }() && total() == 1, "\(d2)")
    check("repetido sobe para o topo (usado_em)", abs(idDe(d2).flatMap { try? h.item(id: $0) }?.usadoEm.timeIntervalSince(depois) ?? 99) < 0.01)

    // Tabela em texto do print (| e –) com RTF: tipo rich-text e colar fiel devolve os dois tipos.
    let tabela = "| A \"Opção um\" | 0 | 1 |\n|–|–|–|\nSem dados"
    let rtf = t("{\\rtf1\\ansi \\b Opção um\\b0 }")
    let dRico = copiar([[(texto, t(tabela)), ("public.rtf", rtf)]])
    let rico = idDe(dRico).flatMap { try? h.item(id: $0) }
    check("texto com RTF vira rich-text", rico?.tipo == .richText, "\(String(describing: rico?.tipo))")
    if let rico {
        let reps = (try? h.representacoes(de: rico.id)) ?? []
        let destino = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.destino"))
        Paster.escrever(itemId: rico.id, representacoes: reps, em: destino)
        check("colar fiel devolve o texto", destino.string(forType: .string) == tabela)
        check("colar fiel devolve o RTF", destino.data(forType: .rtf) == rtf)
        check("colar marca o item como do Colar", destino.string(forType: NSPasteboard.PasteboardType(Coletor.tipoColar)) == rico.id)
        Paster.escrever(itemId: rico.id, representacoes: reps, textoPuro: tabela, em: destino)
        check("texto puro só leva texto (sem RTF)", destino.string(forType: .string) == tabela && destino.data(forType: .rtf) == nil)
        // A captura vê a marca e só sobe o item.
        let antes = total()
        let foto = Coletor.Foto(changeCount: 0, itens: [destino.pasteboardItems!.first!.types.compactMap { tp in
            destino.pasteboardItems!.first!.data(forType: tp).map { (tp.rawValue, $0) } }], appDaFrente: nil)
        let d3 = col.processar(foto)
        check("o que o Colar colou não vira item novo", d3 == .colarProprio(rico.id) && total() == antes, "\(d3)")
        destino.releaseGlobally()
    }

    // Imagens com dimensões de prints de tela.
    for (l, a) in [(729, 461), (737, 408)] {
        let img = idDe(copiar([[(UTType.png.identifier, png(l, a))]])).flatMap { try? h.item(id: $0) }
        check("imagem \(l) × \(a): tipo e dimensões", img?.tipo == .imagem && img?.largura == l && img?.altura == a,
              "\(String(describing: img?.tipo)) \(String(describing: img?.largura))×\(String(describing: img?.altura))")
        let mini = img?.miniatura.flatMap { h.blob($0) }.flatMap { NSImage(data: $0) }
        check("imagem \(l) × \(a): miniatura até 640 px", mini.map { max($0.size.width, $0.size.height) <= 640 } ?? false)
    }

    // Link, cor e arquivo (regras de detecção).
    func gravado(_ itens: [[(String, Data)]]) -> Item? { idDe(copiar(itens)).flatMap { try? h.item(id: $0) } }
    check("URL sozinha vira link", gravado([[(texto, t("https://example.org/produto"))]])?.tipo == .link)
    let cor = gravado([[(texto, t("#ff0000"))]])
    check("#RRGGBB vira cor normalizada", cor?.tipo == .cor && cor?.texto == "#FF0000")
    check("frase com URL continua texto", gravado([[(texto, t("veja https://example.org/produto"))]])?.tipo == .texto)
    let arqs = [URL(fileURLWithPath: "/Applications/Colar.app"), URL(fileURLWithPath: "/Applications/Safari.app")]
    let arq = gravado(arqs.map { [("public.file-url", $0.dataRepresentation)] })
    check("dois arquivos do Finder viram 1 item arquivo", arq?.tipo == .arquivo && arq?.tamanho == 2)
    check("arquivo guarda os 2 itens do pasteboard", Set(((try? h.representacoes(de: arq?.id ?? "")) ?? []).map(\.indicePb)) == [0, 1])

    // Pausa e app ignorado.
    col.pausado = true
    pb.clearContents(); pb.setString("pausado", forType: .string)
    let n0 = total()
    col.verificar()
    check("pausado não grava", total() == n0)
    col.pausado = false
    col.appsIgnorados = ["com.apple.keychainaccess"]
    let d4 = copiar([[(texto, t("do keychain")), (Coletor.tipoOrigem, t("com.apple.keychainaccess"))]])
    check("app ignorado não grava", d4 == .ignorado("app com.apple.keychainaccess") && total() == n0, "\(d4)")
    col.appsIgnorados = []
    copiar([[(texto, t("   \n  "))]])
    check("só espaços não grava", total() == n0)

    // Retenção "Mês" (o padrão): item de 40 dias sai, de 10 dias fica; blobs órfãos somem.
    let agora = Date()
    copiar([[(texto, t("velho de 40 dias"))]], agora: agora.addingTimeInterval(-40 * 86_400))
    copiar([[(UTType.png.identifier, png(729, 461)), (texto, t("legenda velha"))]], agora: agora.addingTimeInterval(-41 * 86_400))
    copiar([[(texto, t("de 10 dias"))]], agora: agora.addingTimeInterval(-10 * 86_400))
    let antesRet = total()
    let blobsAntes = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("blobs").path).count) ?? 0
    let removidos = (try? h.aplicarRetencao(.mes, agora: agora)) ?? -1
    let textos = ((try? h.recentes(limite: 10_000)) ?? []).compactMap(\.texto)
    check("retenção Mês remove os 2 itens de 40+ dias", removidos == 2 && total() == antesRet - 2, "removidos \(removidos)")
    check("retenção mantém o de 10 dias", textos.contains("de 10 dias") && !textos.contains("velho de 40 dias"))
    let blobsDepois = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("blobs").path).count) ?? 0
    check("retenção apaga blobs órfãos", blobsDepois < blobsAntes, "\(blobsAntes) → \(blobsDepois)")
    check("imagem 729 × 461 recente continua com miniatura", ((try? h.recentes(limite: 10_000)) ?? [])
        .filter { $0.largura == 729 }.allSatisfy { $0.miniatura.flatMap { h.blob($0) } != nil })
    check("Para sempre não remove nada", ((try? h.aplicarRetencao(.sempre, agora: agora.addingTimeInterval(9_999 * 86_400))) ?? -1) == 0)

    // Apagar.
    if let alvo = try? h.recentes().first {
        try? h.apagar(alvo.id)
        check("apagado some da lista", !((try? h.recentes()) ?? []).contains { $0.id == alvo.id })
    }
    check("retencao padrão é Mês", h.retencao == .mes)
    h.retencao = .ano
    check("retencao gravada na config", (try? Historico(diretorio: dir))?.retencao == .ano)
}
