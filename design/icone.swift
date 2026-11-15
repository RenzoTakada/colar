// Ícone do Colar gerado por código. Grid de ícone do macOS: tela 1024, corpo 824 × 824 centrado com cantos contínuos
// (squircle), sombra curta embaixo. "Colar" = colar (paste) e colar (o de contas): os itens são as contas de um fio.
// Uso: swift design/icone.swift <conceito: fio|leque|gota> <saida.png> [tamanho]
import AppKit

let args = CommandLine.arguments
let conceito = args.count > 1 ? args[1] : "fio"
let saida = args.count > 2 ? args[2] : "icone.png"
let tam = CGFloat(args.count > 3 ? Double(args[3])! : 1024)
let k = tam / 1024

func cor(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Retângulo de cantos contínuos (aproximação do squircle da Apple com curvas de Bézier).
func squircle(_ r: NSRect, raio: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let c = raio * 1.28   // alcance da curva além do raio: o que dá a continuidade
    let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
    p.move(to: NSPoint(x: x0 + c, y: y0))
    p.line(to: NSPoint(x: x1 - c, y: y0))
    p.curve(to: NSPoint(x: x1, y: y0 + c), controlPoint1: NSPoint(x: x1 - c * 0.35, y: y0), controlPoint2: NSPoint(x: x1, y: y0 + c * 0.35))
    p.line(to: NSPoint(x: x1, y: y1 - c))
    p.curve(to: NSPoint(x: x1 - c, y: y1), controlPoint1: NSPoint(x: x1, y: y1 - c * 0.35), controlPoint2: NSPoint(x: x1 - c * 0.35, y: y1))
    p.line(to: NSPoint(x: x0 + c, y: y1))
    p.curve(to: NSPoint(x: x0, y: y1 - c), controlPoint1: NSPoint(x: x0 + c * 0.35, y: y1), controlPoint2: NSPoint(x: x0, y: y1 - c * 0.35))
    p.line(to: NSPoint(x: x0, y: y0 + c))
    p.curve(to: NSPoint(x: x0 + c, y: y0), controlPoint1: NSPoint(x: x0, y: y0 + c * 0.35), controlPoint2: NSPoint(x: x0 + c * 0.35, y: y0))
    p.close()
    return p
}

let img = NSImage(size: NSSize(width: tam, height: tam))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: k, y: k)

let corpo = NSRect(x: 100, y: 100, width: 824, height: 824)
let forma = squircle(corpo, raio: 145)

// sombra do corpo
NSGraphicsContext.saveGraphicsState()
let sombra = NSShadow()
sombra.shadowColor = cor(0x000000, 0.28); sombra.shadowBlurRadius = 28; sombra.shadowOffset = NSSize(width: 0, height: -12)
sombra.set()
cor(0x000000).setFill(); forma.fill()
NSGraphicsContext.restoreGraphicsState()

forma.addClip()

/// Conta do colar: cartão arredondado com a faixa do cabeçalho, como um item no painel.
func conta(centro: NSPoint, l: CGFloat, a: CGFloat, angulo: CGFloat, fundo: NSColor, faixa: NSColor, linhas: NSColor, sombraA: CGFloat = 0.25) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: centro.x, yBy: centro.y); t.rotate(byDegrees: angulo); t.concat()
    let r = NSRect(x: -l / 2, y: -a / 2, width: l, height: a)
    let s = NSShadow(); s.shadowColor = cor(0x000000, sombraA); s.shadowBlurRadius = 18; s.shadowOffset = NSSize(width: 0, height: -8); s.set()
    let p = squircle(r, raio: l * 0.16)
    fundo.setFill(); p.fill()
    NSShadow().set()
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    faixa.setFill(); NSRect(x: r.minX, y: r.maxY - a * 0.26, width: l, height: a * 0.26).fill()
    linhas.setFill()
    for i in 0..<3 {
        let w = l * [0.62, 0.48, 0.55][i]
        squircle(NSRect(x: r.minX + l * 0.14, y: r.maxY - a * 0.42 - CGFloat(i) * a * 0.14, width: w, height: a * 0.06), raio: a * 0.02).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
}

