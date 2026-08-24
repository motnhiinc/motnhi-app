import ARKit
import AVFoundation
import Combine
import RealityKit
import UIKit

enum CharacterReaderFailure: String, Error {
  case arUnsupported = "ar_unsupported"
  case arFailed = "ar_failed"
  case audioMissing = "audio_missing"
  case modelMissing = "model_missing"
  case modelLoadFailed = "model_load_failed"
  case audioFailed = "audio_failed"
}

/// How far the child got through a story. Empty for the single-clip scan-any-page flow,
/// which has no pages to track.
struct CharacterReaderProgress {
  let lastPageId: String?
  let pagesRead: [String]

  static let none = CharacterReaderProgress(lastPageId: nil, pagesRead: [])
}

enum CharacterReaderResult {
  /// Carried on cancel as well as completion: cancel is the normal way to leave AR, and the
  /// page the child reached still matters to the player.
  case completed(CharacterReaderProgress)
  case cancelled(CharacterReaderProgress)
  case failure(CharacterReaderFailure)
}

/// One page of the story reader playlist: its clips, in narration order.
///
/// A page holds a list rather than a single clip because curated pages carry several
/// narration segments, and they cannot be joined in general — a page can mix an `.mp3`
/// from the backend with a `.caf` written by device speech synthesis.
struct StoryReaderPage {
  let pageId: String
  let pageNumber: Int
  let audioURLs: [URL]
}

enum CharacterReaderPlaybackState: Equatable {
  case ready
  case playing
  case paused
  case retry

  mutating func pauseForInterruption() -> Bool {
    guard self == .playing else { return false }
    self = .paused
    return true
  }
}

final class CharacterReaderViewController: UIViewController {
  /// Both entry points normalise onto this list, so there is exactly one playback path. The
  /// single-clip scan-any-page flow is simply a one-page, one-clip story.
  private let pages: [StoryReaderPage]
  private let storyMode: Bool
  /// Base name, without extension, of the bundled `.usdz` character to load. Chosen by the
  /// player in Flutter and passed through the bridge's `[a-z0-9_]` allowlist, so only a vetted
  /// bundle resource can be named here; the scan-any-page flow keeps its original default.
  private let modelAssetBaseName: String
  private var pageIndex: Int
  private var clipIndex = 0
  /// Ordered and de-duplicated, so the player receives pages as the child heard them.
  private var pagesRead: [String] = []

  private var onComplete: ((CharacterReaderResult) -> Void)?

  private let arView = ARView(frame: .zero)
  private let guidanceLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let readButton = UIButton(type: .system)
  private let previousButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private let pageLabel = UILabel()
  private let waveStack = UIStackView()
  private let waveBars = (0..<3).map { _ in UIView() }

  private var configuration: ARWorldTrackingConfiguration?
  private var modelTemplate: Entity?
  private var modelLoadCancellable: AnyCancellable?
  private var audioPlayer: AVAudioPlayer?
  private var displayLink: CADisplayLink?
  private var placementTap: UITapGestureRecognizer?
  private var reticleAnchor: AnchorEntity?
  private var reticleEntity: ModelEntity?
  private var currentRaycastResult: ARRaycastResult?
  private var placedModel: Entity?
  private var bobBaseY: Float = 0
  private var bobStartTime: CFTimeInterval?
  private var playbackState = CharacterReaderPlaybackState.ready
  private var completionGate = OneShotGate()
  private var isPlaced = false
  private var hasPlaybackStarted = false
  private var isTerminal = false
  private var isApplicationActive = true
  private var ownsAudioSession = false

  /// Single-clip entry point, unchanged for the scan-any-page flow.
  convenience init(audioURL: URL, onComplete: @escaping (CharacterReaderResult) -> Void) {
    self.init(
      pages: [StoryReaderPage(pageId: "", pageNumber: 1, audioURLs: [audioURL])],
      initialPageIndex: 0,
      storyMode: false,
      onComplete: onComplete
    )
  }

  init(
    pages: [StoryReaderPage],
    initialPageIndex: Int,
    storyMode: Bool,
    modelAssetBaseName: String = "scan_any_page_character",
    onComplete: @escaping (CharacterReaderResult) -> Void
  ) {
    self.pages = pages
    self.storyMode = storyMode
    self.modelAssetBaseName = modelAssetBaseName
    self.pageIndex = min(max(initialPageIndex, 0), max(pages.count - 1, 0))
    self.onComplete = onComplete
    super.init(nibName: nil, bundle: nil)
  }

