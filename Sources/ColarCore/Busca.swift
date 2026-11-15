// Busca: FTS5 sem acento no texto, no OCR e nos títulos, mais o nome do app, com filtros de tipo e data. Mais
// recentes primeiro.
import Foundation

public struct Filtro: Equatable {
    public enum Periodo: String, CaseIterable { case qualquer, hoje, semana, mes }
    public var tipos: Set<TipoItem> = []          // vazio = todos
    public var periodo: Periodo = .qualquer
    public init(tipos: Set<TipoItem> = [], periodo: Periodo = .qualquer) { self.tipos = tipos; self.periodo = periodo }
    public var vazio: Bool { tipos.isEmpty && periodo == .qualquer }

    /// Início do período (meia-noite de hoje para "hoje"; 7 e 30 dias para trás).
    public func desde(_ agora: Date, calendario: Calendar = .current) -> Date? {
        switch periodo {
        case .qualquer: return nil
        case .hoje: return calendario.startOfDay(for: agora)
        case .semana: return agora.addingTimeInterval(-7 * 86_400)
        case .mes: return agora.addingTimeInterval(-30 * 86_400)
        }
    }
}

public extension Historico {
    /// Palavras da consulta: só letras e números (aspas, *, -, parênteses da sintaxe FTS5 nunca chegam ao MATCH).
    static func termos(_ consulta: String) -> [String] {
        consulta.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Busca no histórico ou, com `pinboard`, dentro dele (na ordem do pinboard). Consulta e filtros vazios = tudo.
    func buscar(_ consulta: String, filtro: Filtro = Filtro(), pinboard: String? = nil, limite: Int = 200,
                agora: Date = Date()) throws -> [Item] {
        var params: [SQLite.Valor] = []
        var sql = "SELECT i.*, a.nome AS app_nome FROM item i LEFT JOIN app a ON a.bundle_id = i.app_bundle"
        if let pinboard {
            sql += " JOIN pinboard_item p ON p.item_id = i.id AND p.pinboard_id = ? WHERE i.apagado = 0"
            params.append(.texto(pinboard))
        } else {
            sql += " WHERE i.apagado = 0 AND i.no_historico = 1"
        }
        // Cada palavra precisa casar (E): no índice (prefixo, sem acento) ou no nome/bundle do app.
        for termo in Self.termos(consulta) {
            sql += " AND (i.rowid IN (SELECT rowid FROM item_fts WHERE item_fts MATCH ?) OR a.nome LIKE ? OR i.app_bundle LIKE ?)"
            params += [.texto("\"\(termo)\"*"), .texto("%\(termo)%"), .texto("%\(termo)%")]
        }
        if !filtro.tipos.isEmpty {
            sql += " AND i.tipo IN (\(filtro.tipos.map { _ in "?" }.joined(separator: ",")))"
            params += filtro.tipos.sorted { $0.rawValue < $1.rawValue }.map { .texto($0.rawValue) }
        }
        if let desde = filtro.desde(agora) {
            sql += " AND i.usado_em >= ?"
            params.append(.real(desde.timeIntervalSince1970))
        }
        sql += pinboard == nil ? " ORDER BY i.usado_em DESC" : " ORDER BY p.ordem"
        sql += " LIMIT ?"
        params.append(.inteiro(Int64(limite)))
        return try db.consultar(sql, params).compactMap(Historico.itemDaLinha)
    }

    /// Imagens que ainda não passaram pelo OCR, mais recentes primeiro.
    func pendentesOCR(limite: Int = 50) throws -> [Item] {
        try db.consultar("""
            SELECT i.*, a.nome AS app_nome FROM item i LEFT JOIN app a ON a.bundle_id = i.app_bundle
            WHERE i.apagado = 0 AND i.tipo = 'imagem' AND i.ocr IS NULL ORDER BY i.usado_em DESC LIMIT ?
            """, [.inteiro(Int64(limite))]).compactMap(Historico.itemDaLinha)
    }

    func definirOCR(_ id: String, texto: String) throws {
        try db.consultar("UPDATE item SET ocr = ? WHERE id = ?", [.texto(texto), .texto(id)])
    }
}
