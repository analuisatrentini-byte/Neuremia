import AppKit

let outputDirectory = URL(fileURLWithPath: "/Users/analuisabittencourt/Desktop/Neuremia/AppStoreScreenshots", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let width: CGFloat = 1290
let height: CGFloat = 2796

let navy = NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.29, alpha: 1)
let navySoft = NSColor(calibratedRed: 0.05, green: 0.17, blue: 0.36, alpha: 1)
let navyGlass = NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.38, alpha: 1)
let yellow = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.0, alpha: 1)
let gold = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1)
let white = NSColor.white
let muted = NSColor(calibratedWhite: 1, alpha: 0.68)
let card = NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.30, alpha: 0.92)
let cardLight = NSColor(calibratedWhite: 1, alpha: 0.08)

func paragraphStyle(alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = lineSpacing
    return style
}

func drawText(
    _ text: String,
    rect: CGRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = white,
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle(alignment: alignment, lineSpacing: lineSpacing)
    ]
    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

func fillRounded(_ rect: CGRect, color: NSColor, radius: CGFloat = 28, stroke: NSColor? = nil, lineWidth: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSBezierPath(ovalIn: rect).fill(with: color)
}

extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}

func makeImage(fileName: String, title: String, subtitle: String, content: (CGRect) -> Void) throws {
    let image = NSImage(size: CGSize(width: width, height: height))
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [navy.cgColor, navySoft.cgColor, navyGlass.cgColor] as CFArray,
        locations: [0, 0.56, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: width, y: 0),
        options: []
    )

    drawText("Neuremia", rect: CGRect(x: 86, y: height - 178, width: 520, height: 60), size: 34, weight: .bold, color: yellow)
    drawText(title, rect: CGRect(x: 86, y: height - 395, width: 1118, height: 132), size: 64, weight: .bold, color: white, lineSpacing: 3)
    drawText(subtitle, rect: CGRect(x: 86, y: height - 508, width: 1040, height: 92), size: 30, weight: .regular, color: muted, lineSpacing: 4)

    let phone = CGRect(x: 105, y: 120, width: 1080, height: 2020)
    fillRounded(phone, color: NSColor(calibratedWhite: 0.02, alpha: 0.92), radius: 88, stroke: NSColor(calibratedWhite: 1, alpha: 0.18), lineWidth: 3)
    let screen = phone.insetBy(dx: 34, dy: 34)
    fillRounded(screen, color: navy, radius: 58)

    context.saveGState()
    NSBezierPath(roundedRect: screen, xRadius: 58, yRadius: 58).addClip()
    content(screen)
    context.restoreGState()

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "Screenshot", code: 1)
    }

    try png.write(to: outputDirectory.appendingPathComponent(fileName))
}

func drawStatusBar(in screen: CGRect, title: String) {
    drawText("9:41", rect: CGRect(x: screen.minX + 54, y: screen.maxY - 78, width: 140, height: 34), size: 24, weight: .semibold)
    drawText(title, rect: CGRect(x: screen.minX + 54, y: screen.maxY - 162, width: 520, height: 56), size: 44, weight: .bold)
    fillRounded(CGRect(x: screen.maxX - 150, y: screen.maxY - 82, width: 92, height: 36), color: NSColor(calibratedWhite: 1, alpha: 0.10), radius: 18)
    drawText("SOS", rect: CGRect(x: screen.maxX - 132, y: screen.maxY - 78, width: 70, height: 28), size: 19, weight: .bold, color: NSColor.systemRed, alignment: .center)
}

func drawPill(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor = cardLight) {
    fillRounded(CGRect(x: x, y: y, width: width, height: 54), color: color, radius: 18)
    drawText(text, rect: CGRect(x: x + 18, y: y + 13, width: width - 36, height: 28), size: 18, weight: .semibold, color: white, alignment: .center)
}

func drawMetric(title: String, value: String, x: CGFloat, y: CGFloat, w: CGFloat) {
    fillRounded(CGRect(x: x, y: y, width: w, height: 142), color: cardLight, radius: 20)
    drawText(value, rect: CGRect(x: x + 22, y: y + 54, width: w - 44, height: 38), size: 32, weight: .bold, color: yellow)
    drawText(title, rect: CGRect(x: x + 22, y: y + 20, width: w - 44, height: 28), size: 18, color: muted)
}

