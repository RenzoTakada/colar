// Fila de colagem (⇧⌘C). Enquanto ativa, o que é copiado entra numa fila, e cada ⌘V cola o próximo, na ordem em
// que entrou. Para trocar o pasteboard no instante do ⌘V, um CGEventTap escuta o teclado (usa a Acessibilidade) e
// existe só enquanto a fila está ativa; desliga sozinho quando a fila esvazia.
import AppKit
import CoreGraphics

/// A fila em si, sem nada de sistema (testável).
public final class PilhaColagem {
    public private(set) var ids: [String] = []
    public private(set) var colados = 0
    public var ativa = false {
        didSet { if !ativa { ids = []; colados = 0 } }
    }

    public init() {}

    /// Entra no fim. O mesmo item duas vezes seguidas não duplica (copiar duas vezes sem querer).
    public func adicionar(_ id: String) {
        guard ativa, ids.last != id else { return }
        ids.append(id)
    }

    /// Tira o próximo (o mais antigo). Fila vazia depois disso desliga a pilha.
    public func proximo() -> String? {
        guard ativa, !ids.isEmpty else { return nil }
        colados += 1
        return ids.removeFirst()
    }

    public var vazia: Bool { ids.isEmpty }
}

/// Escuta o ⌘V do sistema enquanto a pilha está ativa. `antesDoCmdV` roda dentro do callback, antes de o evento seguir
/// para o app da frente: é ali que o pasteboard recebe o próximo item.
public final class EscutaCmdV {
    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private let antesDoCmdV: () -> Void

    public init(antesDoCmdV: @escaping () -> Void) { self.antesDoCmdV = antesDoCmdV }

    /// true se o tap foi criado (sem Acessibilidade o sistema recusa).
    @discardableResult
    public func ligar() -> Bool {
        guard tap == nil else { return true }
        let mascara = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let eu = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mascara, callback: { _, tipo, evento, ref in
            guard let ref else { return Unmanaged.passUnretained(evento) }
            let escuta = Unmanaged<EscutaCmdV>.fromOpaque(ref).takeUnretainedValue()
            if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                if let t = escuta.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(evento)
            }
            if EscutaCmdV.ehCmdV(evento) { escuta.antesDoCmdV() }
            return Unmanaged.passUnretained(evento)
        }, userInfo: eu) else { return false }
        tap = t
        fonte = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    public func desligar() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let f = fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        tap = nil; fonte = nil
    }

    public var ligada: Bool { tap != nil }

    /// ⌘V puro (sem ⇧, ⌥, ⌃), na tecla do V do layout atual, sem repetição de tecla segurada.
    public static func ehCmdV(_ e: CGEvent, vKeyCode: CGKeyCode = KeyboardLayout.vAtual()) -> Bool {
        let f = e.flags
        guard CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode)) == vKeyCode, f.contains(.maskCommand),
              !f.contains(.maskShift), !f.contains(.maskAlternate), !f.contains(.maskControl),
              e.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              e.getIntegerValueField(.eventSourceUserData) != Paster.marcaEvento else { return false }   // o Colar colando
        return true
    }
}
