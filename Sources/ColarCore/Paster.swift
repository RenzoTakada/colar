// Colar no app que estava na frente: escreve no pasteboard e simula Cmd+V (CGEvent). Postar evento de teclado exige
// Acessibilidade; sem ela o texto fica só copiado.
import AppKit
import ApplicationServices

public enum Paster {
    /// Marca nos eventos que o próprio Colar posta, para a fila de colagem não confundir com o ⌘V do usuário.
    public static let marcaEvento: Int64 = 0x434F4C52   // "COLR"
    public static var temAcessibilidade: Bool { AXIsProcessTrusted() }

    /// Abre o pedido do sistema (só aparece se o app ainda não estiver na lista).
    public static func pedirAcessibilidade() {
        let opcoes = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opcoes)
    }

    /// Troca o conteúdo do pasteboard por `texto`. O teste usa um pasteboard nomeado para não tocar no clipboard real.
    public static func escrever(_ texto: String, em pb: NSPasteboard = .general) {
        pb.clearContents()
        pb.setString(texto, forType: .string)
    }

    /// Põe um item do histórico de volta no pasteboard com todos os tipos guardados (cola idêntico: RTF continua RTF,
    /// vários arquivos continuam vários). `textoPuro` deixa só o texto (Shift, "colar como texto sem formatação").
    /// A marca `Coletor.tipoColar` faz a captura só subir o item em vez de gravar outro.
    public static func escrever(itemId: String, representacoes: [Representacao], textoPuro: String? = nil,
                                em pb: NSPasteboard = .general) {
        pb.clearContents()
        if let textoPuro {
            let it = NSPasteboardItem()
            it.setString(textoPuro, forType: .string)
            it.setString(itemId, forType: NSPasteboard.PasteboardType(Coletor.tipoColar))
            pb.writeObjects([it])
            return
        }
        let grupos = Dictionary(grouping: representacoes, by: \.indicePb).sorted { $0.key < $1.key }
        let itens: [NSPasteboardItem] = grupos.enumerated().map { (n, g) in
            let it = NSPasteboardItem()
            for r in g.value { it.setData(r.dados, forType: NSPasteboard.PasteboardType(r.uti)) }
            if n == 0 { it.setString(itemId, forType: NSPasteboard.PasteboardType(Coletor.tipoColar)) }
            return it
        }
        pb.writeObjects(itens)
    }

    /// Manda Cmd+V para o app da frente. Os flags vão explícitos: só Command, mesmo que o Shift ainda esteja apertado.
    @discardableResult
    public static func postarCmdV(keyCode: CGKeyCode = KeyboardLayout.vAtual()) -> Bool {
        let fonte = CGEventSource(stateID: .combinedSessionState)
        guard let desce = CGEvent(keyboardEventSource: fonte, virtualKey: keyCode, keyDown: true),
              let sobe = CGEvent(keyboardEventSource: fonte, virtualKey: keyCode, keyDown: false) else { return false }
        desce.flags = .maskCommand
        sobe.flags = .maskCommand
        desce.setIntegerValueField(.eventSourceUserData, value: marcaEvento)
        sobe.setIntegerValueField(.eventSourceUserData, value: marcaEvento)
        desce.post(tap: .cghidEventTap)
        sobe.post(tap: .cghidEventTap)
        return true
    }
}
