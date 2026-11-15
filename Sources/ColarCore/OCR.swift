// Texto dentro das imagens (Fase 3, F13), pelo Vision local (nada sai do Mac). Português e inglês, modo preciso.
import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum OCR {
    /// Texto reconhecido, uma linha por bloco; "" se a imagem não tem texto; nil se nem deu para ler a imagem.
    public static func texto(de dados: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(dados as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = ["pt-BR", "en-US"]
        pedido.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([pedido]) } catch { return nil }
        return (pedido.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static let fila = DispatchQueue(label: "app.colar.ocr", qos: .utility)

    /// Lê as imagens pendentes uma a uma, fora da thread principal. `cada` volta na principal com (id, caracteres).
    public static func processarPendentes(_ historico: Historico, cada: @escaping (String, Int) -> Void = { _, _ in }) {
        fila.async {
            while let lote = try? historico.pendentesOCR(limite: 20), !lote.isEmpty {
                for item in lote {
                    let reps = (try? historico.representacoes(de: item.id)) ?? []
                    let dados = reps.first(where: { Coletor.utiImagem.contains($0.uti) })?.dados
                    let t = dados.flatMap(texto(de:)) ?? ""   // ilegível também marca como lido, para não repetir
                    try? historico.definirOCR(item.id, texto: t)
                    DispatchQueue.main.async { cada(item.id, t.count) }
                }
            }
        }
    }
}
