// Preferências de colagem e de som, guardadas na tabela config.
import AppKit

public enum ModoColar: String, CaseIterable {
    /// "Para Aplicativo Ativo": cola direto no app de baixo (Cmd+V simulado).
    case appAtivo = "app"
    /// "Para a Área de Transferência": só copia; cola-se quando quiser.
    case areaTransferencia = "clipboard"
}

/// O que fazer ao escolher um item.
public struct Colagem: Equatable {
    public let textoPuro: Bool
    public let postarCmdV: Bool
    /// Motivo de não postar, para o diário.
    public let motivo: String?
    public init(textoPuro: Bool, postarCmdV: Bool, motivo: String?) {
        self.textoPuro = textoPuro; self.postarCmdV = postarCmdV; self.motivo = motivo
    }
}

public enum Regras {
    /// ⇧ inverte o padrão: com "Sempre colar como texto sem formatação" ligado, ⇧ cola formatado.
    /// Imagem e arquivo nunca viram texto puro. Sem Acessibilidade ou no modo "só copiar", não posta o Cmd+V.
    public static func colagem(tipo: TipoItem, shift: Bool, modo: ModoColar, sempreTextoPuro: Bool,
                               temAcessibilidade: Bool) -> Colagem {
        let querPuro = shift != sempreTextoPuro
        let puro = querPuro && ![.imagem, .arquivo].contains(tipo)
        if modo == .areaTransferencia { return Colagem(textoPuro: puro, postarCmdV: false, motivo: "modo só copiar") }
        if !temAcessibilidade { return Colagem(textoPuro: puro, postarCmdV: false, motivo: "sem acessibilidade") }
        return Colagem(textoPuro: puro, postarCmdV: true, motivo: nil)
    }
}

public extension Historico {
    var modoColar: ModoColar {
        get { config("modo_colar").flatMap(ModoColar.init) ?? .appAtivo }
        set { definir("modo_colar", newValue.rawValue) }
    }
    var sempreTextoPuro: Bool {
        get { config("sempre_texto_puro") == "1" }
        set { definir("sempre_texto_puro", newValue ? "1" : "0") }
    }
    /// Efeitos sonoros ligados por padrão.
    var sons: Bool {
        get { config("sons") != "0" }
        set { definir("sons", newValue ? "1" : "0") }
    }
}

/// Sons de copiar e colar: par "papel" (deslizar curto de papel) sintetizado em design/sons/gerar.py; os sons de
/// alerta do sistema soam como erro. Ficam em
/// Contents/Resources/copiar.wav e colar.wav. Sem o arquivo, fica em silêncio: nunca cai num som de alerta do sistema.
public enum Sons {
    private static let copiarSom = carregar("copiar")
    private static let colarSom = carregar("colar")

    public static func copiou() { tocar(copiarSom) }
    public static func colou() { tocar(colarSom) }

    static func carregar(_ nome: String, bundle: Bundle = .main) -> NSSound? {
        guard let url = bundle.url(forResource: nome, withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }

    private static func tocar(_ som: NSSound?) {
        guard let s = som?.copy() as? NSSound else { return }
        s.volume = 0.6
        s.play()
    }
}
