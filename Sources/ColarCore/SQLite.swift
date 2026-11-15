// Invólucro mínimo do sqlite3 (libsqlite3 do sistema).
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLite {
    public enum Erro: Error, CustomStringConvertible {
        case sql(String, String)
        public var description: String { if case let .sql(m, q) = self { return "\(m) em: \(q)" }; return "" }
    }

    public enum Valor { case texto(String?), real(Double), inteiro(Int64), nulo }

    private var db: OpaquePointer?

    public init(caminho: String) throws {
        guard sqlite3_open_v2(caminho, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Erro.sql(String(cString: sqlite3_errmsg(db)), "open \(caminho)")
        }
        sqlite3_busy_timeout(db, 3000)
        try executar("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
    }

    deinit { sqlite3_close(db) }

    public func executar(_ sql: String) throws {
        var msg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &msg) != SQLITE_OK {
            let m = msg.map { String(cString: $0) } ?? "?"
            sqlite3_free(msg)
            throw Erro.sql(m, sql)
        }
    }

    /// Roda uma instrução com parâmetros; devolve as linhas (cada uma como [coluna: valor]).
    @discardableResult
    public func consultar(_ sql: String, _ params: [Valor] = []) throws -> [[String: Valor]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw Erro.sql(String(cString: sqlite3_errmsg(db)), sql) }
        defer { sqlite3_finalize(st) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .texto(let s): if let s { sqlite3_bind_text(st, idx, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(st, idx) }
            case .real(let d): sqlite3_bind_double(st, idx, d)
            case .inteiro(let n): sqlite3_bind_int64(st, idx, n)
            case .nulo: sqlite3_bind_null(st, idx)
            }
        }
        var linhas: [[String: Valor]] = []
        while true {
            let r = sqlite3_step(st)
            if r == SQLITE_DONE { break }
            guard r == SQLITE_ROW else { throw Erro.sql(String(cString: sqlite3_errmsg(db)), sql) }
            var linha: [String: Valor] = [:]
            for c in 0..<sqlite3_column_count(st) {
                let nome = String(cString: sqlite3_column_name(st, c))
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: linha[nome] = .inteiro(sqlite3_column_int64(st, c))
                case SQLITE_FLOAT: linha[nome] = .real(sqlite3_column_double(st, c))
                case SQLITE_TEXT: linha[nome] = .texto(String(cString: sqlite3_column_text(st, c)))
                default: linha[nome] = .nulo
                }
            }
            linhas.append(linha)
        }
        return linhas
    }

    public var mudancas: Int { Int(sqlite3_changes(db)) }

    public func transacao<T>(_ corpo: () throws -> T) throws -> T {
        try executar("BEGIN IMMEDIATE")
        do { let r = try corpo(); try executar("COMMIT"); return r } catch { try? executar("ROLLBACK"); throw error }
    }
}

public extension Dictionary where Key == String, Value == SQLite.Valor {
    func texto(_ k: String) -> String? { if case let .texto(s)? = self[k] { return s }; return nil }
    func real(_ k: String) -> Double? {
        switch self[k] { case let .real(d)?: return d; case let .inteiro(n)?: return Double(n); default: return nil }
    }
    func inteiro(_ k: String) -> Int? {
        switch self[k] { case let .inteiro(n)?: return Int(n); case let .real(d)?: return Int(d); default: return nil }
    }
}
