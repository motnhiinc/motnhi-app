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

enum CharacterReaderResult {
  case completed
  case cancelled
  case failure(CharacterReaderFailure)
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
  private let audioURL: URL
  private var onComplete: ((CharacterReaderResult) -> Void)?

  private let arView = ARView(frame: .zero)
  private let guidanceLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let readButton = UIButton(type: .system)
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

  init(audioURL: URL, onComplete: @escaping (CharacterReaderResult) -> Void) {
    self.audioURL = audioURL
    self.onComplete = onComplete
    super.init(nibName: nil, bundle: nil)
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
    finish(hasPlaybackStarted ? .completed : .cancelled)
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
    ])

    let placementTap = UITapGestureRecognizer(target: self, action: #selector(placeCharacter))
    placementTap.isEnabled = false
    arView.addGestureRecognizer(placementTap)
    self.placementTap = placementTap
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
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
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
    } catch {
      finish(.failure(.audioFailed))
      return
    }
    guard let modelURL = Bundle.main.url(forResource: "toy_drummer", withExtension: "usdz") else {
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
      guidanceLabel.text = "Reading aloud"
      renderPlaybackState()
    } catch {
      showPlaybackRetry()
    }
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
    finish(hasPlaybackStarted ? .completed : .cancelled)
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
      if flag {
        player.currentTime = 0
        self.playbackState = .ready
        self.guidanceLabel.text = "Reading complete"
      } else {
        self.playbackState = .retry
        self.guidanceLabel.text = "Audio stopped - Tap Retry"
      }
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
