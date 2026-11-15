// Atalhos globais por Carbon RegisterEventHotKey: funcionam sem Acessibilidade nem Monitoramento de Entrada.
// Devolve o OSStatus: outro app pode já ter registrado a mesma combinação.
import Carbon

public final class HotKeys {
    public static let shared = HotKeys()
    public static let cmd = UInt32(cmdKey), shift = UInt32(shiftKey), option = UInt32(optionKey), control = UInt32(controlKey)
    /// -9878: outro app já registrou a mesma combinação.
    public static let jaExiste = OSStatus(eventHotKeyExistsErr)

    private var acoes: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var proximo: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ in
            var id = EventHotKeyID()
            GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.shared.acoes[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registra `keyCode` (código físico da tecla) com os modificadores. Devolve o id (para remover) e o status.
    @discardableResult
    public func registrar(keyCode: UInt32, _ mods: UInt32, _ acao: @escaping () -> Void) -> (id: UInt32?, status: OSStatus) {
        let id = proximo; proximo += 1
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(keyCode, mods, EventHotKeyID(signature: 0x434F4C52 /* COLR */, id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else { return (nil, st) }
        refs[id] = ref; acoes[id] = acao
        return (id, st)
    }

    public func remover(_ id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        acoes[id] = nil
    }
}
