# JuYing Domain Model

Ubiquitous language for the JuYing cross-platform home media hub and unified playback player.

## Language

### Core & Playback

**PlayableOption**:
A fully resolved media target ready for ingestion by a playback engine, carrying the concrete stream URL, HTTP headers, and decoding flags.
_Avoid_: StreamUrl, MediaTarget, PlayLink

**PlaybackSession**:
An active, stateful playback lifecycle instance initiated from local user selection, DLNA push, or AirPlay stream.
_Avoid_: PlayTask, VideoJob, PlayerContext

**PlayerEngine**:
An abstracted playback controller contract wrapping concrete media backends (libmpv or Media3).
_Avoid_: VideoWidget, PlayerWrapper

### Sources & Content

**Source**:
A configured external subscription, local storage mount, or media provider entry point owned by the user.
_Avoid_: Feed, Repository, ChannelList

**Channel**:
A logical broadcast channel entity containing one or more playable stream lines and optional EPG metadata.
_Avoid_: Station, LiveItem

**Line**:
A specific physical streaming address under a Channel with an associated health score and latency history.
_Avoid_: Route, StreamSource, UrlVariant

**MediaItem**:
A browsable or searchable on-demand video item or NAS file asset with metadata references.
_Avoid_: VideoItem, FileNode, VodEntry

**TvBoxSite**:
A remote or local content site configuration parsed from a TVBox warehouse subscription.
_Avoid_: SpiderSite, VodSource

**PortedSpider**:
A TVBox crawler logic re-implemented natively in pure Dart and sandboxed within `source_providers`.
_Avoid_: CustomSpider, DartCrawler

**DexRuntime**:
An Android platform-isolated Dalvik/ART class loader executing external CatVod JAR binaries under explicit user consent.
_Avoid_: JvmSandbox, PluginRunner

### Network & Casting

**LoopbackProxy**:
A local HTTP service strictly bound to IPv4 loopback (127.0.0.1:9978) providing range requests, header injection, and HLS playlist rewriting for the local playback engine without network exposure.
_Avoid_: MediaServer, LocalServer, HttpServer

**LanGateway**:
An on-demand local network HTTP gateway serving temporary DLNA cast streams and a secured remote web configuration portal.
_Avoid_: PublicProxy, RemoteServer

**PairingPin**:
A short-lived 6-digit numeric verification code rendered on TV display to authorize LAN configuration push sessions.
_Avoid_: AuthCode, SecretKey, SessionPassword

**CastDevice**:
A discovered remote rendering target (such as a DLNA MediaRenderer) capable of receiving transport commands and playback URLs.
_Avoid_: RemoteTv, TargetScreen

### UI & Presentation

**TvFocusGlow**:
An Apple TV-inspired focus wrapper applying progressive zoom, border glow, and predictable directional D-Pad traversal to interactive widgets.
_Avoid_: FocusRing, HoverBorder, HighlightBox

**LowPerformanceMode**:
An adaptive UI degradation policy that automatically converts expensive GPU BackdropFilter blurs into opaque or translucent flat colors on resource-constrained TV chipsets.
_Avoid_: FastMode, CheapGraphics, SimpleTheme
