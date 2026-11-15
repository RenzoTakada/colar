// Pinboards, edição e item novo. Fixar é idempotente; apagar pinboard deixa os itens no histórico; criar item num
// pinboard reaproveita o que já existe com o mesmo conteúdo; editar o conteúdo refaz a detecção de tipo e não vale
// para imagem e arquivo.
import AppKit

public struct Pinboard: Identifiable, Equatable {
    public let id: String
    public var nome: String
    public var cor: String          // #RRGGBB
    public let ordem: Int
    public var quantos: Int
}

public enum ErroEdicao: Error, Equatable, CustomStringConvertible {
    case nomeVazio, conteudoVazio, naoEditavel, itemNaoExiste, pinboardNaoExiste, conteudoDuplicado(String)
    public var description: String {
        switch self {
        case .nomeVazio: "O nome não pode ficar vazio."
        case .conteudoVazio: "O conteúdo não pode ficar vazio."
        case .naoEditavel: "Imagem e arquivo não têm o conteúdo editável; o título pode mudar."
        case .itemNaoExiste: "Item não encontrado."
        case .pinboardNaoExiste: "Pinboard não encontrado."
        case .conteudoDuplicado: "Já existe um item com esse conteúdo."
        }
    }
}

public extension Historico {
    /// Cores dos pinboards, na harmonia da direção "fio" (dourado) + o azul do ícone.
    static let coresPinboard = ["#B5452F", "#C8923A", "#3F7D5A", "#1D5BD8", "#2E7C86", "#6E6B66"]

    // MARK: pinboards

    func pinboards() throws -> [Pinboard] {
        try db.consultar("""
            SELECT p.id, p.nome, p.cor, p.ordem, (SELECT count(*) FROM pinboard_item pi JOIN item i ON i.id = pi.item_id
                                                   WHERE pi.pinboard_id = p.id AND i.apagado = 0) AS quantos
            FROM pinboard p ORDER BY p.ordem
            """).compactMap { l in
            guard let id = l.texto("id"), let nome = l.texto("nome"), let cor = l.texto("cor") else { return nil }
            return Pinboard(id: id, nome: nome, cor: cor, ordem: l.inteiro("ordem") ?? 0, quantos: l.inteiro("quantos") ?? 0)
        }
    }