  private var currentAudioURL: URL? {
    guard pageIndex < pages.count else { return nil }
    let clips = pages[pageIndex].audioURLs
    guard clipIndex < clips.count else { return nil }
    return clips[clipIndex]
  }

  private var progress: CharacterReaderProgress {
    guard storyMode else { return .none }
    return CharacterReaderProgress(
      lastPageId: pageIndex < pages.count ? pages[pageIndex].pageId : nil,
      pagesRead: pagesRead
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    isApplicationActive = UIApplication.shared.applicationState == .active
    configureView()
    observeApplicationLifecycle()
    startReader()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    guard !isTerminal else { return }
    finish(hasPlaybackStarted ? .completed(progress) : .cancelled(progress))
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    modelLoadCancellable?.cancel()
    displayLink?.invalidate()
    audioPlayer?.pause()
    deactivateOwnedAudioSession()
    arView.session.delegate = nil
    arView.session.pause()
  }

  func failPresentation() {
    finish(.failure(.arFailed))
  }

  private func configureView() {
    view.backgroundColor = .black

    arView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(arView)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setTitle("Close", for: .normal)
    closeButton.setTitleColor(.white, for: .normal)
    closeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    closeButton.layer.cornerRadius = 12
    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    view.addSubview(closeButton)

    guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
    guidanceLabel.numberOfLines = 0
    guidanceLabel.textAlignment = .center
    guidanceLabel.textColor = .white
    guidanceLabel.font = .preferredFont(forTextStyle: .headline)
    guidanceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    guidanceLabel.layer.cornerRadius = 12
    guidanceLabel.layer.masksToBounds = true
    guidanceLabel.text = "Preparing character reader"
    view.addSubview(guidanceLabel)

    readButton.translatesAutoresizingMaskIntoConstraints = false
    readButton.setTitle("Read", for: .normal)
    readButton.setTitleColor(.white, for: .normal)
    readButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    readButton.backgroundColor = .systemIndigo
    readButton.layer.cornerRadius = 14
    readButton.isHidden = true
    readButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    view.addSubview(readButton)

    configurePageControls()
    configureWaveBadge()

    NSLayoutConstraint.activate([
      arView.topAnchor.constraint(equalTo: view.topAnchor),
      arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
      closeButton.heightAnchor.constraint(equalToConstant: 48),
      guidanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      guidanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 16),
      guidanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      guidanceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
      guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      readButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      readButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      readButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 148),
      readButton.heightAnchor.constraint(equalToConstant: 56),
      waveStack.centerYAnchor.constraint(equalTo: readButton.centerYAnchor),
      waveStack.trailingAnchor.constraint(equalTo: readButton.leadingAnchor, constant: -14),
      waveStack.widthAnchor.constraint(equalToConstant: 42),
      waveStack.heightAnchor.constraint(equalToConstant: 40),
      previousButton.centerYAnchor.constraint(equalTo: readButton.centerYAnchor),
      previousButton.trailingAnchor.constraint(equalTo: waveStack.leadingAnchor, constant: -12),
      previousButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
      previousButton.heightAnchor.constraint(equalToConstant: 56),
      nextButton.centerYAnchor.constraint(equalTo: readButton.centerYAnchor),
      nextButton.leadingAnchor.constraint(equalTo: readButton.trailingAnchor, constant: 12),
      nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
      nextButton.heightAnchor.constraint(equalToConstant: 56),
      pageLabel.bottomAnchor.constraint(equalTo: readButton.topAnchor, constant: -12),
      pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      pageLabel.heightAnchor.constraint(equalToConstant: 32),
    ])

    let placementTap = UITapGestureRecognizer(target: self, action: #selector(placeCharacter))
    placementTap.isEnabled = false
    arView.addGestureRecognizer(placementTap)
    self.placementTap = placementTap
  }

