// Histórico do Colar: SQLite (metadados) + blobs em arquivo endereçados por SHA-256. Item com id estável e checksum
// único; os dados originais do pasteboard ficam guardados à parte, para recolar idêntico. Já leva o que um sync
// futuro vai precisar: UUID, atualizado_em, apagado lógico, aparelho.
import AppKit
import CryptoKit
import Foundation

public enum TipoItem: String, CaseIterable {
    case texto, richText = "rich-text", link, cor, imagem, arquivo

    public var nome: String {
        switch self {
        case .texto: "Texto"; case .richText: "Texto formatado"; case .link: "Link"
        case .cor: "Cor"; case .imagem: "Imagem"; case .arquivo: "Arquivo"
        }
    }
}

/// Um tipo de dado de um item do pasteboard (ex.: public.rtf), guardado como blob.
public struct Representacao: Equatable {
    public let indicePb: Int      // qual NSPasteboardItem (cópia de vários arquivos tem vários)
    public let uti: String
    public let dados: Data
    public init(indicePb: Int, uti: String, dados: Data) { self.indicePb = indicePb; self.uti = uti; self.dados = dados }
}

public struct Item: Identifiable, Equatable {
    public let id: String
    public let tipo: TipoItem
    public var titulo: String?
    public let texto: String?          // texto para mostrar e buscar (texto puro, URL, #RRGGBB, nomes de arquivo)
    public let checksum: String
    public let appBundle: String?
    public let appNome: String?
    public let aparelho: String
    public let tamanho: Int            // caracteres (texto) ou bytes (imagem/arquivo)
    public let largura: Int?
    public let altura: Int?
    public let miniatura: String?      // sha256 do PNG reduzido (imagens)
    public let linkTitulo: String?     // título da página (links)
    public let linkImagem: String?     // sha256 do PNG da imagem da página (links)
    public let ocr: String?            // texto lido da imagem (nil = ainda não lido; "" = imagem sem texto)
    public let criadoEm: Date
    public let usadoEm: Date
}

public final class Historico {
    public static let diretorioPadrao = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Colar", isDirectory: true)

    public let diretorio: URL
    public let db: SQLite
    private var blobs: URL { diretorio.appendingPathComponent("blobs", isDirectory: true) }
    public let aparelho: String

