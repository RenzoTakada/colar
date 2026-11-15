// Acha o código físico de uma tecla no layout de teclado ativo (TIS + UCKeyTranslate): no Dvorak o "V" não fica no
// lugar do QWERTY, então mandar o código 9 fixo colaria a tecla errada. TIS na thread principal (macOS 26+ exige).
import Carbon
import CoreGraphics

public enum KeyboardLayout {
    /// Código ANSI do V no QWERTY, usado se o layout não tiver dados Unicode.
    public static let vQwerty: CGKeyCode = 9

    /// Layout ASCII atual (o que vale para atalhos com Cmd).
    public static func atual() -> TISInputSource {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    }

    /// Um layout instalado pelo id (ex.: "com.apple.keylayout.Dvorak"), habilitado ou não.
    public static func layout(id: String) -> TISInputSource? {
        let filtro = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let lista = TISCreateInputSourceList(filtro, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return lista.first
    }

    public static func id(_ fonte: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(fonte, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    /// Código físico (0...127) que produz `caractere` sem modificador no layout dado; nil se nenhum produz.
    public static func keyCode(para caractere: Character, em fonte: TISInputSource) -> CGKeyCode? {
        guard let p = TISGetInputSourceProperty(fonte, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let dados = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue() as Data
        let alvo = String(caractere).lowercased()
        return dados.withUnsafeBytes { bruto -> CGKeyCode? in
            guard let base = bruto.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for codigo in 0..<128 {
                var morta: UInt32 = 0
                var tamanho = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let st = UCKeyTranslate(layout, UInt16(codigo), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &morta, chars.count, &tamanho, &chars)
                if st == noErr, tamanho == 1, String(utf16CodeUnits: chars, count: 1).lowercased() == alvo {
                    return CGKeyCode(codigo)
                }
            }
            return nil
        }
    }

    /// Código do V no layout atual, com o QWERTY como reserva.
    public static func vAtual() -> CGKeyCode { keyCode(para: "v", em: atual()) ?? vQwerty }
}
