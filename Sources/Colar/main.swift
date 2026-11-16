// Colar, Fase 1: captura o clipboard para o histórico (SQLite + blobs), filtra o que é confidencial, aplica a retenção
// e mostra o histórico no painel do ⌘⇧V. Enter cola fiel (todos os tipos), Shift+Enter cola texto puro.
import AppKit
import Carbon
import ColarCore
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let painel = ColarPanel()
    private let previa = PreviaPanel()
    private let janelaEditor = JanelaEditor()
    private let janelaPilha = JanelaPilha()
    private let pilha = PilhaColagem()
    private var escuta: EscutaCmdV!
    private var historico: Historico!
    private var coletor: Coletor!
    private var modelo: PainelModelo!
    private var statusItem: NSStatusItem!
    private var monitorTeclas: Any?
    private var monitorCliqueFora: Any?
    private var atalhoTexto = "—"
    private var timerRetencao: Timer?
    private var avisouAcessibilidade = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(abrirURL(_:resposta:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    /// colar://abrir · colar://fechar · colar://foto (salva o painel em ~/Library/Logs/Colar/painel.png).
    /// Plano F18; adiantado para diagnóstico (eu abro e fotografo o painel vivo pelo terminal).
    @objc private func abrirURL(_ evento: NSAppleEventDescriptor, resposta: NSAppleEventDescriptor) {
        guard let s = evento.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        Diario.anotar("url \(s)")
        switch url.host {
        case "abrir": mostrar()
        case "fechar": esconder()
        case "foto":
            let destino = Diario.url.deletingLastPathComponent().appendingPathComponent("painel.png")
            Diario.anotar("foto do painel: visivel=\(painel.isVisible) itens=\(modelo.itens.count) ok=\(painel.fotografar(para: destino))")
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            historico = try Historico()
        } catch {
            Diario.anotar("ERRO ao abrir o histórico: \(error)")
            let a = NSAlert(); a.messageText = "O Colar não conseguiu abrir o histórico"; a.informativeText = "\(error)"; a.runModal()
            NSApp.terminate(nil); return
        }
        modelo = PainelModelo(historico: historico)
        painel.contentView = NSHostingView(rootView: PainelView(modelo: modelo) { [weak self] i in self?.colar(indice: i, textoPuro: false) })
        modelo.acoes.colar = { [weak self] i, puro in self?.colar(indice: i, textoPuro: puro) }
        modelo.acoes.editar = { [weak self] it in self?.abrirEditor(.editar(it)) }
        modelo.acoes.pilha = { [weak self] it in self?.porNaPilha(it.id) }
        modelo.acoes.apagar = { [weak self] it in try? self?.historico.apagar(it.id); self?.modelo.recarregar() }
        escuta = EscutaCmdV { [weak self] in self?.pilhaCmdV() }
        painel.sharingType = historico.config("painel_capturavel") == "1" ? NSWindow.SharingType.readOnly : NSWindow.SharingType.none
        previa.sharingType = painel.sharingType

        coletor = Coletor(historico: historico)
        coletor.pausado = historico.config("pausado") == "1"
        coletor.appsIgnorados = Set((historico.config("apps_ignorados") ?? "").split(separator: ",").map(String.init))
        coletor.aoMudar = { [weak self] d in self?.capturou(d) }
        coletor.iniciar()

        aplicarRetencao()
        lerImagensPendentes()
        timerRetencao = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.aplicarRetencao() }

        registrarAtalho()
        montarMenu()
        garantirInicioComOMac()
        if !Paster.temAcessibilidade { Paster.pedirAcessibilidade() }
        Diario.anotar("iniciado; acessibilidade=\(Paster.temAcessibilidade) atalho=\(atalhoTexto) v=\(KeyboardLayout.vAtual()) layout=\(KeyboardLayout.id(KeyboardLayout.atual())) itens=\((try? historico.recentes(limite: 100_000).count) ?? -1) retencao=\(historico.retencao.rawValue)")
    }

    // MARK: captura

    private func capturou(_ d: Coletor.Decisao) {
        switch d {
        case .gravado(.novo(let id)):
            porNaPilha(id, soSeAtiva: true)
            let it = try? historico.item(id: id)
            Diario.anotar("capturado \(it?.tipo.rawValue ?? "?") \(it?.tamanho ?? 0) de \(it?.appBundle ?? "?")")
            if historico.sons { Sons.copiou() }
            if it?.tipo == .imagem { lerImagensPendentes() }
            if let it, it.tipo == .link, let url = URL(string: it.texto ?? "") {
                PreviaLink.buscar(itemId: id, url: url, historico: historico) { [weak self] ok in
                    Diario.anotar("prévia do link \(url.host ?? "?"): \(ok ? "ok" : "falhou")")
                    if self?.painel.isVisible == true { self?.modelo.recarregar() }
                }
            }
        case .gravado(.repetido(let id)):
            porNaPilha(id, soSeAtiva: true)
            Diario.anotar("capturado repetido: subiu para o topo")
            if historico.sons { Sons.copiou() }
        case .ignorado(let motivo): Diario.anotar("ignorado: \(motivo)")
        case .colarProprio: break
        case .vazio: break
        }
        if painel.isVisible { modelo.recarregar() }
    }

    /// OCR das imagens ainda não lidas (as novas e, no primeiro uso da Fase 3, as que já estavam no histórico).
    private func lerImagensPendentes() {
        OCR.processarPendentes(historico) { [weak self] _, caracteres in
            Diario.anotar("ocr: \(caracteres) caracteres")
            if self?.painel.isVisible == true, self?.modelo.buscando == true { self?.modelo.recarregar() }
        }
    }

    private func aplicarRetencao() {
        let n = (try? historico.aplicarRetencao(historico.retencao)) ?? 0
        if n > 0 { Diario.anotar("retenção \(historico.retencao.rawValue): \(n) itens removidos") }
    }

    // MARK: atalho

    private func registrarAtalho() {
        // ⇧⌘C: fila de colagem
        let c = UInt32(KeyboardLayout.keyCode(para: "c", em: KeyboardLayout.atual()) ?? 8)
        let rp = HotKeys.shared.registrar(keyCode: c, HotKeys.cmd | HotKeys.shift) { [weak self] in self?.alternarPilha() }
        if rp.status != noErr { Diario.anotar("atalho ⇧⌘C (fila de colagem) falhou com \(rp.status)") }
        let v = UInt32(KeyboardLayout.vAtual())
        let r = HotKeys.shared.registrar(keyCode: v, HotKeys.cmd | HotKeys.shift) { [weak self] in self?.alternar() }
        if r.status == noErr { atalhoTexto = "⌘⇧V"; return }
        let reserva = HotKeys.shared.registrar(keyCode: v, HotKeys.cmd | HotKeys.shift | HotKeys.option) { [weak self] in self?.alternar() }
        atalhoTexto = reserva.status == noErr ? "⌥⌘⇧V (⌘⇧V ocupado: \(r.status))" : "nenhum (\(r.status), \(reserva.status))"
        Diario.anotar("atalho ⌘⇧V falhou com \(r.status); reserva \(reserva.status)")
    }

    // MARK: menu

    private enum Tag: Int { case pausar = 1, acessibilidade, print, retencao, modoApp, modoClipboard, textoPuro, sons, login }

    private func montarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Colar")
        let menu = NSMenu()
        menu.addItem(item("Abrir o Colar", #selector(abrirPeloMenu)))
        menu.addItem(item("Pausar captura", #selector(alternarPausa), tag: .pausar))
        menu.addItem(item("Fila de colagem (⇧⌘C)", #selector(menuPilha)))
        menu.addItem(.separator())

        let ret = NSMenuItem(title: "Manter histórico", action: nil, keyEquivalent: "")
        ret.tag = Tag.retencao.rawValue
        let sub = NSMenu()
        let nomes: [Historico.Retencao: String] = [.dia: "Dia", .semana: "Semana", .mes: "Mês", .ano: "Ano", .sempre: "Para sempre"]
        for r in Historico.Retencao.allCases {
            let i = NSMenuItem(title: nomes[r]!, action: #selector(escolherRetencao(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = r.rawValue
            sub.addItem(i)
        }
        ret.submenu = sub
        menu.addItem(ret)
        let colarItens = NSMenuItem(title: "Colar itens", action: nil, keyEquivalent: "")
        let subColar = NSMenu()
        subColar.addItem(item("No app ativo", #selector(modoApp), tag: .modoApp))
        subColar.addItem(item("Só copiar (colo depois)", #selector(modoClipboard), tag: .modoClipboard))
        subColar.addItem(.separator())
        subColar.addItem(item("Sempre colar sem formatação", #selector(alternarTextoPuro), tag: .textoPuro))
        colarItens.submenu = subColar
        menu.addItem(colarItens)
        menu.addItem(item("Iniciar com o Mac", #selector(alternarLogin), tag: .login))
        menu.addItem(item("Efeitos sonoros", #selector(alternarSons), tag: .sons))
        menu.addItem(item("Permitir print do painel", #selector(alternarPrint), tag: .print))
        menu.addItem(item("Apagar histórico…", #selector(apagarHistorico)))
        menu.addItem(.separator())
        let atalho = menu.addItem(withTitle: "Atalho: \(atalhoTexto)", action: nil, keyEquivalent: "")
        atalho.isEnabled = false
        menu.addItem(item("", #selector(acessibilidade), tag: .acessibilidade))
        menu.addItem(item("Abrir o diário", #selector(abrirDiario)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do Colar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ titulo: String, _ acao: Selector, tag: Tag? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: titulo, action: acao, keyEquivalent: "")
        i.target = self
        if let tag { i.tag = tag.rawValue }
        return i
    }

    @objc private func abrirPeloMenu() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.mostrar() } }

    @objc private func alternarPausa() {
        coletor.pausado.toggle()
        historico.definir("pausado", coletor.pausado ? "1" : "0")
        statusItem.button?.appearsDisabled = coletor.pausado
        Diario.anotar(coletor.pausado ? "captura pausada" : "captura retomada")
    }

    @objc private func escolherRetencao(_ sender: NSMenuItem) {
        guard let r = (sender.representedObject as? String).flatMap(Historico.Retencao.init) else { return }
        historico.retencao = r
        aplicarRetencao()
    }

    @objc private func menuPilha() { alternarPilha() }
    @objc private func modoApp() { historico.modoColar = .appAtivo; Diario.anotar("modo: colar no app ativo") }
    @objc private func modoClipboard() { historico.modoColar = .areaTransferencia; Diario.anotar("modo: só copiar") }
    @objc private func alternarTextoPuro() { historico.sempreTextoPuro.toggle(); Diario.anotar("sempre texto puro: \(historico.sempreTextoPuro)") }
    @objc private func alternarSons() { historico.sons.toggle(); Diario.anotar("sons: \(historico.sons)") }

    @objc private func alternarPrint() {
        let antes = painel.sharingType
        let capturavel = antes == NSWindow.SharingType.none
        painel.sharingType = capturavel ? NSWindow.SharingType.readOnly : NSWindow.SharingType.none
        previa.sharingType = painel.sharingType
        historico.definir("painel_capturavel", capturavel ? "1" : "0")
        Diario.anotar("print do painel: sharingType \(antes.rawValue) → \(painel.sharingType.rawValue) (\(capturavel ? "aparece" : "não aparece") em print)")
    }

    @objc private func apagarHistorico() {
        let a = NSAlert()
        a.messageText = "Apagar todo o histórico do Colar?"
        a.informativeText = "Todos os itens copiados saem do Colar e não dá para desfazer."
        a.addButton(withTitle: "Apagar"); a.addButton(withTitle: "Cancelar")
        a.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        try? historico.apagarTudo()
        Diario.anotar("histórico apagado pelo menu")
    }

    // MARK: iniciar com o Mac

    /// Liga o item de login (`SMAppService.mainApp`) por padrão, só na cópia de /Applications: a de build não deve
    /// abrir sozinha. Desligado pelo menu, a escolha fica em `iniciar_login=0` e não é religada.
    private func garantirInicioComOMac() {
        guard historico.config("iniciar_login") != "0", Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        let s = SMAppService.mainApp
        guard s.status != .enabled else { return }
        do { try s.register(); Diario.anotar("iniciar com o Mac: registrado (status \(s.status.rawValue))") }
        catch { Diario.anotar("iniciar com o Mac: falhou \(error)") }
    }

    @objc private func alternarLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister(); historico.definir("iniciar_login", "0") }
            else { try s.register(); historico.definir("iniciar_login", "1") }
            Diario.anotar("iniciar com o Mac: status \(s.status.rawValue)")
        } catch {
            Diario.anotar("iniciar com o Mac: falhou \(error)")
            if s.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    @objc private func acessibilidade() {
        Paster.pedirAcessibilidade()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func abrirDiario() { NSWorkspace.shared.open(Diario.url) }

    // MARK: painel

    private func alternar() { painel.isVisible ? esconder() : mostrar() }

    private func mostrar() {
        modelo.selecionado = 0
        if !modelo.limparBusca() { modelo.recarregar() }
        painel.posicionar()
        painel.makeKeyAndOrderFront(nil)   // sem NSApp.activate: o app de baixo continua na frente
        let frente = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        Diario.anotar("painel aberto; app da frente=\(frente); key=\(painel.isKeyWindow); itens=\(modelo.itens.count)")

        monitorTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.tecla(e) == true ? nil : e
        }
        monitorCliqueFora = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if ColarPanel.printDoSistemaAtivo() { return }   // clique do ⌘⇧4/⌘⇧5 não fecha o painel
            self?.esconder()
        }
    }

    private func esconder() {
        previa.orderOut(nil)
        janelaEditor.orderOut(nil)
        painel.orderOut(nil)
        if let m = monitorTeclas { NSEvent.removeMonitor(m); monitorTeclas = nil }
        if let m = monitorCliqueFora { NSEvent.removeMonitor(m); monitorCliqueFora = nil }
    }

    /// true = tecla tratada (não chega ao campo de busca). O resto (letras, ⌫, espaço durante a busca) vai para o
    /// campo, que está focado. Não registra a tecla digitada no diário: o que se busca não vai para log (Fase 3).
    private func tecla(_ e: NSEvent) -> Bool {
        guard e.window === painel else { return false }   // editor e outras janelas recebem o próprio teclado
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let opt = e.modifierFlags.contains(.option)
        if modelo.nomeEmEdicao != nil {   // digitando nome de pinboard: só Esc e Enter são nossos
            switch Int(e.keyCode) {
            case kVK_Escape: _ = modelo.limparBusca(); return true
            case kVK_Return, kVK_ANSI_KeypadEnter: modelo.confirmarNome(); return true
            default: return false
            }
        }
        switch Int(e.keyCode) {
        case kVK_Escape:
            if previa.isVisible { previa.orderOut(nil) } else if !modelo.limparBusca() { esconder() }
        case kVK_LeftArrow where cmd: modelo.trocarAba(-1)
        case kVK_RightArrow where cmd: modelo.trocarAba(1)
        case kVK_Return where opt, kVK_ANSI_KeypadEnter where opt:
            if let it = modelo.atual { porNaPilha(it.id) }
        case kVK_ANSI_E where cmd: if let it = modelo.atual { abrirEditor(.editar(it)) }
        case kVK_ANSI_N where cmd: abrirEditor(.novo(pinboard: modelo.pinboardAtual, nomePinboard: modelo.nomePinboardAtual))
        case kVK_LeftArrow: modelo.mover(-1); atualizarPrevia()
        case kVK_RightArrow: modelo.mover(1); atualizarPrevia()
        case kVK_Return, kVK_ANSI_KeypadEnter: colar(indice: modelo.selecionado, textoPuro: shift)
        case kVK_Tab: modelo.proximoTipo(shift ? -1 : 1)
        case kVK_Space where modelo.busca.isEmpty: alternarPrevia()
        case kVK_Delete where cmd, kVK_ForwardDelete where cmd:
            // ⌘⌫ apaga o item (⌫ sozinho edita a busca)
            if let it = modelo.atual { try? historico.apagar(it.id); modelo.recarregar(); Diario.anotar("apagado pelo painel") }
        default:
            // ⌘1…9 cola o item da posição; com ⇧ inverte a formatação.
            if cmd, let n = numeroDaTecla(e.keyCode), n <= modelo.itens.count {
                colar(indice: n - 1, textoPuro: shift)
            } else { return false }
        }
        return true
    }

    /// keyCode físico das teclas 1…9 da fileira de cima → número. Pelo código físico porque com ⇧ o caractere vira !@#…
    private func numeroDaTecla(_ k: UInt16) -> Int? {
        let mapa: [Int: Int] = [kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
                                 kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9]
        return mapa[Int(k)]
    }

    // MARK: prévia

    private func alternarPrevia() {
        if previa.isVisible { previa.orderOut(nil) } else { atualizarPrevia(abrir: true) }
    }

    /// Mostra (ou troca) a prévia do item selecionado. Com `abrir: false`, só atualiza se já estiver aberta.
    private func atualizarPrevia(abrir: Bool = false) {
        guard abrir || previa.isVisible, let item = modelo.atual else { return }
        previa.contentView = NSHostingView(rootView: PreviaView(conteudo: ConteudoPrevia(item: item, historico: historico),
                                                                 direcao: modelo.direcao))
        previa.posicionar(acima: painel)
        previa.orderFront(nil)
    }

    // MARK: editor

    private func abrirEditor(_ modo: EditorView.Modo) {
        janelaEditor.contentView = NSHostingView(rootView: EditorView(modo: modo, direcao: modelo.direcao, salvar: { [weak self] titulo, conteudo in
            guard let self else { return nil }
            do {
                switch modo {
                case .editar(let it):
                    try self.historico.atualizarItem(it.id, titulo: titulo, conteudo: conteudo == it.texto ? nil : conteudo)
                    Diario.anotar("item editado (\(it.tipo.rawValue))")
                case .novo(let pb, _):
                    try self.historico.criarItem(conteudo ?? "", titulo: titulo.isEmpty ? nil : titulo, pinboard: pb)
                    Diario.anotar("item novo \(pb == nil ? "no histórico" : "em pinboard")")
                }
            } catch let e as ErroEdicao { return e.description } catch { return "\(error)" }
            self.fecharEditor()
            return nil
        }, cancelar: { [weak self] in self?.fecharEditor() }))
        previa.orderOut(nil)
        janelaEditor.posicionar(acima: painel)
        janelaEditor.makeKeyAndOrderFront(nil)
    }

    private func fecharEditor() {
        janelaEditor.orderOut(nil)
        modelo.recarregar()
        if painel.isVisible { painel.makeKey() }
    }

    // MARK: Fila de colagem

    private func alternarPilha() {
        if pilha.ativa { encerrarPilha("⇧⌘C") } else { iniciarPilha() }
    }

    private func iniciarPilha() {
        guard !pilha.ativa else { return }
        guard escuta.ligar() else {
            Diario.anotar("fila de colagem: sem Acessibilidade, não dá para escutar o ⌘V")
            Paster.pedirAcessibilidade(); NSSound.beep(); return
        }
        pilha.ativa = true
        Diario.anotar("fila de colagem ligado")
        atualizarJanelaPilha()
    }

    private func encerrarPilha(_ motivo: String) {
        escuta.desligar()
        pilha.ativa = false
        janelaPilha.orderOut(nil)
        Diario.anotar("fila de colagem encerrado (\(motivo))")
    }

    /// Põe na fila. `soSeAtiva`: vindo da captura, só entra se a pilha já estiver ligada.
    private func porNaPilha(_ id: String, soSeAtiva: Bool = false) {
        if !pilha.ativa { if soSeAtiva { return }; iniciarPilha() }
        guard pilha.ativa else { return }
        pilha.adicionar(id)
        atualizarJanelaPilha()
    }

    /// Dentro do callback do ⌘V, antes de o app da frente ler o pasteboard.
    private func pilhaCmdV() {
        guard let id = pilha.proximo() else { return }
        let reps = (try? historico.representacoes(de: id)) ?? []
        Paster.escrever(itemId: id, representacoes: reps)
        try? historico.marcarUsado(id)
        Diario.anotar("fila de colagem colou \(pilha.colados), faltam \(pilha.ids.count)")
        if pilha.vazia {
            // espera o app ler o pasteboard antes de desligar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.pilha.vazia == true { self?.encerrarPilha("fila vazia") }
            }
        }
        DispatchQueue.main.async { [weak self] in self?.atualizarJanelaPilha() }
    }

    private func atualizarJanelaPilha() {
        guard pilha.ativa else { return }
        let itens = pilha.ids.compactMap { try? historico.item(id: $0) }
        janelaPilha.contentView = NSHostingView(rootView: PilhaView(itens: itens, colados: pilha.colados, direcao: modelo.direcao) { [weak self] in
            self?.encerrarPilha("botão Encerrar")
        })
        if !janelaPilha.isVisible { janelaPilha.posicionar(); janelaPilha.orderFrontRegardless() }
    }

    // MARK: colar

    /// `shift` = ⇧ apertado. A regra (modo, sempre texto puro, Acessibilidade) está em `Regras.colagem`.
    private func colar(indice: Int, textoPuro shift: Bool) {
        guard modelo.itens.indices.contains(indice) else { return }
        let item = modelo.itens[indice]
        let reps = (try? historico.representacoes(de: item.id)) ?? []
        let frente = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let c = Regras.colagem(tipo: item.tipo, shift: shift, modo: historico.modoColar,
                               sempreTextoPuro: historico.sempreTextoPuro, temAcessibilidade: Paster.temAcessibilidade)
        esconder()
        Paster.escrever(itemId: item.id, representacoes: reps, textoPuro: c.textoPuro ? (item.texto ?? "") : nil)
        try? historico.marcarUsado(item.id)
        let inicio = Date()
        guard c.postarCmdV else {
            Diario.anotar("item \(indice + 1) só copiado (\(c.motivo ?? "")) app=\(frente)")
            if c.motivo == "sem acessibilidade" {
                NSSound.beep()
                // Só o bipe não diz nada: na primeira vez por execução, abre a tela da Acessibilidade.
                if !avisouAcessibilidade { avisouAcessibilidade = true; acessibilidade() }
            } else if historico.sons { Sons.copiou() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let ok = Paster.postarCmdV()
            if self?.historico.sons == true { Sons.colou() }
            Diario.anotar("colou item \(indice + 1) \(item.tipo.rawValue)\(c.textoPuro ? " texto puro" : "") (\(reps.count) tipos) em \(frente); cmdV=\(ok) em \(Int(Date().timeIntervalSince(inicio) * 1000)) ms")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: Tag.acessibilidade.rawValue)?.title = Paster.temAcessibilidade ? "Acessibilidade: liberada ✓" : "Liberar Acessibilidade…"
        menu.item(withTag: Tag.pausar.rawValue)?.state = coletor.pausado ? .on : .off
        menu.item(withTag: Tag.print.rawValue)?.state = painel.sharingType == NSWindow.SharingType.none ? .off : .on
        let sub = menu.items.first { $0.title == "Colar itens" }?.submenu
        sub?.item(withTag: Tag.modoApp.rawValue)?.state = historico.modoColar == .appAtivo ? .on : .off
        sub?.item(withTag: Tag.modoClipboard.rawValue)?.state = historico.modoColar == .areaTransferencia ? .on : .off
        sub?.item(withTag: Tag.textoPuro.rawValue)?.state = historico.sempreTextoPuro ? .on : .off
        menu.item(withTag: Tag.sons.rawValue)?.state = historico.sons ? .on : .off
        menu.item(withTag: Tag.login.rawValue)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for i in menu.item(withTag: Tag.retencao.rawValue)?.submenu?.items ?? [] {
            i.state = (i.representedObject as? String) == historico.retencao.rawValue ? .on : .off
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
