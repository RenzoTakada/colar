// Prévia de link: título e imagem da página pelo LinkPresentation, depois da captura e fora da thread principal.
// Só acessa a rede para links copiados pelo próprio usuário.
import AppKit
import LinkPresentation

public enum PreviaLink {
    /// Busca e grava no histórico. `pronto` volta na thread principal.
    public static func buscar(itemId: String, url: URL, historico: Historico, pronto: @escaping (Bool) -> Void) {
        let provedor = LPMetadataProvider()
        provedor.timeout = 8
        provedor.startFetchingMetadata(for: url) { meta, erro in
            guard let meta, erro == nil else { DispatchQueue.main.async { pronto(false) }; return }
            let titulo = meta.title
            guard let ip = meta.imageProvider ?? meta.iconProvider else {
                try? historico.definirPreviaLink(itemId, titulo: titulo, imagem: nil)
                DispatchQueue.main.async { pronto(true) }
                return
            }
            ip.loadObject(ofClass: NSImage.self) { obj, _ in
                let png = (obj as? NSImage).flatMap { img -> Data? in
                    guard let tiff = img.tiffRepresentation else { return nil }
                    return Coletor.dimensoesEMiniatura(tiff).2
                }
                try? historico.definirPreviaLink(itemId, titulo: titulo, imagem: png)
                DispatchQueue.main.async { pronto(true) }
            }
        }
    }
}