try makeImage(
    fileName: "01-hoje-checkin.png",
    title: "Acompanhe seu bem-estar diariamente",
    subtitle: "Registre humor, ansiedade, sono e medicação em uma rotina simples e acolhedora."
) { screen in
    drawStatusBar(in: screen, title: "Hoje")

    let x = screen.minX + 54
    var y = screen.maxY - 450
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 252), color: card, radius: 30, stroke: yellow.withAlphaComponent(0.20))
    drawText("Boa manhã", rect: CGRect(x: x + 32, y: y + 172, width: 680, height: 48), size: 40, weight: .bold)
    drawText("Um espaço tranquilo para perceber como você está.", rect: CGRect(x: x + 32, y: y + 118, width: 760, height: 42), size: 25, color: muted)
    fillRounded(CGRect(x: x + 32, y: y + 40, width: 300, height: 58), color: yellow, radius: 20)
    drawText("Registrar agora", rect: CGRect(x: x + 54, y: y + 56, width: 256, height: 28), size: 21, weight: .bold, color: navy, alignment: .center)

    y -= 178
    drawMetric(title: "Humor", value: "3/5", x: x, y: y, w: 286)
    drawMetric(title: "Ansiedade", value: "2/5", x: x + 312, y: y, w: 286)
    drawMetric(title: "Sono", value: "7h", x: x + 624, y: y, w: 286)

    y -= 266
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 230), color: card, radius: 28)
    drawText("Missões do dia", rect: CGRect(x: x + 28, y: y + 170, width: 520, height: 38), size: 30, weight: .bold, color: yellow)
    drawPill("Check-in", x: x + 28, y: y + 92, width: 220, color: yellow.withAlphaComponent(0.24))
    drawPill("Escalas", x: x + 274, y: y + 92, width: 198)
    drawPill("Respiração", x: x + 498, y: y + 92, width: 246)
    drawText("Pequenos passos diários viram progresso concreto.", rect: CGRect(x: x + 28, y: y + 38, width: 740, height: 34), size: 22, color: muted)

    y -= 404
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 352), color: card, radius: 28)
    drawText("Como você está agora?", rect: CGRect(x: x + 28, y: y + 286, width: 620, height: 40), size: 31, weight: .bold)
    drawText("Toque em uma emoção ou ajuste os controles.", rect: CGRect(x: x + 28, y: y + 244, width: 680, height: 32), size: 21, color: muted)
    let moods = [("Leve", NSColor.systemGreen), ("Bem", yellow), ("Neutro", NSColor.systemGray), ("Ansioso", NSColor.systemOrange), ("Triste", NSColor.systemBlue)]
    for (index, item) in moods.enumerated() {
        let bx = x + 30 + CGFloat(index) * 176
        fillRounded(CGRect(x: bx, y: y + 92, width: 150, height: 112), color: cardLight, radius: 22, stroke: item.1.withAlphaComponent(index == 1 ? 0.9 : 0.0), lineWidth: 4)
        drawText(item.0, rect: CGRect(x: bx + 8, y: y + 126, width: 134, height: 28), size: 20, weight: .semibold, color: index == 1 ? yellow : white, alignment: .center)
    }
}