switch conceito {
case "fio":
    // Fundo carvão quente; um fio dourado em arco; cinco contas penduradas, a do meio maior e acesa (o item escolhido).
    NSGradient(colors: [cor(0x2A2724), cor(0x161514)])!.draw(in: corpo, angle: -90)
    let fio = NSBezierPath()
    fio.move(to: NSPoint(x: 60, y: 760)); fio.curve(to: NSPoint(x: 964, y: 760), controlPoint1: NSPoint(x: 330, y: 330), controlPoint2: NSPoint(x: 694, y: 330))
    fio.lineWidth = 14; fio.lineCapStyle = .round
    cor(0xE8B45A).setStroke(); fio.stroke()
    // pontos do arco (Bézier cúbica) para pendurar as contas
    func ponto(_ t: CGFloat) -> NSPoint {
        let p0 = NSPoint(x: 60, y: 760), p1 = NSPoint(x: 330, y: 330), p2 = NSPoint(x: 694, y: 330), p3 = NSPoint(x: 964, y: 760)
        let u = 1 - t
        return NSPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x, y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
    }
    let contas: [(t: CGFloat, l: CGFloat, ang: CGFloat, acesa: Bool)] = [(0.13, 150, 24, false), (0.31, 175, 11, false), (0.5, 250, 0, true), (0.69, 175, -11, false), (0.87, 150, -24, false)]
    for c in contas.sorted(by: { !$0.acesa && $1.acesa }) {
        let p = ponto(c.t)
        let a = c.l * 1.12
        conta(centro: NSPoint(x: p.x, y: p.y - a / 2 + 6), l: c.l, a: a, angulo: c.ang,
              fundo: c.acesa ? cor(0xFFFBF2) : cor(0xEDE6DA), faixa: c.acesa ? cor(0xE8B45A) : cor(0xC9BFAF),
              linhas: c.acesa ? cor(0x3A322A, 0.55) : cor(0x6B6156, 0.35), sombraA: 0.4)
    }
case "leque":
    // Fundo claro papel; três cartões em leque, o da frente com faixa terracota-coral, presos por um fio que passa por cima.
    NSGradient(colors: [cor(0xF7F4EE), cor(0xE9E4DA)])!.draw(in: corpo, angle: -90)
    conta(centro: NSPoint(x: 400, y: 470), l: 330, a: 380, angulo: 14, fundo: cor(0xFFFFFF), faixa: cor(0x9DB4C0), linhas: cor(0x2B2F33, 0.25))
    conta(centro: NSPoint(x: 624, y: 470), l: 330, a: 380, angulo: -14, fundo: cor(0xFFFFFF), faixa: cor(0xA9C29A), linhas: cor(0x2B2F33, 0.25))
    conta(centro: NSPoint(x: 512, y: 450), l: 360, a: 410, angulo: 0, fundo: cor(0xFFFFFF), faixa: cor(0x1F6FEB), linhas: cor(0x2B2F33, 0.35))
    let fio = NSBezierPath()
    fio.move(to: NSPoint(x: 100, y: 735)); fio.curve(to: NSPoint(x: 924, y: 735), controlPoint1: NSPoint(x: 360, y: 640), controlPoint2: NSPoint(x: 664, y: 640))
    fio.lineWidth = 12; fio.lineCapStyle = .round; cor(0x1D1F22).setStroke(); fio.stroke()
case "gota":
    // Fundo azul profundo liso; uma única conta grande, cartão branco pendurado num fio fino que desce do topo.
    NSGradient(colors: [cor(0x1D5BD8), cor(0x0E2F7A)])!.draw(in: corpo, angle: -90)
    let fio = NSBezierPath(); fio.move(to: NSPoint(x: 512, y: 924)); fio.line(to: NSPoint(x: 512, y: 690))
    fio.lineWidth = 12; fio.lineCapStyle = .round; cor(0xFFFFFF, 0.9).setStroke(); fio.stroke()
    let anel = NSBezierPath(ovalIn: NSRect(x: 482, y: 660, width: 60, height: 60)); anel.lineWidth = 12; anel.stroke()
    conta(centro: NSPoint(x: 512, y: 440), l: 420, a: 460, angulo: -6, fundo: cor(0xFFFFFF), faixa: cor(0xFFC845), linhas: cor(0x0E2F7A, 0.3), sombraA: 0.45)
default:
    fatalError("conceito desconhecido: \(conceito)")
}

// brilho de borda sutil (luz de cima), como os ícones do macOS 26
NSGraphicsContext.saveGraphicsState()
let borda = squircle(corpo.insetBy(dx: 1, dy: 1), raio: 144); borda.lineWidth = 3
NSGradient(colors: [cor(0xFFFFFF, 0.35), cor(0xFFFFFF, 0)])!.draw(in: borda, angle: -90)
NSGraphicsContext.restoreGraphicsState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: saida))
print("ok \(conceito) → \(saida)")
