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
  case listenWithoutAr(CharacterReaderProgress)
  case scanNextPage(CharacterReaderProgress)
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
  private var pages: [StoryReaderPage]
  private let automaticScanFlow: Bool
  private var automaticStartPending: Bool
  private var surfaceDwell = CharacterSurfaceDwell()
  private var placedAt: TimeInterval = 0
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
  private let playbackLabel = UILabel()
  private let preparationSpinner = UIActivityIndicatorView(style: .medium)
  private let placeButton = UIButton(type: .system)
  private let moveButton = UIButton(type: .system)
  private let cancelMoveButton = UIButton(type: .system)
  private let smallerButton = UIButton(type: .system)
  private let largerButton = UIButton(type: .system)
  private let turnLeftButton = UIButton(type: .system)
  private let turnRightButton = UIButton(type: .system)
  private let resetAdjustmentButton = UIButton(type: .system)
  private let listenWithoutArButton = UIButton(type: .system)
  private let moreButton = UIButton(type: .system)
  private var moreControls = false
  private var readingComplete = false
  private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(adjustScale(_:)))
  private lazy var yawGesture = UIRotationGestureRecognizer(target: self, action: #selector(adjustYaw(_:)))
  private var adjustment = CharacterAdjustment()
  private var pinchStartScale: Float?
  private var rotationStartYaw: Float?
  private let targetLabel = UILabel()
  private let waveStack = UIStackView()
  private let waveBars = (0..<3).map { _ in UIView() }

  private var configuration: ARWorldTrackingConfiguration?
  private var modelTemplate: Entity?
  private var modelLoadCancellable: AnyCancellable?
  private var audioPlayer: AVAudioPlayer?
  private var audioCompletion = CharacterAudioCompletionPolicy()
  private var displayLink: CADisplayLink?
  private var reticleAnchor: AnchorEntity?
  private var reticleEntity: ModelEntity?
  private let readyPreviewMaterial = SimpleMaterial(color: .systemGreen, isMetallic: false)
  private let provisionalPreviewMaterial = SimpleMaterial(color: .systemYellow, isMetallic: false)
  private var placedModel: Entity?
  private var animationOwner: Entity?
  private var idleAnimation: AnimationResource?
  private var idlePlayback: AnimationPlaybackController?
  private var nativeStart: TimeInterval = 0
  private var diagnosticEvents: Set<String> = []
  private var roomOcclusionConfigured = false
  private var peopleOcclusionConfigured = false
  private var committedAnchor: ARAnchor?
  private var committedEntity: AnchorEntity?
  private var placementState = CharacterPlacementState.searching
  private var trackingRecovery = CharacterTrackingRecovery()
  private var sessionInterrupted = false
  private var sessionFailed = false
  private var presentationState = CharacterPresentationState.idle
  private var playbackState = CharacterReaderPlaybackState.ready
  private var completionGate = OneShotGate()
  private var isPlaced: Bool { placementState.hasPlacement }
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
    modelAssetBaseName: String = "little_buddy",
    automaticScanFlow: Bool = false,
    onComplete: @escaping (CharacterReaderResult) -> Void
  ) {
    self.pages = pages
    self.automaticScanFlow = automaticScanFlow
    self.automaticStartPending = automaticScanFlow
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
    nativeStart = ProcessInfo.processInfo.systemUptime
    markDiagnostic("native_reader_loaded")
    markDiagnostic("rendered_camera_ready_unavailable")
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
    idlePlayback?.stop()
    deactivateOwnedAudioSession()
    arView.session.delegate = nil
    arView.session.pause()
  }

  func failPresentation() {
    finish(.failure(.arFailed))
  }

  func cancelPreparation() { finish(.cancelled(progress)) }

  func attachNarration(_ narration: [StoryReaderPage]) -> Bool {
    guard automaticScanFlow, !isTerminal, pages.isEmpty, !narration.isEmpty else { return false }
    pages = narration
    pageIndex = 0
    clipIndex = 0
    // The bridge may deliver while the presentation animation is still running.
    loadViewIfNeeded()
    guard loadCurrentClip() else { pages = []; return false }
    preparationSpinner.stopAnimating()
    playbackLabel.text = readerText("Character ready")
    markDiagnostic("approved_narration_attached")
    syncPageControls()
    updatePlacementControls()
    return true
  }

  private func configureView() {
    view.backgroundColor = .black

    arView.translatesAutoresizingMaskIntoConstraints = false
    arView.automaticallyConfigureSession = false
    view.addSubview(arView)
    for gesture in [pinchGesture, yawGesture] {
      gesture.delegate = self
      arView.addGestureRecognizer(gesture)
    }
    targetLabel.text = "+"
    targetLabel.textColor = .white
    targetLabel.font = .systemFont(ofSize: 32, weight: .light)
    targetLabel.isAccessibilityElement = false
    targetLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(targetLabel)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setTitle(readerText("Close"), for: .normal)
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
    guidanceLabel.text = readerText("Preparing character reader")
    view.addSubview(guidanceLabel)

    readButton.translatesAutoresizingMaskIntoConstraints = false
    readButton.setTitle(readerText("Read"), for: .normal)
    readButton.setTitleColor(.white, for: .normal)
    readButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    readButton.backgroundColor = .systemIndigo
    readButton.layer.cornerRadius = 14
    readButton.isHidden = true
    readButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    view.addSubview(readButton)

    configurePageControls()
    configureWaveBadge()

    for (button, title, action) in [
      (placeButton, "Place character", #selector(placeCharacter)),
      (moveButton, "Move character", #selector(beginMove)),
      (cancelMoveButton, "Cancel move", #selector(cancelMove)),
      (smallerButton, "Smaller character", #selector(makeSmaller)),
      (largerButton, "Larger character", #selector(makeLarger)),
      (turnLeftButton, "Turn character left", #selector(turnLeft)),
      (turnRightButton, "Turn character right", #selector(turnRight)),
      (resetAdjustmentButton, "Reset size and rotation", #selector(resetAdjustment)),
      (listenWithoutArButton, "Listen without AR", #selector(listenWithoutAr)),
      (moreButton, "More controls", #selector(toggleMoreControls)),
    ] {
      button.setTitle(readerText(title), for: .normal)
      button.setTitleColor(.white, for: .normal)
      button.backgroundColor = .systemIndigo
      button.layer.cornerRadius = 12
      button.addTarget(self, action: action, for: .touchUpInside)
    }
    moveButton.isHidden = true
    cancelMoveButton.isHidden = true
    placeButton.isHidden = true
    placeButton.isEnabled = false
    listenWithoutArButton.isHidden = !automaticScanFlow
    moreButton.isHidden = true
    if automaticScanFlow { playbackLabel.text = readerText("Getting your story ready") }
    preparationSpinner.color = .white
    preparationSpinner.hidesWhenStopped = true
    if automaticScanFlow && pages.isEmpty { preparationSpinner.startAnimating() }
    for button in adjustmentButtons {
      button.isHidden = true
      button.accessibilityHint = readerText("Adjusts in place without moving the character or restarting audio")
    }
    resetAdjustmentButton.accessibilityHint = readerText("Restores original size and placement-facing rotation; keeps position and audio")
    moveButton.accessibilityHint = readerText("Pinch to resize and twist with two fingers to turn, or use the adjustment buttons")

    playbackLabel.textColor = .white
    playbackLabel.textAlignment = .center
    playbackLabel.numberOfLines = 0
    playbackLabel.font = .preferredFont(forTextStyle: .subheadline)
    playbackLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    placeButton.accessibilityHint = readerText("Places on the confirmed surface at the center target")
    waveStack.isAccessibilityElement = true
    waveStack.accessibilityLabel = readerText("Speaking indicator")
    for label in [guidanceLabel, playbackLabel, pageLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.numberOfLines = 0
    }
    // A single flexible column remains reachable at accessibility sizes and in landscape.
    // Scrolling is preferable to clipping or shrinking the user's chosen type size.
    let controls = UIStackView(arrangedSubviews: [preparationSpinner, pageLabel, playbackLabel, waveStack,
      previousButton, readButton, nextButton, placeButton, moveButton, cancelMoveButton,
      listenWithoutArButton, moreButton] + adjustmentButtons)
    controls.axis = .vertical
    controls.alignment = .fill
    controls.spacing = 8
    controls.translatesAutoresizingMaskIntoConstraints = false
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(controls)
    view.addSubview(scroll)
    for button in [closeButton, readButton, previousButton, nextButton, placeButton,
                    moveButton, cancelMoveButton, listenWithoutArButton, moreButton] + adjustmentButtons {
      button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.textAlignment = .center
      button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
      let minimumHeight = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
      // Hidden arranged controls must be allowed to collapse to zero without a constraint fight.
      minimumHeight.priority = UILayoutPriority(999)
      minimumHeight.isActive = true
    }
    closeButton.accessibilityIdentifier = "reader.close"
    guidanceLabel.accessibilityIdentifier = "reader.guidance"
    readButton.accessibilityIdentifier = "reader.playback"
    previousButton.accessibilityIdentifier = "reader.previous"
    nextButton.accessibilityIdentifier = "reader.next"
    placeButton.accessibilityIdentifier = "reader.place"
    moveButton.accessibilityIdentifier = "reader.move"
    listenWithoutArButton.accessibilityIdentifier = "reader.listenWithoutAr"
    moreButton.accessibilityIdentifier = "reader.more"
    cancelMoveButton.accessibilityIdentifier = "reader.cancelMove"
    for (button, suffix) in zip(adjustmentButtons, ["smaller", "larger", "turnLeft", "turnRight", "resetAdjustment"]) {
      button.accessibilityIdentifier = "reader.\(suffix)"
    }
    scroll.accessibilityIdentifier = "reader.controls"

    NSLayoutConstraint.activate([
      arView.topAnchor.constraint(equalTo: view.topAnchor),
      arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      targetLabel.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
      targetLabel.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
      closeButton.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      guidanceLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),
      guidanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      guidanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      guidanceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
      guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      scroll.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      scroll.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
      scroll.topAnchor.constraint(greaterThanOrEqualTo: guidanceLabel.bottomAnchor, constant: 12),
      scroll.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.42),
      controls.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      controls.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      controls.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      controls.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      controls.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    let badgeHeight = waveStack.heightAnchor.constraint(equalToConstant: 40)
    badgeHeight.priority = UILayoutPriority(999)
    badgeHeight.isActive = true
    let preferredHeight = scroll.heightAnchor.constraint(equalTo: controls.heightAnchor)
    preferredHeight.priority = .defaultLow
    preferredHeight.isActive = true
  }

  /// Page controls exist only in story mode; the scan-any-page flow has a single clip and no
  /// pages to move between, so they stay hidden and unreachable there.
  private func configurePageControls() {
    for (button, title, action) in [
      (previousButton, "Back", #selector(goToPreviousPage)),
      (nextButton, "Next", #selector(goToNextPage)),
    ] {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.setTitle(readerText(title), for: .normal)
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
      bar.widthAnchor.constraint(equalToConstant: 6).isActive = true
      bar.heightAnchor.constraint(equalToConstant: index == 1 ? 22 : 14).isActive = true
      waveStack.addArrangedSubview(bar)
    }
    // Fixed icon slots keep the speaking badge small even when its row fills a tablet.
    let leading = UIView()
    let trailing = UIView()
    waveStack.insertArrangedSubview(leading, at: 0)
    waveStack.addArrangedSubview(trailing)
    waveStack.distribution = .fill
    leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive = true
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
    NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
  }

  private func startReader() {
    guard ARWorldTrackingConfiguration.isSupported else {
      finish(.failure(.arUnsupported))
      return
    }
    if !automaticScanFlow {
      guard loadCurrentClip() else {
        finish(.failure(.audioFailed))
        return
      }
      syncPageControls()
    }
    guard let modelURL = Bundle.main.url(forResource: modelAssetBaseName, withExtension: "usdz") else {
      finish(.failure(.modelMissing))
      return
    }
    guidanceLabel.text = readerText("Loading character")
    startARSession()
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
          self.markDiagnostic("model_ready")
          self.auditAnimations(on: entity)
          // Rebuild the discovery footprint with the loaded model's exact bounds.
          self.reticleAnchor?.removeFromParent()
          self.reticleAnchor = nil
          self.reticleEntity = nil
        }
      )
  }

  private func startARSession() {
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal]
    configuration.environmentTexturing = .automatic
    configureExperimentalOcclusion(configuration)
    self.configuration = configuration
    arView.session.delegate = self

    let displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = !isApplicationActive
    self.displayLink = displayLink
    if isApplicationActive {
      activateARSession(configuration)
    } else {
      guidanceLabel.text = readerText("Character reader paused")
    }
  }

  private func activateARSession(_ configuration: ARWorldTrackingConfiguration) {
    arView.session.run(configuration)
    sessionInterrupted = false
    sessionFailed = false
  }

  @objc private func updateFrame(_ displayLink: CADisplayLink) {
    guard !isTerminal else { return }
    if let frame = arView.session.currentFrame {
      markDiagnostic("first_session_frame_observed_not_rendered")
      if peopleOcclusionConfigured, !diagnosticEvents.contains("people_segmentation_depth_observed"),
         frame.segmentationBuffer != nil && frame.estimatedDepthData != nil {
        markDiagnostic("people_segmentation_depth_observed")
      }
      if #available(iOS 13.4, *), roomOcclusionConfigured,
         !diagnosticEvents.contains("scene_mesh_anchor_observed") {
        if frame.anchors.contains(where: { $0 is ARMeshAnchor }) {
          markDiagnostic("scene_mesh_anchor_observed")
        }
      }
      if !diagnosticEvents.contains("effective_running_configuration") {
        let running = arView.session.configuration as? ARWorldTrackingConfiguration
        var meshEffective = false
        if #available(iOS 13.4, *) { meshEffective = running?.sceneReconstruction == .mesh }
        markDiagnostic("effective_running_configuration", detail:
          "room_mesh=\(meshEffective) room_renderer=\(arView.environment.sceneUnderstanding.options.contains(.occlusion)) " +
          "people_semantics=\(running?.frameSemantics.contains(.personSegmentationWithDepth) == true) " +
          "people_renderer=\(!arView.renderOptions.contains(.disablePersonOcclusion)) environment_automatic=\(running?.environmentTexturing == .automatic) " +
          "grounding_shadows_disabled=\(arView.renderOptions.contains(.disableGroundingShadows))")
      }
    }
    updateTracking(at: displayLink.timestamp)
    if placementState.isPreviewing { updateRaycast() }
    if automaticStartPending, isApplicationActive, !isTerminal,
       placementState == .placed, normalTracking, committedEntity?.isAnchored == true,
       !trackingRecovery.requiresRecovery, audioPlayer != nil,
       ProcessInfo.processInfo.systemUptime - placedAt >= 0.35 {
      automaticStartPending = false
      markDiagnostic("automatic_narration_start")
      togglePlayback()
    }
  }

  private var normalTracking: Bool {
    guard isApplicationActive, !sessionInterrupted, !sessionFailed,
          let frame = arView.session.currentFrame,
          case .normal = frame.camera.trackingState else { return false }
    return true
  }

  private func targetHit() -> (ARRaycastResult?, CharacterPlacementEligibility) {
    guard normalTracking else { return (nil, .searching) }
    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    let geometryHit = arView.raycast(from: center, allowing: .existingPlaneGeometry,
      alignment: .horizontal).first
    let result = geometryHit ?? arView.raycast(from: center, allowing: .estimatedPlane,
      alignment: .horizontal).first
    let plane = result?.anchor as? ARPlaneAnchor
    var eligibility = CharacterPlacementEligibility.evaluate(normalTracking: normalTracking,
      hasHit: result != nil, trackedPlane: geometryHit != nil && plane?.alignment == .horizontal,
      upwardNormal: result?.worldTransform.columns.1.y ?? 0)
    if automaticScanFlow, let result, let plane, let frame = arView.session.currentFrame {
      let p = result.worldTransform.columns.3
      let camera = frame.camera.transform.columns.3
      let distance = simd_distance(SIMD3(p.x, p.y, p.z), SIMD3(camera.x, camera.y, camera.z))
      let local = simd_inverse(plane.transform) * p
      let margin: Float = 0.25 * adjustment.scale
      if distance < 0.25 || distance > 3 || (camera.y - p.y) / distance < 0.25 ||
         abs(local.x - plane.center.x) + margin > plane.extent.x / 2 ||
         abs(local.z - plane.center.z) + margin > plane.extent.z / 2 {
        eligibility = .searching
      }
    }
    return (result, eligibility)
  }

  private func updateRaycast() {
    let (result, eligibility) = targetHit()
    if eligibility == .ready { markDiagnostic("first_valid_center_placement") }
    placeButton.isHidden = modelTemplate == nil || (automaticScanFlow &&
      ProcessInfo.processInfo.systemUptime - nativeStart < 8 && placementState != .moving)
    placeButton.isEnabled = eligibility == .ready
    guard let result, eligibility != .searching else {
      surfaceDwell.reset()
      reticleEntity?.isEnabled = false
      guidanceLabel.text = readerText(normalTracking
        ? (automaticScanFlow ? "Find a spot for your reading buddy" : "Aim the center target at a horizontal surface")
        : trackingGuidance())
      return
    }
    guidanceLabel.text = readerText(eligibility == .ready
      ? (automaticScanFlow ? "Hold steady - Placing your buddy" : "Surface ready - Choose Place character")
      : "Surface estimated - Keep scanning to confirm")
    let anchor = reticleAnchor ?? makeReticleAnchor()
    let wasVisible = reticleEntity?.isEnabled == true
    var transform = presentationTransform(for: result)
    // Smooth provisional discovery only. Ready previews must exactly match the center hit,
    // rather than lag behind it and jump when the explicit placement action is consumed.
    if wasVisible && eligibility == .provisional {
      transform.columns.3 = anchor.transform.matrix.columns.3 * 0.7 + transform.columns.3 * 0.3
    }
    anchor.transform.matrix = transform
    reticleEntity?.model?.materials = [eligibility == .ready
      ? readyPreviewMaterial : provisionalPreviewMaterial]
    reticleEntity?.isEnabled = true
    if automaticScanFlow, modelTemplate != nil {
      let p = result.worldTransform.columns.3
      let stable = surfaceDwell.update(
        plane: eligibility == .ready ? result.anchor?.identifier : nil,
        position: SIMD3(p.x, p.y, p.z), at: ProcessInfo.processInfo.systemUptime)
      if stable { placeCharacter() }
    }
  }

  private func makeReticleAnchor() -> AnchorEntity {
    let anchor = AnchorEntity(world: matrix_identity_float4x4)
    let material = SimpleMaterial(color: UIColor.systemYellow.withAlphaComponent(0.85), isMetallic: false)
    let extents = modelTemplate?.visualBounds(relativeTo: modelTemplate).extents ?? SIMD3<Float>(repeating: 0)
    let largest = max(extents.x, extents.y, extents.z)
    let scale: Float = largest.isFinite && largest > 0 ? 0.35 / largest : 0.35
    let reticle = ModelEntity(
      mesh: .generatePlane(width: max(0.04, extents.x * scale),
                           depth: max(0.04, extents.z * scale), cornerRadius: 0.01),
      materials: [material]
    )
    reticle.position.y = 0.001
    anchor.addChild(reticle)
    arView.scene.addAnchor(anchor)
    reticleAnchor = anchor
    reticleEntity = reticle
    return anchor
  }

  private func presentationTransform(for result: ARRaycastResult) -> simd_float4x4 {
    let column = result.worldTransform.columns.3
    let camera = arView.cameraTransform.matrix.columns.3
    let yaw = CharacterAssetPresentation.viewerYaw(position: SIMD3(column.x, column.y, column.z),
      camera: SIMD3(camera.x, camera.y, camera.z))
    var transform = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
    transform.columns.3 = column
    return transform
  }

  @objc private func placeCharacter() {
    guard placementState.isPreviewing, let modelTemplate else { return }
    // Never consume a cached preview hit: both tracking and center geometry must still be valid.
    let (hit, eligibility) = targetHit()
    guard eligibility == .ready, let result = hit else { updateRaycast(); return }
    let trackedAnchor = ARAnchor(name: "reader-character", transform: presentationTransform(for: result))
    let anchor = AnchorEntity(anchor: trackedAnchor)

    // Reparent on Move instead of cloning: adjustments, held animation phase and authored
    // transforms survive confirmation. Cancel never touches this committed instance.
    let model: Entity
    if let placedModel {
      model = placedModel
    } else {
      model = Entity() // bottom-contact pivot, only user scale/yaw lives here
      let normalized = Entity()
      let authored = modelTemplate.clone(recursive: true)
      authored.stopAllAnimations(recursive: true)
      normalized.addChild(authored)
      scaleForTable(normalized)
      model.addChild(normalized)
      animationOwner = authored
    }
    anchor.addChild(model)
    arView.session.add(anchor: trackedAnchor)
    arView.scene.addAnchor(anchor)
    if let old = committedAnchor { arView.session.remove(anchor: old) }
    committedEntity?.removeFromParent()
    committedAnchor = trackedAnchor
    committedEntity = anchor
    placedModel = model
    placementState.confirm()
    surfaceDwell.reset()
    placedAt = ProcessInfo.processInfo.systemUptime
    if automaticScanFlow { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    applyAdjustment()
    markDiagnostic("first_confirmed_placement")
    reticleEntity?.isEnabled = false
    guidanceLabel.text = readerText("Character ready")
    updatePlacementControls()
    syncPageControls()
    renderPlaybackState()
  }

  private func updatePlacementControls() {
    let previewing = placementState.isPreviewing
    targetLabel.isHidden = !previewing
    placeButton.isHidden = !previewing || (automaticScanFlow && placementState != .moving &&
      ProcessInfo.processInfo.systemUptime - nativeStart < 8)
    cancelMoveButton.isHidden = placementState != .moving
    moveButton.isHidden = !isPlaced || previewing
    readButton.isHidden = automaticScanFlow && (audioPlayer == nil || !isPlaced)
    moreButton.isHidden = !automaticScanFlow || previewing
    listenWithoutArButton.isHidden = !automaticScanFlow || (isPlaced && !moreControls)
    waveStack.isHidden = false
    previousButton.isHidden = !storyMode || automaticScanFlow
    nextButton.isHidden = automaticScanFlow ? !readingComplete : !storyMode
    pageLabel.isHidden = !storyMode || automaticScanFlow
    readButton.isEnabled = !previewing && !trackingRecovery.requiresRecovery
    previousButton.isEnabled = !previewing && pageIndex > 0
    nextButton.isEnabled = !previewing && (automaticScanFlow ? readingComplete : pageIndex < pages.count - 1)
    updateAdjustmentControls()
  }

  @objc private func beginMove() {
    guard placementState == .placed else { return }
    placementState.beginMove()
    automaticStartPending = false
    surfaceDwell.reset()
    pausePreservingPlayback()
    if sessionFailed, let configuration { activateARSession(configuration) }
    updatePlacementControls()
    updateRaycast()
  }

  @objc private func cancelMove() {
    guard placementState == .moving else { return }
    placementState.cancelMove()
    reticleEntity?.isEnabled = false
    updatePlacementControls()
    guidanceLabel.text = readerText("Character ready")
    updateAnimationPlayback()
  }

  private var adjustmentButtons: [UIButton] {
    [smallerButton, largerButton, turnLeftButton, turnRightButton, resetAdjustmentButton]
  }

  @objc private func toggleMoreControls() {
    moreControls.toggle()
    moreButton.setTitle(readerText(moreControls ? "Hide controls" : "More controls"), for: .normal)
    updatePlacementControls()
  }

  private var canAdjust: Bool {
    CharacterAdjustment.canAdjust(placement: placementState,
      healthy: normalTracking && committedEntity?.isAnchored == true,
      recovering: trackingRecovery.requiresRecovery, active: isApplicationActive, terminal: isTerminal)
  }

  private func updateAdjustmentControls() {
    let enabled = canAdjust
    for button in adjustmentButtons {
      let hidden = placementState != .placed || (automaticScanFlow && !moreControls)
      if button.isHidden != hidden { button.isHidden = hidden }
      let buttonEnabled = enabled &&
        (button !== smallerButton || adjustment.scale > CharacterAdjustment.scaleRange.lowerBound) &&
        (button !== largerButton || adjustment.scale < CharacterAdjustment.scaleRange.upperBound)
      if button.isEnabled != buttonEnabled { button.isEnabled = buttonEnabled }
    }
    for gesture in [pinchGesture, yawGesture] where gesture.isEnabled != enabled { gesture.isEnabled = enabled }
  }

  private func applyAdjustment() {
    placedModel?.scale = SIMD3(repeating: adjustment.scale)
    placedModel?.orientation = simd_quatf(angle: adjustment.yaw +
      (CharacterAssetPresentation.auditedForwardAxisOffset(asset: modelAssetBaseName) ?? 0), axis: SIMD3(0, 1, 0))
    // Preview footprint reflects the retained user adjustment, not the default size.
    reticleEntity?.scale = SIMD3(repeating: adjustment.scale)
    reticleEntity?.orientation = simd_quatf(angle: adjustment.yaw, axis: SIMD3(0, 1, 0))
    let value = String(format: readerText("Size %ld percent, rotation %ld degrees"),
      Int((adjustment.scale * 100).rounded()), Int((adjustment.yaw * 180 / .pi).rounded()))
    for button in adjustmentButtons { button.accessibilityValue = value }
    updateAdjustmentControls()
  }

  @objc private func makeSmaller() {
    guard canAdjust else { return }
    adjustment.setScale(adjustment.scale - 0.1)
    applyAdjustment()
  }

  @objc private func makeLarger() {
    guard canAdjust else { return }
    adjustment.setScale(adjustment.scale + 0.1)
    applyAdjustment()
  }

  @objc private func turnLeft() { turn(by: .pi / 12) }
  @objc private func turnRight() { turn(by: -.pi / 12) }

  private func turn(by radians: Float) {
    guard canAdjust else { return }
    adjustment.setYaw(adjustment.yaw + radians)
    applyAdjustment()
  }

  @objc private func resetAdjustment() {
    guard canAdjust else { return }
    pinchGesture.isEnabled = false
    yawGesture.isEnabled = false
    adjustment.reset()
    applyAdjustment()
  }

  @objc private func reduceMotionChanged() {
    guard !isTerminal else { return }
    renderPlaybackState()
  }

  @objc private func adjustScale(_ gesture: UIPinchGestureRecognizer) {
    if gesture.state == .cancelled || gesture.state == .failed {
      guard let start = pinchStartScale else { return }
      pinchStartScale = nil
      adjustment.setScale(start)
      applyAdjustment()
      return
    }
    guard canAdjust else { return }
    if gesture.state == .began { pinchStartScale = adjustment.scale }
    if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
      adjustment.setScale(adjustment.scale * Float(gesture.scale))
      gesture.scale = 1 // Incremental deltas allow immediate reversal at a bound.
      applyAdjustment()
      if gesture.state == .ended { pinchStartScale = nil }
    }
  }

  @objc private func adjustYaw(_ gesture: UIRotationGestureRecognizer) {
    if gesture.state == .cancelled || gesture.state == .failed {
      guard let start = rotationStartYaw else { return }
      rotationStartYaw = nil
      adjustment.setYaw(start)
      applyAdjustment()
      return
    }
    guard canAdjust else { return }
    if gesture.state == .began { rotationStartYaw = adjustment.yaw }
    if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
      // Screen twist rotates about the surface's vertical +Y axis, never pitches/rolls.
      adjustment.setYaw(adjustment.yaw - Float(gesture.rotation))
      gesture.rotation = 0
      applyAdjustment()
      if gesture.state == .ended { rotationStartYaw = nil }
    }
  }

  private func auditAnimations(on root: Entity) {
    // Enumerate owners as well as names: generated child aliases are NOT distinct clips.
    func enumerate(_ entity: Entity, path: [String]) {
      let owner = path + [entity.name]
      #if DEBUG
      for animation in entity.availableAnimations {
        NSLog("[CharacterReader] animation asset=%@ owner=%@ name=%@", modelAssetBaseName,
          owner.joined(separator: "/"), animation.name ?? "<unnamed>")
      }
      #endif
      for child in entity.children { enumerate(child, path: owner) }
    }
    enumerate(root, path: [])
    guard #available(iOS 15.0, *) else {
      markDiagnostic("animation_stable_fallback", detail: "duration validation requires iOS 15")
      return
    }
    let matches = root.availableAnimations.filter {
      $0.name == CharacterAssetPresentation.clipName(asset: modelAssetBaseName, state: .idle)
    }
    guard matches.count == 1, let candidate = matches.first else {
      markDiagnostic("animation_stable_fallback", detail: "root contract missing or ambiguous")
      return
    }
    // Duration is exposed by the controller on iOS 15; inspect paused, before attachment.
    let probe = root.playAnimation(candidate, startsPaused: true)
    let duration = probe.duration
    probe.stop()
    guard CharacterAssetPresentation.validatesIdle(asset: modelAssetBaseName,
      ownerPath: [root.name], name: candidate.name, duration: duration) else {
      markDiagnostic("animation_stable_fallback", detail: "owner/name/duration mismatch")
      return
    }
    idleAnimation = candidate
    markDiagnostic("animation_idle_contract_validated", detail:
      "asset=\(modelAssetBaseName) owner=<loaded-root> name=\(candidate.name ?? "") duration=\(duration) visual_unverified=true")
  }

  private func updateAnimationPlayback() {
    guard #available(iOS 15.0, *) else { return } // Older OS: stable pose, never guess a clip.
    let shouldPlay = CharacterAnimationPolicy.shouldPlay(state: presentationState,
      placement: placementState, active: isApplicationActive, interrupted: sessionInterrupted,
      failed: sessionFailed, recovering: trackingRecovery.requiresRecovery) && !UIAccessibility.isReduceMotionEnabled
    guard shouldPlay, let animationOwner, let idleAnimation else {
      idlePlayback?.pause() // Hold the authored pose; do not reset at Pause/Move/lifecycle loss.
      return
    }
    if let idlePlayback {
      if !idlePlayback.isPlaying { idlePlayback.resume() }
    } else {
      idlePlayback = animationOwner.playAnimation(idleAnimation.repeat(), transitionDuration: 0.2)
    }
    // Idle and speaking share the validated Idle-like loop. No talking/facial clip exists.
    // Page/audio/state changes never start another controller or reset its timeline.
  }

  private func markDiagnostic(_ event: String, detail: String = "") {
    guard diagnosticEvents.insert(event).inserted else { return }
    let elapsed = (ProcessInfo.processInfo.systemUptime - nativeStart) * 1000
    NSLog("[CharacterReader] %@ elapsed_ms=%.1f %@", event, elapsed, detail)
  }

  private func configureExperimentalOcclusion(_ configuration: ARWorldTrackingConfiguration) {
    var requestRoom = false
    var requestPeople = false
    #if DEBUG
    requestRoom = ProcessInfo.processInfo.arguments.contains("--reader-experimental-scene-occlusion")
    requestPeople = ProcessInfo.processInfo.arguments.contains("--reader-experimental-people-occlusion")
    #endif
    var roomAPI = false
    var roomSupport = false
    if #available(iOS 13.4, *) {
      roomAPI = true
      roomSupport = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
      roomOcclusionConfigured = CharacterExperimentalCapability(apiAvailable: roomAPI,
        supported: roomSupport, requested: requestRoom).configured
      configuration.sceneReconstruction = roomOcclusionConfigured ? .mesh : []
      if roomOcclusionConfigured { arView.environment.sceneUnderstanding.options.insert(.occlusion) }
      else { arView.environment.sceneUnderstanding.options.remove(.occlusion) }
    }
    let peopleSupport = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
    peopleOcclusionConfigured = CharacterExperimentalCapability(apiAvailable: true,
      supported: peopleSupport, requested: requestPeople).configured
    if peopleOcclusionConfigured {
      configuration.frameSemantics.insert(.personSegmentationWithDepth)
      arView.renderOptions.remove(.disablePersonOcclusion)
    } else {
      configuration.frameSemantics.remove(.personSegmentationWithDepth)
      arView.renderOptions.insert(.disablePersonOcclusion)
    }
    // Independent experiments, OFF in release/default launches. Support/configuration does
    // not establish useful depth, people/hand quality, rendered occlusion or performance.
    markDiagnostic("occlusion_capabilities", detail:
      "room_api=\(roomAPI) room_supported=\(roomSupport) room_requested=\(requestRoom) room_configured=\(roomOcclusionConfigured) " +
      "people_api=true people_supported=\(peopleSupport) people_requested=\(requestPeople) people_configured=\(peopleOcclusionConfigured) experimental_visual_unverified=true")
  }

  private func scaleForTable(_ model: Entity) {
    let bounds = model.visualBounds(relativeTo: model)
    guard let normalization = CharacterModelNormalization(minimum: bounds.min, maximum: bounds.max) else { return }
    model.scale = SIMD3(repeating: normalization.scale)
    model.position = normalization.translation
  }

  private func pausePreservingPlayback() {
    _ = playbackState.pauseForInterruption()
    audioPlayer?.pause()
    deactivateOwnedAudioSession()
    renderPlaybackState()
  }

  private func trackingGuidance() -> String {
    if sessionFailed { return "Tracking unavailable - Try Move character" }
    if sessionInterrupted { return "Session interrupted - Return to the placement area" }
    guard let state = arView.session.currentFrame?.camera.trackingState else {
      return "Move the device slowly to scan a surface"
    }
    switch state {
    case .normal: return "Point back toward the placement area or choose Move character"
    case .notAvailable: return "Tracking unavailable - Return to the placement area"
    case .limited(let reason):
      switch reason {
      case .excessiveMotion: return "Move the device more slowly"
      case .insufficientFeatures: return "Improve lighting and aim at a textured surface"
      case .relocalizing: return "Point back toward the placement area"
      case .initializing: return "Move the device slowly to scan a surface"
      @unknown default: return "Point back toward the placement area"
      }
    }
  }

  private func updateTracking(at time: TimeInterval) {
    let healthy = normalTracking && (!isPlaced || committedEntity?.isAnchored == true)
    let previouslyRecovering = trackingRecovery.requiresRecovery
    let needsRecovery = trackingRecovery.update(healthy: healthy, at: time)
    updateAdjustmentControls()
    if previouslyRecovering != needsRecovery { updateAnimationPlayback() }
    guard isPlaced else { return }
    if needsRecovery {
      if playbackState == .playing { pausePreservingPlayback() }
      guidanceLabel.text = readerText(trackingGuidance())
    } else if healthy && !placementState.isPreviewing {
      guidanceLabel.text = readerText("Character ready")
    }
    readButton.isEnabled = placementState == .placed &&
      (playbackState == .playing || (healthy && !needsRecovery))
  }

  @objc private func togglePlayback() {
    automaticStartPending = false
    guard placementState == .placed else { return }
    // Pause remains usable during the debounce window even if camera tracking just degraded.
    if playbackState == .playing {
      pausePreservingPlayback()
      return
    }
    guard normalTracking, !trackingRecovery.requiresRecovery else { return }
    if playbackState == .retry, !loadCurrentClip() {
      showPlaybackRetry()
      return
    }
    guard let audioPlayer else { return }
    readingComplete = false
    updatePlacementControls()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      ownsAudioSession = true
      try session.setActive(true)
      guard audioPlayer.play() else {
        showPlaybackRetry()
        return
      }
      audioCompletion.started()
      hasPlaybackStarted = true
      playbackState = .playing
      markCurrentPageRead()
      playbackLabel.text = readerText("Reading aloud")
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
    audioCompletion.invalidate()
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
    guard placementState == .placed, normalTracking,
          !trackingRecovery.requiresRecovery, let audioPlayer else { return false }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      ownsAudioSession = true
      try session.setActive(true)
      guard audioPlayer.play() else { return false }
      audioCompletion.started()
      hasPlaybackStarted = true
      playbackState = .playing
      markCurrentPageRead()
      playbackLabel.text = readerText("Reading aloud")
      renderPlaybackState()
      return true
    } catch {
      return false
    }
  }

  /// Moves between pages without touching the AR session or the placed anchor: only the audio
  /// changes, which is what lets the character stay exactly where the child put it.
  @objc private func goToPreviousPage() { goToPage(by: -1) }

  @objc private func goToNextPage() {
    if automaticScanFlow { finish(.scanNextPage(progress)) }
    else { goToPage(by: 1) }
  }

  private func goToPage(by delta: Int) {
    guard storyMode, placementState == .placed else { return }
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
      playbackLabel.text = readerText("Character ready")
      renderPlaybackState()
    }
  }

  private func syncPageControls() {
    guard storyMode else { return }
    if automaticScanFlow {
      nextButton.isEnabled = placementState == .placed && readingComplete
      return
    }
    pageLabel.text = String(format: readerText("Page %ld of %ld"), pageIndex + 1, pages.count)
    previousButton.isEnabled = placementState == .placed && pageIndex > 0
    nextButton.isEnabled = placementState == .placed && pageIndex < pages.count - 1
    previousButton.alpha = previousButton.isEnabled ? 1.0 : 0.35
    nextButton.alpha = nextButton.isEnabled ? 1.0 : 0.35
  }

  private func showPlaybackRetry() {
    audioCompletion.invalidate()
    audioPlayer?.pause()
    playbackState = .retry
    deactivateOwnedAudioSession()
    playbackLabel.text = readerText("Audio couldn't play - Tap Retry")
    renderPlaybackState()
  }

  private func renderPlaybackState() {
    switch playbackState {
    case .ready:
      readButton.setTitle(readerText(automaticScanFlow && readingComplete ? "Read again" : "Read"), for: .normal)
    case .playing:
      readButton.setTitle(readerText("Pause"), for: .normal)
    case .paused:
      readButton.setTitle(readerText("Resume"), for: .normal)
      playbackLabel.text = readerText("Reading paused")
    case .retry:
      readButton.setTitle(readerText("Retry"), for: .normal)
    }
    let state = CharacterPresentationState.resolve(playback: playbackState,
      audioIsPlaying: audioPlayer?.isPlaying == true)
    presentationState = state
    updateAnimationPlayback()
    waveStack.accessibilityValue = readerText(state == .speaking ? "Reading aloud" : "Reading paused")
    setWaveAnimating(state == .speaking && !UIAccessibility.isReduceMotionEnabled)
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

  @objc private func listenWithoutAr() { finish(.listenWithoutAr(progress)) }

  private func finish(_ result: CharacterReaderResult) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.finish(result)
      }
      return
    }
    guard completionGate.claim() else { return }
    isTerminal = true
    audioCompletion.invalidate()
    idlePlayback?.stop()
    idlePlayback = nil
    animationOwner = nil
    idleAnimation = nil
    pinchGesture.isEnabled = false
    yawGesture.isEnabled = false
    adjustment.reset()
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
    if let committedAnchor { arView.session.remove(anchor: committedAnchor) }
    committedEntity?.removeFromParent()
    reticleAnchor?.removeFromParent()
    committedAnchor = nil
    committedEntity = nil
    reticleAnchor = nil
    reticleEntity = nil
    placedModel = nil
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
    automaticStartPending = false
    surfaceDwell.reset()
    if playbackState == .playing {
      playbackState = .paused
    }
    audioPlayer?.pause()
    deactivateOwnedAudioSession()
    placeButton.isEnabled = false
    displayLink?.isPaused = true
    arView.session.pause()
    renderPlaybackState()
    updateAdjustmentControls()
  }

  @objc private func applicationDidBecomeActive() {
    isApplicationActive = true
    guard !isTerminal, let configuration else { return }
    activateARSession(configuration)
    displayLink?.isPaused = false
    updateAnimationPlayback()
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
    automaticStartPending = false

    if playbackState.pauseForInterruption() {
      audioPlayer?.pause()
      playbackLabel.text = readerText("Reading paused")
      renderPlaybackState()
    }
    deactivateOwnedAudioSession()
    ownsAudioSession = false
  }
}

extension CharacterReaderViewController: UIGestureRecognizerDelegate {
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { canAdjust }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    // Recognizers live only on the AR view, not the overlay/scroll view. Reject every
    // non-scene/control touch explicitly; no tap recognizer can consume placement actions.
    guard canAdjust, let touched = touch.view else { return false }
    return (touched === arView || touched.isDescendant(of: arView)) && !(touched is UIControl)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    (gestureRecognizer === pinchGesture && other === yawGesture) ||
      (gestureRecognizer === yawGesture && other === pinchGesture)
  }
}