  /// Page controls exist only in story mode; the scan-any-page flow has a single clip and no
  /// pages to move between, so they stay hidden and unreachable there.
  private func configurePageControls() {
    for (button, title, action) in [
      (previousButton, "Back", #selector(goToPreviousPage)),
      (nextButton, "Next", #selector(goToNextPage)),
    ] {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.setTitle(title, for: .normal)
      button.setTitleColor(.white, for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
      button.backgroundColor = .systemIndigo
      button.layer.cornerRadius = 14
      button.isHidden = true
      button.addTarget(self, action: action, for: .touchUpInside)
      view.addSubview(button)
    }

    pageLabel.translatesAutoresizingMaskIntoConstraints = false
    pageLabel.textAlignment = .center
    pageLabel.textColor = .white
    pageLabel.font = .preferredFont(forTextStyle: .subheadline)
    pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    pageLabel.layer.cornerRadius = 10
    pageLabel.layer.masksToBounds = true
    pageLabel.isHidden = true
    view.addSubview(pageLabel)
  }

  private func configureWaveBadge() {
    waveStack.translatesAutoresizingMaskIntoConstraints = false
    waveStack.axis = .horizontal
    waveStack.alignment = .center
    waveStack.distribution = .fillEqually
    waveStack.spacing = 4
    waveStack.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    waveStack.layer.cornerRadius = 12
    waveStack.isLayoutMarginsRelativeArrangement = true
    waveStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    waveStack.isHidden = true
    view.addSubview(waveStack)

    for (index, bar) in waveBars.enumerated() {
      bar.backgroundColor = .systemGreen
      bar.layer.cornerRadius = 2
      bar.translatesAutoresizingMaskIntoConstraints = false
      bar.heightAnchor.constraint(equalToConstant: index == 1 ? 22 : 14).isActive = true
      waveStack.addArrangedSubview(bar)
    }
  }

  private func observeApplicationLifecycle() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioSessionInterrupted),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  private func startReader() {
    guard ARWorldTrackingConfiguration.isSupported else {
      finish(.failure(.arUnsupported))
      return
    }
    guard let audioURL = currentAudioURL,
          FileManager.default.fileExists(atPath: audioURL.path)
    else {
      finish(.failure(.audioMissing))
      return
    }
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
      guard audioPlayer?.prepareToPlay() == true else {
        finish(.failure(.audioFailed))
        return
      }
      audioPlayer?.delegate = self
      syncPageControls()
    } catch {
      finish(.failure(.audioFailed))
      return
    }
    guard let modelURL = Bundle.main.url(forResource: modelAssetBaseName, withExtension: "usdz") else {
      finish(.failure(.modelMissing))
      return
    }
    guidanceLabel.text = "Loading character"
    modelLoadCancellable = Entity.loadAsync(contentsOf: modelURL)
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          guard let self, !self.isTerminal else { return }
          self.modelLoadCancellable = nil
          if case .failure = completion {
            self.finish(.failure(.modelLoadFailed))
          }
        },
        receiveValue: { [weak self] entity in
          guard let self, !self.isTerminal else { return }
          self.modelTemplate = entity
          self.startARSession()
        }
      )
  }

  private func startARSession() {
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal]
    configuration.environmentTexturing = .automatic
    self.configuration = configuration
    arView.session.delegate = self

    let displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = !isApplicationActive
    self.displayLink = displayLink
    if isApplicationActive {
      activateARSession(configuration)
    } else {
      guidanceLabel.text = "Character reader paused"
    }
  }

  private func activateARSession(_ configuration: ARWorldTrackingConfiguration) {
    arView.session.run(configuration)
    placementTap?.isEnabled = !isPlaced
    if !isPlaced {
      guidanceLabel.text = "Move the iPad slowly to find a table"
    }
  }

  @objc private func updateFrame(_ displayLink: CADisplayLink) {
    guard !isTerminal else { return }
    if isPlaced {
      updateBob(at: displayLink.timestamp)
    } else {
      updateRaycast()
    }
  }

  private func updateRaycast() {
    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    let result = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal).first
      ?? arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first
    currentRaycastResult = result

    guard let result else {
      reticleEntity?.isEnabled = false
      guidanceLabel.text = "Move the iPad slowly to find a table"
      return
    }
    guidanceLabel.text = "Table found - Tap to place the character"
    let anchor = reticleAnchor ?? makeReticleAnchor()
    anchor.transform.matrix = result.worldTransform
    reticleEntity?.isEnabled = true
  }

  private func makeReticleAnchor() -> AnchorEntity {
    let anchor = AnchorEntity(world: matrix_identity_float4x4)
    let material = SimpleMaterial(color: UIColor.systemYellow.withAlphaComponent(0.85), isMetallic: false)
    let reticle = ModelEntity(
      mesh: .generatePlane(width: 0.12, depth: 0.12, cornerRadius: 0.06),
      materials: [material]
    )
    reticle.position.y = 0.001
    anchor.addChild(reticle)
    arView.scene.addAnchor(anchor)
    reticleAnchor = anchor
    reticleEntity = reticle
    return anchor
  }

  @objc private func placeCharacter() {
    guard !isPlaced, let result = currentRaycastResult, let modelTemplate else { return }
    let anchor = reticleAnchor ?? makeReticleAnchor()
    anchor.transform.matrix = result.worldTransform
    reticleEntity?.removeFromParent()
    reticleEntity = nil

    let model = modelTemplate.clone(recursive: true)
    scaleForTable(model)
    anchor.addChild(model)
    placedModel = model
    isPlaced = true
    guidanceLabel.text = "Character ready"
    readButton.isHidden = false
    waveStack.isHidden = false
    previousButton.isHidden = !storyMode
    nextButton.isHidden = !storyMode
    pageLabel.isHidden = !storyMode
    syncPageControls()
    renderPlaybackState()

    if !playFirstAnimation(in: model) {
      bobBaseY = model.position.y
      bobStartTime = CACurrentMediaTime()
    }
  }

  private func scaleForTable(_ model: Entity) {
    let bounds = model.visualBounds(relativeTo: model)
    let largestDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
    guard largestDimension.isFinite, largestDimension > 0 else { return }
    let uniformScale: Float = 0.35 / largestDimension
    model.scale = SIMD3(repeating: uniformScale)
    model.position.y = -bounds.min.y * uniformScale
  }

  private func playFirstAnimation(in entity: Entity) -> Bool {
    if let animation = entity.availableAnimations.first {
      entity.playAnimation(animation.repeat(), transitionDuration: 0.25, startsPaused: false)
      return true
    }
    for child in entity.children where playFirstAnimation(in: child) {
      return true
    }
    return false
  }

  private func updateBob(at timestamp: CFTimeInterval) {
    guard let model = placedModel, let startTime = bobStartTime else { return }
    let phase = Float((timestamp - startTime) * .pi)
    model.position.y = bobBaseY + sin(phase) * 0.008
  }

  @objc private func togglePlayback() {
    guard isPlaced, let audioPlayer else { return }
    if playbackState == .playing {
      audioPlayer.pause()
      playbackState = .paused
      guidanceLabel.text = "Reading paused"
      renderPlaybackState()
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      ownsAudioSession = true
      try session.setActive(true)
      guard audioPlayer.play() else {
        showPlaybackRetry()
        return
      }
      hasPlaybackStarted = true
      playbackState = .playing
      markCurrentPageRead()
      guidanceLabel.text = "Reading aloud"
      renderPlaybackState()
    } catch {
      showPlaybackRetry()
    }
  }

  private func markCurrentPageRead() {
    guard storyMode, pageIndex < pages.count else { return }
    let pageId = pages[pageIndex].pageId
    guard !pageId.isEmpty, !pagesRead.contains(pageId) else { return }
    pagesRead.append(pageId)
  }

  /// Loads the current clip into a fresh player. Returns false rather than finishing: once the
  /// scene is up, an audio failure must not take the child's placed character away.
  @discardableResult
  private func loadCurrentClip() -> Bool {
    guard let url = currentAudioURL,
          FileManager.default.fileExists(atPath: url.path),
          let player = try? AVAudioPlayer(contentsOf: url),
          player.prepareToPlay()
    else {
      return false
    }
    audioPlayer?.pause()
    player.delegate = self
    audioPlayer = player
    return true
  }

  private func startCurrentClip() -> Bool {
    guard let audioPlayer else { return false }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      ownsAudioSession = true
      try session.setActive(true)
      guard audioPlayer.play() else { return false }
      hasPlaybackStarted = true
      playbackState = .playing
      markCurrentPageRead()
      guidanceLabel.text = "Reading aloud"
      renderPlaybackState()
      return true
    } catch {
      return false
    }
  }

  /// Moves between pages without touching the AR session or the placed anchor: only the audio
  /// changes, which is what lets the character stay exactly where the child put it.
  @objc private func goToPreviousPage() { goToPage(by: -1) }

  @objc private func goToNextPage() { goToPage(by: 1) }

  private func goToPage(by delta: Int) {
    guard storyMode, isPlaced else { return }
    let target = pageIndex + delta
    guard target >= 0, target < pages.count else { return }

    let wasPlaying = playbackState == .playing
    pageIndex = target
    clipIndex = 0
    syncPageControls()

    guard loadCurrentClip() else {
      showPlaybackRetry()
      return
    }
    if wasPlaying {
      if !startCurrentClip() { showPlaybackRetry() }
    } else {
      playbackState = .ready
      guidanceLabel.text = "Character ready"
      renderPlaybackState()
    }
  }

  private func syncPageControls() {
    guard storyMode else { return }
    pageLabel.text = "  Page \(pageIndex + 1) of \(pages.count)  "
    previousButton.isEnabled = pageIndex > 0
    nextButton.isEnabled = pageIndex < pages.count - 1
    previousButton.alpha = previousButton.isEnabled ? 1.0 : 0.35
    nextButton.alpha = nextButton.isEnabled ? 1.0 : 0.35
  }

  private func showPlaybackRetry() {
    audioPlayer?.pause()
    playbackState = .retry
    deactivateOwnedAudioSession()
    guidanceLabel.text = "Audio couldn't play - Tap Retry"
    renderPlaybackState()
  }

  private func renderPlaybackState() {
    switch playbackState {
    case .ready:
      readButton.setTitle("Read", for: .normal)
    case .playing:
      readButton.setTitle("Pause", for: .normal)
    case .paused:
      readButton.setTitle("Resume", for: .normal)
    case .retry:
      readButton.setTitle("Retry", for: .normal)
    }
    setWaveAnimating(playbackState == .playing && audioPlayer?.isPlaying == true)
  }

  private func setWaveAnimating(_ shouldAnimate: Bool) {
    for (index, bar) in waveBars.enumerated() {
      if shouldAnimate {
        guard bar.layer.animation(forKey: "soundWave") == nil else { continue }
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = 0.45
        animation.toValue = 1.0
        animation.duration = 0.28 + Double(index) * 0.08
        animation.autoreverses = true
        animation.repeatCount = .infinity
        bar.layer.add(animation, forKey: "soundWave")
      } else {
        bar.layer.removeAnimation(forKey: "soundWave")
      }
    }
  }

  @objc private func close() {
    finish(hasPlaybackStarted ? .completed(progress) : .cancelled(progress))
  }

  private func finish(_ result: CharacterReaderResult) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.finish(result)
      }
      return
    }
    guard completionGate.claim() else { return }
    isTerminal = true
    NotificationCenter.default.removeObserver(self)
    modelLoadCancellable?.cancel()
    modelLoadCancellable = nil
    displayLink?.invalidate()
    displayLink = nil
    setWaveAnimating(false)
    audioPlayer?.pause()
    deactivateOwnedAudioSession()
    arView.session.delegate = nil
    arView.session.pause()
    onComplete?(result)
    onComplete = nil
  }

  private func deactivateOwnedAudioSession() {
    guard ownsAudioSession else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
      ownsAudioSession = false
    } catch {
      // A later terminal or lifecycle cleanup will retry deactivation.
    }
  }

  @objc private func applicationWillResignActive() {
    isApplicationActive = false
    if playbackState == .playing {
      playbackState = .paused
    }
    audioPlayer?.pause()
    deactivateOwnedAudioSession()
    placementTap?.isEnabled = false
    displayLink?.isPaused = true
    arView.session.pause()
    renderPlaybackState()
  }

  @objc private func applicationDidBecomeActive() {
    isApplicationActive = true
    guard !isTerminal, let configuration else { return }
    activateARSession(configuration)
    displayLink?.isPaused = false
  }

  @objc private func audioSessionInterrupted(_ notification: Notification) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.audioSessionInterrupted(notification)
      }
      return
    }
    guard
      !isTerminal,
      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else {
      return
    }
    guard type == .began else { return }

    if playbackState.pauseForInterruption() {
      audioPlayer?.pause()
      guidanceLabel.text = "Reading paused"
      renderPlaybackState()
    }
    deactivateOwnedAudioSession()
    ownsAudioSession = false
  }
}

extension CharacterReaderViewController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal else { return }
      guard flag else {
        self.playbackState = .retry
        self.guidanceLabel.text = "Audio stopped - Tap Retry"
        self.deactivateOwnedAudioSession()
        self.renderPlaybackState()
        return
      }

      // A page's clips play back to back. Only when the last one ends is the page finished —
      // this is what keeps multi-segment curated pages from stopping after one sentence.
      let clips = self.pageIndex < self.pages.count
        ? self.pages[self.pageIndex].audioURLs.count
        : 0
      if self.clipIndex + 1 < clips {
        self.clipIndex += 1
        if self.loadCurrentClip(), self.startCurrentClip() { return }
        self.showPlaybackRetry()
        return
      }

      player.currentTime = 0
      self.playbackState = .ready
      self.guidanceLabel.text = self.storyMode && self.pageIndex < self.pages.count - 1
        ? "Page finished - Tap Next"
        : "Reading complete"
      self.deactivateOwnedAudioSession()
      self.renderPlaybackState()
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal else { return }
      self.showPlaybackRetry()
    }
  }
}

extension CharacterReaderViewController: ARSessionDelegate {
  func session(_ session: ARSession, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.finish(.failure(.arFailed))
    }
  }
}
