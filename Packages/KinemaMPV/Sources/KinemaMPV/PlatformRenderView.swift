#if canImport(SwiftUI) && (os(iOS) || os(tvOS))
import SwiftUI
import UIKit
import OpenGLES
import Darwin
import KinemaCore
import LibMPV

/// VLC-style iOS / tvOS render surface — OpenGL ES into `CAEAGLLayer`, resize on every layout.
private let iosOpenGLProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
    guard let name else { return nil }
    let symbol = String(cString: name) as CFString
    if let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString),
       let pointer = CFBundleGetFunctionPointerForName(bundle, symbol) {
        return pointer
    }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
}

private let iosRenderUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
    guard let ctx else { return }
    let view = Unmanaged<GLESRenderSurface>.fromOpaque(ctx).takeUnretainedValue()
    view.scheduleRedraw()
}

public final class GLESRenderSurface: UIView, MPVRenderSurface {
    private weak var controller: MPVController?
    private var renderContext: OpaquePointer?
    private var eaglContext: EAGLContext?
    private var renderBuffer: GLuint = 0
    private var frameBuffer: GLuint = 0
    private var pixelWidth: GLint = 1
    private var pixelHeight: GLint = 1
    private var bufferNeedsReset = true
    private var redrawScheduled = false
    private let redrawLock = NSLock()

    public override class var layerClass: AnyClass { CAEAGLLayer.self }

