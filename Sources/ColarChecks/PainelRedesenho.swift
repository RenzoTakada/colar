// Regressão: o painel reabria com o desenho antigo (cartões identificados pela posição não eram redesenhados quando o
// histórico mudava). O desenho recarregado tem de ficar igual ao de um painel criado do zero com o mesmo histórico.
// Limite: este check não reproduz o congelamento visto no app real (que depende do app em segundo plano); para isso,
// abrir o painel, mudar a ordem no banco e abrir de novo (colar://abrir, colar://foto).
import AppKit
import ColarCore
import SwiftUI
import UniformTypeIdentifiers

/// Desenha o painel numa janela fora da tela, do mesmo jeito que o app (NSHostingView + cacheDisplay).
final class PainelDeTeste {
    let janela: ColarPanel
    let vista: NSHostingView<PainelView>

    /// O mesmo ColarPanel do app (não ativador), fora da tela.
    init(modelo: PainelModelo) {
        janela = ColarPanel()
        janela.setFrame(NSRect(x: -4000, y: 0, width: 1700, height: 300), display: false)
        vista = NSHostingView(rootView: PainelView(modelo: modelo) { _ in })
        janela.contentView = vista
        janela.makeKeyAndOrderFront(nil)
    }

    func png() -> Data {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        vista.layoutSubtreeIfNeeded()
        let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds)!
        vista.cacheDisplay(in: vista.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])!
    }

    func fechar() { janela.orderOut(nil) }
}

func painelRedesenha() {
    print("\n== Painel redesenha quando o histórico muda")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colar-painel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let h = try? Historico(diretorio: dir, aparelho: "Mac de teste") else { check("abre o histórico", false); return }
    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.checks.painel"))
    defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)
    let base = Date().addingTimeInterval(-600)
    func copiar(_ tipos: [(String, Data)], _ minutos: Double) {
        pb.clearContents()
        let it = NSPasteboardItem()
        for (t, d) in tipos { it.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        pb.writeObjects([it])
        if let f = col.foto() { _ = col.processar(f, agora: base.addingTimeInterval(minutos * 60)) }
    }
    let texto = "public.utf8-plain-text"
    // Sete itens no painel.
    copiar([(texto, Data("2. Separe os arquivos da reunião.".utf8))], 0)
    for (i, (l, a)) in [(939, 628), (1675, 281), (772, 459), (248, 253), (1125, 679)].enumerated() {
        copiar([(UTType.png.identifier, png(l, a))], Double(i + 1))
    }
    copiar([(texto, Data("Para quando é a entrega?".utf8)), ("public.rtf", Data("{\\rtf1 Para quando é a entrega?}".utf8))], 6)

    let modelo = PainelModelo(historico: h)
    modelo.recarregar()
    let painel = PainelDeTeste(modelo: modelo)
    let antes = painel.png()
    check("painel desenha os 7 itens", modelo.itens.count == 7)

    // Chegam itens novos.
    copiar([(UTType.png.identifier, png(1719, 270))], 7)
    copiar([(texto, Data("3. Revise o texto antes de enviar para a equipe.".utf8))], 8)
    copiar([(UTType.png.identifier, png(1896, 285))], 9)
    // Como o app: fecha (orderOut), o histórico muda com o painel fechado, recarrega e reabre.
    painel.janela.orderOut(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    modelo.recarregar()
    painel.janela.makeKeyAndOrderFront(nil)
    let depois = painel.png()
    painel.fechar()

    let novo = PainelDeTeste(modelo: modelo)
    let referencia = novo.png()
    novo.fechar()

    check("modelo recarregado tem 10 itens com o print 1896 × 285 no topo",
          modelo.itens.count == 10 && modelo.itens.first?.largura == 1896)
    check("desenho muda depois da recarga", depois != antes)
    check("desenho recarregado = painel novo com o mesmo histórico", depois == referencia,
          "salvo em \(salvar(depois, "depois")) e \(salvar(referencia, "referencia"))")
}

private func salvar(_ d: Data, _ nome: String) -> String {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("colar-painel-\(nome).png")
    try? d.write(to: u)
    return u.path
}