    @discardableResult
    func criarPinboard(_ nome: String, cor: String? = nil, agora: Date = Date()) throws -> Pinboard {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ErroEdicao.nomeVazio }
        let existentes = try pinboards()
        let c = cor ?? Self.coresPinboard[existentes.count % Self.coresPinboard.count]
        let ordem = (existentes.map(\.ordem).max() ?? -1) + 1
        let id = UUID().uuidString
        try db.consultar("INSERT INTO pinboard(id, nome, cor, ordem, criado_em, atualizado_em) VALUES(?,?,?,?,?,?)",
                         [.texto(id), .texto(n), .texto(c), .inteiro(Int64(ordem)), .real(agora.timeIntervalSince1970),
                          .real(agora.timeIntervalSince1970)])
        return Pinboard(id: id, nome: n, cor: c, ordem: ordem, quantos: 0)
    }

    func renomearPinboard(_ id: String, para nome: String) throws {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ErroEdicao.nomeVazio }
        try db.consultar("UPDATE pinboard SET nome = ?, atualizado_em = ? WHERE id = ?", [.texto(n), .real(Date().timeIntervalSince1970), .texto(id)])
        guard db.mudancas == 1 else { throw ErroEdicao.pinboardNaoExiste }
    }

    func mudarCorPinboard(_ id: String, para cor: String) throws {
        try db.consultar("UPDATE pinboard SET cor = ? WHERE id = ?", [.texto(cor), .texto(id)])
    }

    /// Apaga o pinboard. Itens fixados continuam no histórico; os que só existiam nele (criados direto no pinboard e
    /// sem outro pinboard) somem junto, para não ficar item órfão invisível.
    func apagarPinboard(_ id: String) throws {
        try db.transacao {
            try db.consultar("""
                DELETE FROM item WHERE no_historico = 0
                  AND id IN (SELECT item_id FROM pinboard_item WHERE pinboard_id = ?)
                  AND id NOT IN (SELECT item_id FROM pinboard_item WHERE pinboard_id <> ?)
                """, [.texto(id), .texto(id)])
            try db.consultar("DELETE FROM pinboard WHERE id = ?", [.texto(id)])
        }
    }

    // MARK: fixar

    /// Fixa no fim do pinboard. Idempotente: fixar de novo mantém uma vez só, no mesmo lugar.
    func fixar(_ itemId: String, em pinboard: String) throws {
        guard try item(id: itemId) != nil else { throw ErroEdicao.itemNaoExiste }
        guard try db.consultar("SELECT 1 FROM pinboard WHERE id = ?", [.texto(pinboard)]).first != nil else { throw ErroEdicao.pinboardNaoExiste }
        try db.consultar("""
            INSERT OR IGNORE INTO pinboard_item(pinboard_id, item_id, ordem)
            VALUES(?, ?, coalesce((SELECT max(ordem) FROM pinboard_item WHERE pinboard_id = ?), 0) + 1)
            """, [.texto(pinboard), .texto(itemId), .texto(pinboard)])
    }

    /// Desafixa. Item que só existia no pinboard (sem histórico, sem outro pinboard) é apagado.
    func desafixar(_ itemId: String, de pinboard: String) throws {
        try db.transacao {
            try db.consultar("DELETE FROM pinboard_item WHERE pinboard_id = ? AND item_id = ?", [.texto(pinboard), .texto(itemId)])
            try db.consultar("DELETE FROM item WHERE id = ? AND no_historico = 0 AND id NOT IN (SELECT item_id FROM pinboard_item)",
                             [.texto(itemId)])
        }
    }

    /// Move `itemId` para a posição de `antesDe` (ou para o fim, com nil) dentro do pinboard.
    func reordenar(_ itemId: String, antesDe: String?, em pinboard: String) throws {
        var ids = try buscar("", pinboard: pinboard, limite: 10_000).map(\.id)
        guard let de = ids.firstIndex(of: itemId) else { return }
        ids.remove(at: de)
        let para = antesDe.flatMap { ids.firstIndex(of: $0) } ?? ids.count
        ids.insert(itemId, at: para)
        try db.transacao {
            for (i, id) in ids.enumerated() {
                try db.consultar("UPDATE pinboard_item SET ordem = ? WHERE pinboard_id = ? AND item_id = ?",
                                 [.real(Double(i + 1)), .texto(pinboard), .texto(id)])
            }
        }
    }

    func pinboardsDo(_ itemId: String) throws -> Set<String> {
        Set(try db.consultar("SELECT pinboard_id FROM pinboard_item WHERE item_id = ?", [.texto(itemId)]).compactMap { $0.texto("pinboard_id") })
    }

    // MARK: criar e editar

    /// Cria um item de texto à mão. Tipo detectado como na captura (texto, link, cor). Sem pinboard vai para o
    /// histórico; com pinboard, fica só nele (ou fixa o item que já existe com o mesmo conteúdo).
    @discardableResult
    func criarItem(_ conteudo: String, titulo: String? = nil, pinboard: String? = nil, agora: Date = Date()) throws -> String {
        guard !conteudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ErroEdicao.conteudoVazio }
        guard let c = Coletor.classificar([[("public.utf8-plain-text", Data(conteudo.utf8))]]) else { throw ErroEdicao.conteudoVazio }
        let existente = try db.consultar("SELECT id FROM item WHERE checksum = ?", [.texto(c.checksum)]).first?.texto("id")
        let id: String
        if let existente {
            id = existente
            if pinboard == nil { try db.consultar("UPDATE item SET no_historico = 1, apagado = 0, usado_em = ? WHERE id = ?",
                                                  [.real(agora.timeIntervalSince1970), .texto(id)]) }
        } else {
            let r = try gravar(tipo: c.tipo, texto: c.texto, checksum: c.checksum,
                               representacoes: [Representacao(indicePb: 0, uti: "public.utf8-plain-text", dados: Data(conteudo.utf8))],
                               app: ("app.colar", "Colar"), tamanho: c.tamanho, agora: agora)
            guard case .novo(let novo) = r else { throw ErroEdicao.conteudoVazio }
            id = novo
            if pinboard != nil { try db.consultar("UPDATE item SET no_historico = 0 WHERE id = ?", [.texto(id)]) }
        }
        if let titulo { try atualizarItem(id, titulo: titulo) }
        if let pinboard { try fixar(id, em: pinboard) }
        return id
    }

    /// Muda o título (vazio limpa) e/ou o conteúdo. Conteúdo novo refaz o tipo e troca os dados por texto puro.
    func atualizarItem(_ id: String, titulo: String? = nil, conteudo: String? = nil, agora: Date = Date()) throws {
        guard let it = try item(id: id) else { throw ErroEdicao.itemNaoExiste }
        try db.transacao {
            if let titulo {
                let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
                try db.consultar("UPDATE item SET titulo = ?, atualizado_em = ? WHERE id = ?",
                                 [.texto(t.isEmpty ? nil : t), .real(agora.timeIntervalSince1970), .texto(id)])
            }
            if let conteudo {
                guard ![.imagem, .arquivo].contains(it.tipo) else { throw ErroEdicao.naoEditavel }
                guard let c = Coletor.classificar([[("public.utf8-plain-text", Data(conteudo.utf8))]]) else { throw ErroEdicao.conteudoVazio }
                if let outro = try db.consultar("SELECT id FROM item WHERE checksum = ? AND id <> ?", [.texto(c.checksum), .texto(id)]).first?.texto("id") {
                    throw ErroEdicao.conteudoDuplicado(outro)
                }
                try db.consultar("UPDATE item SET tipo = ?, texto = ?, checksum = ?, tamanho = ?, atualizado_em = ?, link_titulo = NULL, link_imagem = NULL WHERE id = ?",
                                 [.texto(c.tipo.rawValue), .texto(c.texto), .texto(c.checksum), .inteiro(Int64(c.tamanho)),
                                  .real(agora.timeIntervalSince1970), .texto(id)])
                try db.consultar("DELETE FROM item_tipo WHERE item_id = ?", [.texto(id)])
                let h = try gravarBlob(Data(conteudo.utf8))
                try db.consultar("INSERT INTO item_tipo(item_id, indice_pb, ordem, uti, blob, tamanho) VALUES(?, 0, 0, 'public.utf8-plain-text', ?, ?)",
                                 [.texto(id), .texto(h), .inteiro(Int64(conteudo.utf8.count))])
            }
        }
    }
}