    private var eaglLayer: CAEAGLLayer { layer as! CAEAGLLayer }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentMode = .scaleToFill
        eaglLayer.isOpaque = true
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]
        eaglContext = EAGLContext(api: .openGLES2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func attach(to controller: MPVController) {
        self.controller = controller
        setupRenderContextIfNeeded()
        setNeedsLayout()
    }

    public func detach() {
        clearRenderContext()
        controller = nil
        deleteGLBuffers()
    }

    public func requestLayoutUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.nativeScale ?? contentScaleFactor
        let pixelW = Int((bounds.width * scale).rounded())
        let pixelH = Int((bounds.height * scale).rounded())
        if abs(contentScaleFactor - scale) > 0.01 {
            contentScaleFactor = scale
            bufferNeedsReset = true
        }
        if pixelW != Int(pixelWidth) || pixelH != Int(pixelHeight) {
            bufferNeedsReset = true
        }
        // Avoid scheduling a redraw storm from unrelated layout passes while idle.
        if renderContext != nil {
            scheduleRedraw()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            contentScaleFactor = window.screen.nativeScale
            bufferNeedsReset = true
            setupRenderContextIfNeeded()
            scheduleRedraw()
        }
    }

    public override func display(_ layer: CALayer) {
        renderFrame()
    }

    public override func setNeedsDisplay() {
        layer.setNeedsDisplay()
    }

    func scheduleRedraw() {
        redrawLock.lock()
        guard !redrawScheduled else {
            redrawLock.unlock()
            return
        }
        redrawScheduled = true
        redrawLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.redrawLock.lock()
            self.redrawScheduled = false
            self.redrawLock.unlock()
            self.setNeedsDisplay()
        }
    }

    private func pixelScale() -> CGFloat {
        window?.screen.nativeScale ?? traitCollection.displayScale
    }

    private func resetBuffersIfNeeded() {
        guard bufferNeedsReset, let eaglContext else { return }
        bufferNeedsReset = false
        deleteGLBuffers()

        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)

        glGenRenderbuffers(1, &renderBuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
        guard eaglContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer) else {
            NSLog("Kinema: failed to bind EAGL renderbuffer storage")
            return
        }
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_RENDERBUFFER),
            renderBuffer
        )

        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &pixelWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &pixelHeight)

        if glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            NSLog("Kinema: incomplete OpenGL framebuffer (%dx%d)", pixelWidth, pixelHeight)
        }
    }

    private func deleteGLBuffers() {
        if frameBuffer != 0 {
            var fb = frameBuffer
            glDeleteFramebuffers(1, &fb)
            frameBuffer = 0
        }
        if renderBuffer != 0 {
            var rb = renderBuffer
            glDeleteRenderbuffers(1, &rb)
            renderBuffer = 0
        }
    }

    private func renderFrame() {
        setupRenderContextIfNeeded()
        guard let eaglContext else { return }
        guard EAGLContext.setCurrent(eaglContext) else { return }

        resetBuffersIfNeeded()
        guard frameBuffer != 0, renderBuffer != 0, pixelWidth > 0, pixelHeight > 0 else { return }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
        glViewport(0, 0, GLsizei(pixelWidth), GLsizei(pixelHeight))

        guard let renderContext else {
            eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
            return
        }

        _ = mpv_render_context_update(renderContext)

        var flip: Int32 = 1
        var fbo = mpv_opengl_fbo(
            fbo: GLint(frameBuffer),
            w: max(pixelWidth, 1),
            h: max(pixelHeight, 1),
            internal_format: GLint(GL_RGBA8)
        )

        withUnsafePointer(to: &fbo) { fboPointer in
            withUnsafePointer(to: &flip) { flipPointer in
                var params: [mpv_render_param] = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(mutating: fboPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(mutating: flipPointer)
                    ),
                    mpv_render_param(type: mpv_render_param_type(0), data: nil)
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
        eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
        mpv_render_context_report_swap(renderContext)
    }

    private func setupRenderContextIfNeeded() {
        guard renderContext == nil,
              let controller,
              let handle = controller.mpvHandle(),
              let eaglContext else { return }

        guard EAGLContext.setCurrent(eaglContext) else { return }

        var initParams = mpv_opengl_init_params(
            get_proc_address: iosOpenGLProcAddress,
            get_proc_address_ctx: nil
        )
        var createdContext: OpaquePointer?

        let status = withUnsafePointer(to: &initParams) { initPointer in
            MPV_RENDER_API_TYPE_OPENGL.withCString { apiPointer in
                var params: [mpv_render_param] = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_API_TYPE,
                        data: UnsafeMutableRawPointer(mutating: apiPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                        data: UnsafeMutableRawPointer(mutating: initPointer)
                    ),
                    mpv_render_param(type: mpv_render_param_type(0), data: nil)
                ]
                return mpv_render_context_create(&createdContext, handle, &params)
            }
        }

        guard status >= 0, let createdContext else {
            NSLog("Kinema: failed to create mpv OpenGL render context (%d)", status)
            return
        }

        renderContext = createdContext
        mpv_render_context_set_update_callback(
            createdContext,
            iosRenderUpdateCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        bufferNeedsReset = true
        scheduleRedraw()
        NSLog(
            "Kinema: OpenGL render surface ready (%.0fx%.0f @ %.0fx scale)",
            bounds.width,
            bounds.height,
            pixelScale()
        )
    }

    private func clearRenderContext() {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }
}

public final class GLESRenderContainerView: UIView {
    let surface: GLESRenderSurface

    public init(surface: GLESRenderSurface) {
        self.surface = surface
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .black
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

public struct MPVPlatformView: UIViewControllerRepresentable {
    public let surface: GLESRenderSurface

    public init(surface: GLESRenderSurface = GLESRenderSurface()) {
        self.surface = surface
    }

    public func makeUIViewController(context: Context) -> PlayerRenderViewController {
        PlayerRenderViewController(surface: surface)
    }

    public func updateUIViewController(_ controller: PlayerRenderViewController, context: Context) {}
}

public final class PlayerRenderViewController: UIViewController {
    let container: GLESRenderContainerView

    init(surface: GLESRenderSurface) {
        container = GLESRenderContainerView(surface: surface)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func loadView() {
        view = container
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.container.surface.requestLayoutUpdate()
        }
    }
}

public typealias AVFoundationRenderSurface = GLESRenderSurface
public typealias IOSRenderSurface = GLESRenderSurface
public typealias IOSRenderContainerView = GLESRenderContainerView
#endif

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import KinemaCore
import LibMPV

private let macOSOpenGLProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
    guard let name else { return nil }
    let symbol = String(cString: name) as CFString
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
          let pointer = CFBundleGetFunctionPointerForName(bundle, symbol) else { return nil }
    return pointer
}

private let macOSRenderUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
    guard let ctx else { return }
    let view = Unmanaged<MacOSRenderSurface>.fromOpaque(ctx).takeUnretainedValue()
    view.scheduleRedraw()
}

public final class MacOSRenderSurface: NSOpenGLView, MPVRenderSurface {
    private weak var controller: MPVController?
    private var renderContext: OpaquePointer?
    private var redrawScheduled = false
    private let redrawLock = NSLock()

    public override init(frame frameRect: NSRect) {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            0
        ]
        super.init(frame: frameRect, pixelFormat: NSOpenGLPixelFormat(attributes: attributes))!
        autoresizingMask = [.width, .height]
        if let context = openGLContext {
            var swapInterval: GLint = 0
            context.setValues(&swapInterval, for: .swapInterval)
        }
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func attach(to controller: MPVController) {
        self.controller = controller
        setupRenderContextIfNeeded()
    }

    public func detach() {
        clearRenderContext()
        controller = nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupRenderContextIfNeeded()
    }

    public override func reshape() {
        super.reshape()
        openGLContext?.update()
        scheduleRedraw()
    }

    func scheduleRedraw() {
        redrawLock.lock()
        guard !redrawScheduled else {
            redrawLock.unlock()
            return
        }
        redrawScheduled = true
        redrawLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.redrawLock.lock()
            self.redrawScheduled = false
            self.redrawLock.unlock()
            self.needsDisplay = true
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        setupRenderContextIfNeeded()
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        context.update()

        guard let renderContext else {
            context.flushBuffer()
            return
        }

        let backing = convertToBacking(bounds)
        var flip: Int32 = 1
        var fbo = mpv_opengl_fbo(
            fbo: 0,
            w: Int32(max(backing.width, 1)),
            h: Int32(max(backing.height, 1)),
            internal_format: 0
        )

        withUnsafePointer(to: &fbo) { fboPointer in
            withUnsafePointer(to: &flip) { flipPointer in
                var params: [mpv_render_param] = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(mutating: fboPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(mutating: flipPointer)
                    ),
                    mpv_render_param(type: mpv_render_param_type(0), data: nil)
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }

        context.flushBuffer()
        mpv_render_context_report_swap(renderContext)
    }

    public func setNeedsDisplay() {
        needsDisplay = true
    }

    private func setupRenderContextIfNeeded() {
        guard renderContext == nil,
              let controller,
              let handle = controller.mpvHandle(),
              let context = openGLContext else { return }

        context.makeCurrentContext()

        var initParams = mpv_opengl_init_params(
            get_proc_address: macOSOpenGLProcAddress,
            get_proc_address_ctx: nil
        )
        var createdContext: OpaquePointer?

        let status = withUnsafePointer(to: &initParams) { initPointer in
            MPV_RENDER_API_TYPE_OPENGL.withCString { apiPointer in
                var params: [mpv_render_param] = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_API_TYPE,
                        data: UnsafeMutableRawPointer(mutating: apiPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                        data: UnsafeMutableRawPointer(mutating: initPointer)
                    ),
                    mpv_render_param(type: mpv_render_param_type(0), data: nil)
                ]
                return mpv_render_context_create(&createdContext, handle, &params)
            }
        }

        guard status >= 0, let createdContext else { return }
        renderContext = createdContext
        mpv_render_context_set_update_callback(
            createdContext,
            macOSRenderUpdateCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        needsDisplay = true
    }

    private func clearRenderContext() {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }
}

public final class MacOSRenderContainerView: NSView {
    let surface: MacOSRenderSurface
    private var lastLayoutSize = NSSize.zero

    public init(surface: MacOSRenderSurface) {
        self.surface = surface
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func layout() {
        super.layout()
        let size = bounds.size
        guard size != lastLayoutSize else { return }
        lastLayoutSize = size
        surface.scheduleRedraw()
    }
}

public struct MPVPlatformView: NSViewRepresentable {
    public let surface: MacOSRenderSurface

    public init(surface: MacOSRenderSurface = MacOSRenderSurface()) {
        self.surface = surface
    }

    public func makeNSView(context: Context) -> MacOSRenderContainerView {
        MacOSRenderContainerView(surface: surface)
    }

    public func updateNSView(_ nsView: MacOSRenderContainerView, context: Context) {}
}
#endif