try makeImage(
    fileName: "02-checkup-bem-estar.png",
    title: "Check-ups para reflexão pessoal",
    subtitle: "Escalas estruturadas ajudam você a observar tendências sem substituir atendimento profissional."
) { screen in
    drawStatusBar(in: screen, title: "Check-up")

    let x = screen.minX + 54
    var y = screen.maxY - 450
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 292), color: card, radius: 30, stroke: yellow.withAlphaComponent(0.22))
    drawText("Check-up do bem-estar", rect: CGRect(x: x + 32, y: y + 218, width: 760, height: 46), size: 38, weight: .bold, color: yellow)
    drawText("Resultado automático de apoio", rect: CGRect(x: x + 32, y: y + 172, width: 620, height: 32), size: 24, color: muted)
    drawMetric(title: "PHQ-9", value: "7", x: x + 32, y: y + 40, w: 260)
    drawMetric(title: "GAD-7", value: "5", x: x + 324, y: y + 40, w: 260)
    drawMetric(title: "YMRS", value: "3", x: x + 616, y: y + 40, w: 260)

    y -= 300
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 218), color: card, radius: 28)
    drawText("Aplicação formal das escalas", rect: CGRect(x: x + 28, y: y + 158, width: 720, height: 38), size: 30, weight: .bold)
    drawPill("PHQ-9", x: x + 28, y: y + 80, width: 190, color: yellow.withAlphaComponent(0.26))
    drawPill("GAD-7", x: x + 244, y: y + 80, width: 190)
    drawPill("YMRS", x: x + 460, y: y + 80, width: 190)

    y -= 472
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 410), color: card, radius: 28)
    drawText("Nas últimas 2 semanas, com que frequência você se sentiu desanimada?", rect: CGRect(x: x + 32, y: y + 302, width: 820, height: 90), size: 28, weight: .semibold, lineSpacing: 4)
    let labels = ["Nunca", "Alguns dias", "Mais da metade", "Quase todos"]
    for (index, label) in labels.enumerated() {
        let rowY = y + 224 - CGFloat(index) * 58
        fillRounded(CGRect(x: x + 32, y: rowY, width: screen.width - 172, height: 44), color: index == 1 ? yellow.withAlphaComponent(0.22) : cardLight, radius: 16)
        drawText(label, rect: CGRect(x: x + 54, y: rowY + 11, width: 680, height: 24), size: 20, weight: index == 1 ? .semibold : .regular, color: index == 1 ? yellow : white)
    }
}

try makeImage(
    fileName: "03-configuracoes-modo-local.png",
    title: "Privacidade em primeiro lugar",
    subtitle: "Nesta versão, seus registros ficam no aparelho. Exporte backups quando quiser."
) { screen in
    drawStatusBar(in: screen, title: "Configurações")

    let x = screen.minX + 54
    var y = screen.maxY - 450
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 178), color: card, radius: 28, stroke: NSColor.systemGreen.withAlphaComponent(0.25))
    drawText("Modo local", rect: CGRect(x: x + 32, y: y + 106, width: 520, height: 42), size: 34, weight: .bold, color: NSColor.systemGreen)
    drawText("Seus registros ficam neste aparelho. Login e sincronização remota não estão disponíveis nesta versão.", rect: CGRect(x: x + 32, y: y + 42, width: 780, height: 54), size: 22, color: muted, lineSpacing: 3)

    y -= 282
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 236), color: card, radius: 28)
    drawText("Meus dados", rect: CGRect(x: x + 32, y: y + 164, width: 520, height: 42), size: 34, weight: .bold, color: yellow)
    drawText("Exportar, apagar e revisar informações do app.", rect: CGRect(x: x + 32, y: y + 118, width: 740, height: 32), size: 22, color: muted)
    fillRounded(CGRect(x: x + 32, y: y + 38, width: 348, height: 58), color: yellow, radius: 20)
    drawText("Gerar backup", rect: CGRect(x: x + 54, y: y + 54, width: 304, height: 28), size: 21, weight: .bold, color: navy, alignment: .center)

    y -= 352
    fillRounded(CGRect(x: x, y: y, width: screen.width - 108, height: 310), color: card, radius: 28)
    drawText("Como seus dados são protegidos", rect: CGRect(x: x + 32, y: y + 236, width: 820, height: 42), size: 31, weight: .bold)
    let rows = [
        ("Uso local", "Sem login, convites ou sincronização clínica remota."),
        ("Criptografia", "Textos sensíveis são protegidos antes de serem armazenados."),
        ("LGPD", "Você pode exportar seus dados em formato estruturado.")
    ]
    for (index, row) in rows.enumerated() {
        let rowY = y + 170 - CGFloat(index) * 66
        drawCircle(center: CGPoint(x: x + 58, y: rowY + 22), radius: 13, color: yellow)
        drawText(row.0, rect: CGRect(x: x + 88, y: rowY + 26, width: 280, height: 26), size: 22, weight: .semibold)
        drawText(row.1, rect: CGRect(x: x + 88, y: rowY - 2, width: 730, height: 26), size: 18, color: muted)
    }
}

print("Screenshots saved to \(outputDirectory.path)")
