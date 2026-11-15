// Checks da Fase 0. Sai com 0 só se tudo passou. Nunca mexe no clipboard real: usa um pasteboard nomeado.
// Executável no lugar do XCTest, que só vem com o Xcode completo.
import AppKit
import Carbon
import ColarCore

var falhas = 0, total = 0
func check(_ nome: String, _ ok: Bool, _ detalhe: String = "") {
    total += 1
    if ok { print("ok    \(nome)") } else { falhas += 1; print("FALHA \(nome) \(detalhe)") }
}

// MARK: tecla do V por layout
// Layouts comuns no Brasil ("Brazilian - Pro", "ABC", "US") e o Dvorak, em que o V muda de lugar.
// Códigos esperados = constantes da Apple em HIToolbox/Events.h: kVK_ANSI_V = 0x09, kVK_ANSI_Period = 0x2F (no Dvorak
// o V fica onde o QWERTY tem o ponto).
let casos: [(id: String, esperado: CGKeyCode)] = [
    ("com.apple.keylayout.ABC", CGKeyCode(kVK_ANSI_V)),
    ("com.apple.keylayout.Brazilian-Pro", CGKeyCode(kVK_ANSI_V)),
    ("com.apple.keylayout.US", CGKeyCode(kVK_ANSI_V)),
    ("com.apple.keylayout.Dvorak", CGKeyCode(kVK_ANSI_Period)),
]
for caso in casos {
    guard let fonte = KeyboardLayout.layout(id: caso.id) else {
        check("layout \(caso.id) instalado", false, "não encontrado")
        continue
    }
    let codigo = KeyboardLayout.keyCode(para: "v", em: fonte)
    check("V em \(caso.id) = \(caso.esperado)", codigo == caso.esperado, "veio \(String(describing: codigo))")
}
let atual = KeyboardLayout.atual()
check("V no layout atual (\(KeyboardLayout.id(atual))) encontrado", KeyboardLayout.keyCode(para: "v", em: atual) != nil)

// MARK: escrever no pasteboard (nomeado, nunca o geral)
let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks"))
// Textos com acentos e travessão, tabela em texto com | e –, quebras de linha.
let textos = [
    "- A reunião de sexta foi remarcada para às 15h (\"sala 2\"), e a pauta não mudou: revisão, orçamento e próximos passos.",
    "| A \"Opção um\" | 0 | 1 |\n|–|–|–|\nSem dados",
    "linha 1\nlinha 2\n\tlinha 3 com tab",
]
for t in textos {
    Paster.escrever(t, em: pb)
    check("pasteboard devolve igual (\(t.count) caracteres)", pb.string(forType: .string) == t)
}
let antes = pb.changeCount
Paster.escrever("outro", em: pb)
check("escrever muda o changeCount (base da captura da Fase 1)", pb.changeCount > antes)
check("clipboard real intocado pelos checks", NSPasteboard.general.name != pb.name)
pb.releaseGlobally()

// MARK: painel
_ = NSApplication.shared
let painel = ColarPanel()
check("painel não ativa o app (.nonactivatingPanel)", painel.styleMask.contains(.nonactivatingPanel))
check("painel recebe teclado (canBecomeKey)", painel.canBecomeKey)
check("painel nunca vira janela principal", !painel.canBecomeMain)
check("painel invisível a captura de tela (sharingType .none)", painel.sharingType == NSWindow.SharingType.none)
painel.posicionar()
let area = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)!.visibleFrame
check("painel na base da tela, largura inteira", painel.frame.minY == area.minY && painel.frame.width == area.width,
      "frame \(painel.frame) área \(area)")

// MARK: atalho (informativo: o Carbon pode responder -9878 se outro app já usa o ⌘⇧V)
let r = HotKeys.shared.registrar(keyCode: UInt32(KeyboardLayout.vAtual()), HotKeys.cmd | HotKeys.shift) {}
print("info  ⌘⇧V: status \(r.status)\(r.status == HotKeys.jaExiste ? " (ocupado)" : "")")
check("registro do ⌘⇧V devolve ok ou 'já existe'", r.status == noErr || r.status == HotKeys.jaExiste, "status \(r.status)")
if let id = r.id { HotKeys.shared.remover(id) }

fase1()
painelRedesenha()
fase2()
fase3()
fase4()

print("\n\(total - falhas)/\(total) ok")
exit(falhas == 0 ? 0 : 1)
