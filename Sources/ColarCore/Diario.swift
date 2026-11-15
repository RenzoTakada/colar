// Diário da bancada: uma linha por evento em ~/Library/Logs/Colar/colar.log, com milissegundos, para medir o tempo
// entre o Enter e o Cmd+V e para depurar sem o Console.
import Foundation

public enum Diario {
    public static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Colar/colar.log")
    private static let fila = DispatchQueue(label: "app.colar.diario")
    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static func anotar(_ texto: String) {
        let linha = "\(formato.string(from: Date())) \(texto)\n"
        fila.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(linha.utf8)); try? h.close()
            } else {
                try? Data(linha.utf8).write(to: url)
            }
        }
    }
}
