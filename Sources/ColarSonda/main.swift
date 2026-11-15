// Sonda de diagnóstico: renderiza o painel num PNG, numa janela fora da tela que não pega o teclado. Só lê.
// Uso: ColarSonda <saida.png> [direcao] [busca]. COLAR_DIR aponta para uma cópia do banco.
import AppKit
import ColarCore
import SwiftUI

_ = NSApplication.shared
// COLAR_DIR: usar uma cópia do banco (nunca o real) para montar cenários; COLAR_PINBOARD: cria esse pinboard na cópia,
// fixa o primeiro link e abre a aba dele.
let env = ProcessInfo.processInfo.environment
let h = try env["COLAR_DIR"].map { try Historico(diretorio: URL(fileURLWithPath: $0)) } ?? Historico()
var abrirPinboard: String?
// COLAR_DEMO=1 (só com COLAR_DIR): preenche a cópia com itens de demonstração neutros, para a imagem do README.
if env["COLAR_DEMO"] == "1", env["COLAR_DIR"] != nil {
    func png(_ l: Int, _ a: Int, _ texto: String, fundo: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: l, pixelsHigh: a, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        fundo.setFill(); NSRect(x: 0, y: 0, width: l, height: a).fill()
        NSColor.white.withAlphaComponent(0.9).setFill(); NSRect(x: l/10, y: a/3, width: l*8/10, height: a/3).fill()
        (texto as NSString).draw(at: NSPoint(x: l/10 + 20, y: a/2 - 14), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold)])
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
    let pb = NSPasteboard(name: NSPasteboard.Name("app.colar.sonda.demo")); defer { pb.releaseGlobally() }
    let col = Coletor(historico: h, pasteboard: pb)
    let base = Date()
    func copiar(_ tipos: [(String, Data)], app: String, min: Double) -> String? {
        pb.clearContents(); let it = NSPasteboardItem()
        for (t, d) in tipos + [(Coletor.tipoOrigem, Data(app.utf8))] { it.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        pb.writeObjects([it])
        if case .gravado(.novo(let id)) = col.processar(col.foto()!, agora: base.addingTimeInterval(-min * 60)) { return id }
        return nil
    }
    let t = "public.utf8-plain-text"
    _ = copiar([(t, Data("git commit -m \"ajusta o layout do painel\"".utf8))], app: "com.apple.Terminal", min: 95)
    _ = copiar([("public.png", png(1200, 760, "Relatório de vendas — março", fundo: NSColor(srgbRed: 0.11, green: 0.36, blue: 0.85, alpha: 1)))], app: "com.apple.Safari", min: 60)
    _ = copiar([(t, Data("#C8923A".utf8))], app: "com.apple.TextEdit", min: 42)
    if let l = copiar([(t, Data("https://www.swift.org/documentation/".utf8))], app: "com.apple.Safari", min: 30) {
        try h.definirPreviaLink(l, titulo: "Swift.org - Documentation", imagem: nil)
    }
    _ = copiar([(t, Data("Oi! A reunião de amanhã ficou para as 15h, na sala 2. Levo o relatório impresso.".utf8))], app: "com.apple.MobileSMS", min: 12)
    _ = copiar([("public.png", png(900, 600, "Fluxo de pagamento v2", fundo: NSColor(srgbRed: 0.24, green: 0.49, blue: 0.35, alpha: 1)))], app: "com.apple.Preview", min: 5)
    _ = copiar([(t, Data("Endereço de entrega: Rua das Flores, 120 — apto 31".utf8))], app: "com.apple.Notes", min: 1)
}
if let nome = env["COLAR_PINBOARD"], env["COLAR_DIR"] != nil {
    let pb = try h.criarPinboard(nome, cor: "#B5452F")
    if let link = try h.recentes().first(where: { $0.tipo == .link }) { try h.fixar(link.id, em: pb.id) }
    if let img = try h.recentes().first(where: { $0.tipo == .imagem }) { try h.fixar(img.id, em: pb.id) }
    _ = try h.criarPinboard("Projetos")
    abrirPinboard = pb.id
}
let m = PainelModelo(historico: h)
m.recarregar()
if let p = abrirPinboard, env["COLAR_ABA"] == "pinboard" { m.pinboardAtual = p }
for it in m.itens {
    let blob = it.miniatura.map { h.urlBlob($0) }
    let viaURL = blob.flatMap { NSImage(contentsOf: $0) } != nil
    let viaData = blob.flatMap { try? Data(contentsOf: $0) }.flatMap { NSImage(data: $0) } != nil
    print(it.tipo.rawValue, it.largura ?? 0, "x", it.altura ?? 0, "mini:", it.miniatura?.prefix(8) ?? "-", "NSImage(contentsOf:)", viaURL, "NSImage(data:)", viaData)
}
// Janela fora da tela com o mesmo NSHostingView do app (ImageRenderer não desenha ScrollView).
let janela = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 1700, height: 340), styleMask: [.borderless],
                      backing: .buffered, defer: false)
if CommandLine.arguments.count > 2, let d = Direcao(rawValue: CommandLine.arguments[2]) { m.direcao = d }
m.selecionado = 0
if CommandLine.arguments.count > 3 { m.busca = CommandLine.arguments[3] }
let vista = NSHostingView(rootView: PainelView(modelo: m) { _ in })
janela.contentView = vista
janela.orderFrontRegardless()
RunLoop.main.run(until: Date().addingTimeInterval(1.0))
vista.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
if let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) {
    vista.cacheDisplay(in: vista.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("ok", CommandLine.arguments[1])
}