    public init(diretorio: URL = Historico.diretorioPadrao, aparelho: String = Host.current().localizedName ?? "Mac") throws {
        self.diretorio = diretorio
        self.aparelho = aparelho
        try FileManager.default.createDirectory(at: diretorio.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        db = try SQLite(caminho: diretorio.appendingPathComponent("colar.sqlite").path)
        try migrar()
    }

    // MARK: esquema

    private func migrar() throws {
        let versao = try db.consultar("PRAGMA user_version").first?.inteiro("user_version") ?? 0
        if versao < 1 {
            try db.executar("""
            CREATE TABLE app (bundle_id TEXT PRIMARY KEY, nome TEXT NOT NULL);
            CREATE TABLE item (
              id TEXT PRIMARY KEY, tipo TEXT NOT NULL, titulo TEXT, texto TEXT, checksum TEXT NOT NULL UNIQUE,
              app_bundle TEXT, aparelho TEXT NOT NULL, tamanho INTEGER NOT NULL, largura INTEGER, altura INTEGER,
              miniatura TEXT, criado_em REAL NOT NULL, atualizado_em REAL NOT NULL, usado_em REAL NOT NULL,
              apagado INTEGER NOT NULL DEFAULT 0);
            CREATE INDEX item_recentes ON item(apagado, usado_em DESC);
            CREATE TABLE item_tipo (
              item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, indice_pb INTEGER NOT NULL, ordem INTEGER NOT NULL,
              uti TEXT NOT NULL, blob TEXT NOT NULL, tamanho INTEGER NOT NULL, PRIMARY KEY (item_id, indice_pb, uti));
            CREATE INDEX item_tipo_blob ON item_tipo(blob);
            CREATE TABLE config (chave TEXT PRIMARY KEY, valor TEXT NOT NULL);
            PRAGMA user_version = 1;
            """)
        }
        if versao < 2 {
            // Prévia de link (Fase 2): título e imagem da página, buscados depois da captura.
            try db.executar("""
            ALTER TABLE item ADD COLUMN link_titulo TEXT;
            ALTER TABLE item ADD COLUMN link_imagem TEXT;
            PRAGMA user_version = 2;
            """)
        }
        if versao < 3 {
            // Fase 3: texto lido das imagens (OCR) e índice de busca FTS5 sem acento, mantido por triggers.
            try db.executar("""
            ALTER TABLE item ADD COLUMN ocr TEXT;
            CREATE VIRTUAL TABLE item_fts USING fts5(texto, ocr, titulo, link_titulo, content='item', content_rowid='rowid',
                                                    tokenize='unicode61 remove_diacritics 2');
            CREATE TRIGGER item_fts_ai AFTER INSERT ON item BEGIN
              INSERT INTO item_fts(rowid, texto, ocr, titulo, link_titulo) VALUES (new.rowid, new.texto, new.ocr, new.titulo, new.link_titulo);
            END;
            CREATE TRIGGER item_fts_ad AFTER DELETE ON item BEGIN
              INSERT INTO item_fts(item_fts, rowid, texto, ocr, titulo, link_titulo)
                VALUES ('delete', old.rowid, old.texto, old.ocr, old.titulo, old.link_titulo);
            END;
            CREATE TRIGGER item_fts_au AFTER UPDATE OF texto, ocr, titulo, link_titulo ON item BEGIN
              INSERT INTO item_fts(item_fts, rowid, texto, ocr, titulo, link_titulo)
                VALUES ('delete', old.rowid, old.texto, old.ocr, old.titulo, old.link_titulo);
              INSERT INTO item_fts(rowid, texto, ocr, titulo, link_titulo) VALUES (new.rowid, new.texto, new.ocr, new.titulo, new.link_titulo);
            END;
            INSERT INTO item_fts(item_fts) VALUES ('rebuild');
            PRAGMA user_version = 3;
            """)
        }
        if versao < 4 {
            // Fase 4: pinboards. Item fixado não sai pela retenção; item criado direto num pinboard não entra no
            // histórico (no_historico = 0), como item criado direto num pinboard.
            try db.executar("""
            CREATE TABLE pinboard (id TEXT PRIMARY KEY, nome TEXT NOT NULL, cor TEXT NOT NULL, ordem INTEGER NOT NULL,
                                   criado_em REAL NOT NULL, atualizado_em REAL NOT NULL);
            CREATE TABLE pinboard_item (pinboard_id TEXT NOT NULL REFERENCES pinboard(id) ON DELETE CASCADE,
                                        item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                                        ordem REAL NOT NULL, PRIMARY KEY (pinboard_id, item_id));
            CREATE INDEX pinboard_item_item ON pinboard_item(item_id);
            ALTER TABLE item ADD COLUMN no_historico INTEGER NOT NULL DEFAULT 1;
            PRAGMA user_version = 4;
            """)
        }
    }

    // MARK: blobs

    public static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    @discardableResult
    func gravarBlob(_ d: Data) throws -> String {
        let h = Self.sha256(d)
        let url = blobs.appendingPathComponent(h)
        if !FileManager.default.fileExists(atPath: url.path) { try d.write(to: url, options: .atomic) }
        return h
    }

    public func blob(_ hash: String) -> Data? { try? Data(contentsOf: blobs.appendingPathComponent(hash)) }
    public func urlBlob(_ hash: String) -> URL { blobs.appendingPathComponent(hash) }

    // MARK: gravar

    public enum Resultado: Equatable { case novo(String), repetido(String) }

    /// Grava um item novo ou, se o checksum já existe, só sobe o existente para o topo (usado_em).
    @discardableResult
    public func gravar(tipo: TipoItem, texto: String?, checksum: String, representacoes: [Representacao],
                       app: (bundle: String, nome: String)?, tamanho: Int, largura: Int? = nil, altura: Int? = nil,
                       miniatura: Data? = nil, agora: Date = Date()) throws -> Resultado {
        try db.transacao {
            if let existente = try db.consultar("SELECT id FROM item WHERE checksum = ?", [.texto(checksum)]).first?.texto("id") {
                try db.consultar("UPDATE item SET usado_em = ?, atualizado_em = ?, apagado = 0 WHERE id = ?",
                                 [.real(agora.timeIntervalSince1970), .real(agora.timeIntervalSince1970), .texto(existente)])
                return .repetido(existente)
            }
            let id = UUID().uuidString
            if let app {
                try db.consultar("INSERT INTO app(bundle_id, nome) VALUES(?, ?) ON CONFLICT(bundle_id) DO UPDATE SET nome = excluded.nome",
                                 [.texto(app.bundle), .texto(app.nome)])
            }
            let mini = try miniatura.map { try gravarBlob($0) }
            let t = agora.timeIntervalSince1970
            try db.consultar("""
                INSERT INTO item(id, tipo, texto, checksum, app_bundle, aparelho, tamanho, largura, altura, miniatura,
                                 criado_em, atualizado_em, usado_em) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [.texto(id), .texto(tipo.rawValue), .texto(texto), .texto(checksum), .texto(app?.bundle),
                      .texto(aparelho), .inteiro(Int64(tamanho)), largura.map { .inteiro(Int64($0)) } ?? .nulo,
                      altura.map { .inteiro(Int64($0)) } ?? .nulo, .texto(mini), .real(t), .real(t), .real(t)])
            for (ordem, r) in representacoes.enumerated() {
                let h = try gravarBlob(r.dados)
                try db.consultar("INSERT OR IGNORE INTO item_tipo(item_id, indice_pb, ordem, uti, blob, tamanho) VALUES(?,?,?,?,?,?)",
                                 [.texto(id), .inteiro(Int64(r.indicePb)), .inteiro(Int64(ordem)), .texto(r.uti), .texto(h),
                                  .inteiro(Int64(r.dados.count))])
            }
            return .novo(id)
        }
    }

    /// Item colado pelo próprio Colar: só sobe para o topo.
    public func marcarUsado(_ id: String, agora: Date = Date()) throws {
        try db.consultar("UPDATE item SET usado_em = ? WHERE id = ? AND apagado = 0", [.real(agora.timeIntervalSince1970), .texto(id)])
    }

    // MARK: ler

    public func recentes(limite: Int = 200) throws -> [Item] {
        try db.consultar("""
            SELECT i.*, a.nome AS app_nome FROM item i LEFT JOIN app a ON a.bundle_id = i.app_bundle
            WHERE i.apagado = 0 AND i.no_historico = 1 ORDER BY i.usado_em DESC LIMIT ?
            """, [.inteiro(Int64(limite))]).compactMap(Self.item)
    }

    public func item(id: String) throws -> Item? {
        try db.consultar("SELECT i.*, a.nome AS app_nome FROM item i LEFT JOIN app a ON a.bundle_id = i.app_bundle WHERE i.id = ?",
                         [.texto(id)]).first.flatMap(Self.item)
    }

    public func representacoes(de id: String) throws -> [Representacao] {
        try db.consultar("SELECT indice_pb, uti, blob FROM item_tipo WHERE item_id = ? ORDER BY indice_pb, ordem", [.texto(id)])
            .compactMap { l in
                guard let uti = l.texto("uti"), let h = l.texto("blob"), let d = blob(h) else { return nil }
                return Representacao(indicePb: l.inteiro("indice_pb") ?? 0, uti: uti, dados: d)
            }
    }

    static func itemDaLinha(_ l: [String: SQLite.Valor]) -> Item? { item(l) }

    private static func item(_ l: [String: SQLite.Valor]) -> Item? {
        guard let id = l.texto("id"), let tipo = l.texto("tipo").flatMap(TipoItem.init), let ck = l.texto("checksum") else { return nil }
        return Item(id: id, tipo: tipo, titulo: l.texto("titulo"), texto: l.texto("texto"), checksum: ck,
                    appBundle: l.texto("app_bundle"), appNome: l.texto("app_nome"), aparelho: l.texto("aparelho") ?? "",
                    tamanho: l.inteiro("tamanho") ?? 0, largura: l.inteiro("largura"), altura: l.inteiro("altura"),
                    miniatura: l.texto("miniatura"), linkTitulo: l.texto("link_titulo"), linkImagem: l.texto("link_imagem"), ocr: l.texto("ocr"),
                    criadoEm: Date(timeIntervalSince1970: l.real("criado_em") ?? 0),
                    usadoEm: Date(timeIntervalSince1970: l.real("usado_em") ?? 0))
    }

    /// Guarda o que o LinkPresentation achou da página.
    public func definirPreviaLink(_ id: String, titulo: String?, imagem: Data?) throws {
        let h = try imagem.map { try gravarBlob($0) }
        try db.consultar("UPDATE item SET link_titulo = ?, link_imagem = ? WHERE id = ?", [.texto(titulo), .texto(h), .texto(id)])
    }

    // MARK: apagar e retenção

    public func apagar(_ id: String) throws {
        try db.consultar("UPDATE item SET apagado = 1, atualizado_em = ? WHERE id = ?", [.real(Date().timeIntervalSince1970), .texto(id)])
    }

    /// Opções de "Manter histórico". Padrão: Mês.
    public enum Retencao: String, CaseIterable {
        case dia, semana, mes, ano, sempre
        public var segundos: TimeInterval? {
            switch self { case .dia: 86_400; case .semana: 7 * 86_400; case .mes: 30 * 86_400; case .ano: 365 * 86_400; case .sempre: nil }
        }
    }

    /// Apaga de vez o que saiu da janela de retenção e o que foi apagado, e os blobs que ninguém mais usa.
    /// Devolve quantos itens saíram.
    @discardableResult
    public func aplicarRetencao(_ r: Retencao, agora: Date = Date()) throws -> Int {
        let removidos = try db.transacao { () -> Int in
            if let s = r.segundos {
                try db.consultar("DELETE FROM item WHERE usado_em < ? AND id NOT IN (SELECT item_id FROM pinboard_item)",
                                 [.real(agora.timeIntervalSince1970 - s)])
            }
            let porJanela = db.mudancas
            try db.consultar("DELETE FROM item WHERE apagado = 1")
            return porJanela + db.mudancas
        }
        try limparBlobs()
        return removidos
    }

    /// "Apagar histórico": o que está fixado em pinboard fica (sai só do histórico).
    public func apagarTudo() throws {
        try db.executar("""
            DELETE FROM item WHERE id NOT IN (SELECT item_id FROM pinboard_item);
            UPDATE item SET no_historico = 0;
            """)
        try limparBlobs()
    }

    func limparBlobs() throws {
        let usados = Set(try db.consultar("SELECT blob FROM item_tipo UNION SELECT miniatura FROM item WHERE miniatura IS NOT NULL UNION SELECT link_imagem FROM item WHERE link_imagem IS NOT NULL")
            .compactMap { $0.texto("blob") ?? $0.texto("miniatura") })
        for nome in (try? FileManager.default.contentsOfDirectory(atPath: blobs.path)) ?? [] where !usados.contains(nome) {
            try? FileManager.default.removeItem(at: blobs.appendingPathComponent(nome))
        }
    }

    // MARK: config

    public func config(_ chave: String) -> String? {
        (try? db.consultar("SELECT valor FROM config WHERE chave = ?", [.texto(chave)]))?.first?.texto("valor")
    }

    public func definir(_ chave: String, _ valor: String) {
        _ = try? db.consultar("INSERT INTO config(chave, valor) VALUES(?, ?) ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor",
                              [.texto(chave), .texto(valor)])
    }

    public var retencao: Retencao {
        get { config("retencao").flatMap(Retencao.init) ?? .mes }
        set { definir("retencao", newValue.rawValue) }
    }
}