extension CharacterReaderViewController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let callbackCycle = audioCompletion.cycle
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal, player === self.audioPlayer else { return }
      switch self.audioCompletion.consume(cycle: callbackCycle, successfully: flag) {
      case .ignored: return
      case .failed:
        self.playbackState = .retry
        self.playbackLabel.text = readerText("Audio stopped - Tap Retry")
        self.deactivateOwnedAudioSession()
        self.renderPlaybackState()
        return
      case .completed: break
      }

      // A page's clips play back to back. Only when the last one ends is the page finished —
      // this is what keeps multi-segment curated pages from stopping after one sentence.
      let clips = self.pageIndex < self.pages.count
        ? self.pages[self.pageIndex].audioURLs.count
        : 0
      if self.clipIndex + 1 < clips {
        let autostart = CharacterAudioCompletionPolicy.canAutostart(playback: self.playbackState,
          placement: self.placementState, active: self.isApplicationActive,
          healthy: self.normalTracking, recovering: self.trackingRecovery.requiresRecovery)
        self.clipIndex += 1
        if self.loadCurrentClip() {
          guard autostart else {
            self.playbackState = .paused
            self.pausePreservingPlayback()
            return
          }
          if self.startCurrentClip() { return }
        }
        self.showPlaybackRetry()
        return
      }

      player.currentTime = 0
      // Read again starts the whole page, not just its last narration segment.
      if self.clipIndex != 0 {
        self.clipIndex = 0
        guard self.loadCurrentClip() else { self.showPlaybackRetry(); return }
      }
      self.playbackState = .ready
      self.readingComplete = true
      if self.automaticScanFlow {
        self.nextButton.setTitle(readerText("Scan next page"), for: .normal)
        self.updatePlacementControls()
      }
      self.playbackLabel.text = readerText(self.storyMode && self.pageIndex < self.pages.count - 1
        ? "Page finished - Tap Next"
        : "Reading complete")
      self.deactivateOwnedAudioSession()
      self.renderPlaybackState()
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal, player === self.audioPlayer else { return }
      self.showPlaybackRetry()
    }
  }
}

extension CharacterReaderViewController: ARSessionDelegate {
  func session(_ session: ARSession, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal else { return }
      guard self.isPlaced else {
        self.finish(.failure(.arFailed))
        return
      }
      self.sessionFailed = true
      self.placeButton.isEnabled = false
      self.pausePreservingPlayback()
      self.guidanceLabel.text = readerText(self.trackingGuidance())
    }
  }

  func sessionWasInterrupted(_ session: ARSession) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal else { return }
      self.sessionInterrupted = true
      self.placeButton.isEnabled = false
      self.pausePreservingPlayback()
      self.guidanceLabel.text = readerText(self.trackingGuidance())
    }
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isTerminal else { return }
      self.sessionInterrupted = false
      // Keep existing anchors and progress; never reset tracking or automatically resume audio.
      if self.isApplicationActive, let configuration = self.configuration {
        self.arView.session.run(configuration)
      }
      self.updateAnimationPlayback() // Idle may recover; paused narration never auto-resumes.
    }
  }
}
