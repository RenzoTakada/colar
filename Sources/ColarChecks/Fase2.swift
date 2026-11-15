// Checks da Fase 2: regra de colagem (modo, sempre sem formatação, ⇧, Acessibilidade), preferências,
// migração do banco v1 → v2, prévia de link e prévia grande.
import AppKit
import ColarCore
import SQLite3
import UniformTypeIdentifiers

func fase2() {
    print("\n== Fase 2")

    // Regra de colagem: todas as combinações de modo × ⇧ × "sempre sem formatação" × Acessibilidade, nos tipos aceitos.
    for tipo in TipoItem.allCases {
        for modo in ModoColar.allCases {
            for shift in [false, true] {
                for sempre in [false, true] {
                    for acesso in [false, true] {
                        let c = Regras.colagem(tipo: tipo, shift: shift, modo: modo, sempreTextoPuro: sempre, temAcessibilidade: acesso)
                        let esperadoPuro = (shift != sempre) && tipo != .imagem && tipo != .arquivo
                        let esperadoPostar = modo == .appAtivo && acesso
                        if c.textoPuro != esperadoPuro || c.postarCmdV != esperadoPostar {
                            check("colagem \(tipo) \(modo) ⇧\(shift) sempre\(sempre) acesso\(acesso)", false, "\(c)")
                        }
                    }
                }
            }
        }
    }
    check("regra de colagem certa nas \(TipoItem.allCases.count * 2 * 2 * 2 * 2) combinações", true)
    check("⇧ com 'sempre sem formatação' cola formatado",
          !Regras.colagem(tipo: .richText, shift: true, modo: .appAtivo, sempreTextoPuro: true, temAcessibilidade: true).textoPuro)
    check("modo 'só copiar' nunca posta Cmd+V",
          Regras.colagem(tipo: .texto, shift: false, modo: .areaTransferencia, sempreTextoPuro: false, temAcessibilidade: true)
            == Colagem(textoPuro: false, postarCmdV: false, motivo: "modo só copiar"))

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colar-f2-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    // Migração: um banco no esquema v1 abre na versão atual sem perder item.
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let v1 = try? SQLite(caminho: dir.appendingPathComponent("colar.sqlite").path) {
        try? v1.executar("""
        CREATE TABLE app (bundle_id TEXT PRIMARY KEY, nome TEXT NOT NULL);
        CREATE TABLE item (id TEXT PRIMARY KEY, tipo TEXT NOT NULL, titulo TEXT, texto TEXT, checksum TEXT NOT NULL UNIQUE,
          app_bundle TEXT, aparelho TEXT NOT NULL, tamanho INTEGER NOT NULL, largura INTEGER, altura INTEGER, miniatura TEXT,
          criado_em REAL NOT NULL, atualizado_em REAL NOT NULL, usado_em REAL NOT NULL, apagado INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX item_recentes ON item(apagado, usado_em DESC);
        CREATE TABLE item_tipo (item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, indice_pb INTEGER NOT NULL,
          ordem INTEGER NOT NULL, uti TEXT NOT NULL, blob TEXT NOT NULL, tamanho INTEGER NOT NULL, PRIMARY KEY (item_id, indice_pb, uti));
        CREATE INDEX item_tipo_blob ON item_tipo(blob);
        CREATE TABLE config (chave TEXT PRIMARY KEY, valor TEXT NOT NULL);
        INSERT INTO item(id, tipo, texto, checksum, aparelho, tamanho, criado_em, atualizado_em, usado_em)
          VALUES('v1', 'texto', 'Outra opção é', 'texto:v1', 'Mac', 15, 1, 1, \(Date().timeIntervalSince1970));
        PRAGMA user_version = 1;
        """)
    }
    guard let h = try? Historico(diretorio: dir, aparelho: "Mac de teste") else { check("migração v1 → v2 abre", false); return }
    let versao = (try? h.db.consultar("PRAGMA user_version"))?.first?.inteiro("user_version")
    check("migração v1 → atual (user_version 4)", versao == 4, "\(String(describing: versao))")
    check("item do banco v1 sobrevive à migração", (try? h.item(id: "v1"))?.texto == "Outra opção é")

    // Preferências: padrões (colar no app ativo, sons ligados, sem texto puro) e persistência.
    check("padrão: colar no app ativo", h.modoColar == .appAtivo)
    check("padrão: sons ligados", h.sons)
    check("padrão: não força texto puro", !h.sempreTextoPuro)
    h.modoColar = .areaTransferencia; h.sons = false; h.sempreTextoPuro = true
    let h2 = try? Historico(diretorio: dir)
    check("preferências persistem", h2?.modoColar == .areaTransferencia && h2?.sons == false && h2?.sempreTextoPuro == true)

    // Prévia de link: título e imagem gravados, imagem fica protegida da limpeza de blobs.
    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.f2"))
    defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)
    pb.clearContents(); pb.setString("https://example.org/produto", forType: .string)
    guard case .gravado(.novo(let idLink)) = col.processar(col.foto()!) else { check("grava link", false); return }
    let imgLink = png(1200, 630)   // tamanho padrão de og:image
    try? h.definirPreviaLink(idLink, titulo: "Produto de exemplo", imagem: imgLink)
    let link = try? h.item(id: idLink)
    check("prévia de link grava título", link?.linkTitulo == "Produto de exemplo")
    check("prévia de link grava imagem", link?.linkImagem.flatMap { h.blob($0) } == imgLink)
    _ = try? h.aplicarRetencao(.mes)
    check("limpeza de blobs não apaga a imagem do link", (try? h.item(id: idLink))?.linkImagem.flatMap { h.blob($0) } != nil)

    // Prévia grande de imagem usa o original (1896 × 285), não a miniatura de 640.
    pb.clearContents(); pb.setData(png(1896, 285), forType: .png)
    guard case .gravado(.novo(let idImg)) = col.processar(col.foto()!), let itImg = try? h.item(id: idImg) else {
        check("grava imagem", false); return
    }
    let conteudo = ConteudoPrevia(item: itImg, historico: h)
    let rep = conteudo.imagem.flatMap { $0.representations.first }
    check("prévia mostra a imagem original 1896 × 285", rep?.pixelsWide == 1896 && rep?.pixelsHigh == 285,
          "\(String(describing: rep?.pixelsWide))×\(String(describing: rep?.pixelsHigh))")
    check("prévia de texto não carrega imagem", ConteudoPrevia(item: (try? h.item(id: "v1"))!, historico: h).imagem == nil)
}
