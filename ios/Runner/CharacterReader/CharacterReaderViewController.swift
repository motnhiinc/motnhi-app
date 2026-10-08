import ARKit
import AVFoundation
import Combine
import CoreText
import Flutter
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
  case scanNext(CharacterReaderProgress)
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
  private let scannedPageMode: Bool
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
  private let scanNextButton = UIButton(type: .system)
  private let pageLabel = UILabel()
  private let dockView = UIView()
  private let dockContentStack = UIStackView()
  private let dockTitleLabel = UILabel()
  private let placementStatusLabel = UILabel()
  private let headingStack = UIStackView()
  private let controlsStack = UIStackView()
  private let arBadge = UILabel()
  private let waveStack = UIStackView()
  private let waveBars = (0..<3).map { _ in UIView() }
  private let paperColor = UIColor(red: 1, green: 0.98, blue: 0.957, alpha: 1)
  private let inkColor = UIColor(red: 0.125, green: 0.102, blue: 0.094, alpha: 1)
  private let mutedColor = UIColor(red: 0.455, green: 0.42, blue: 0.4, alpha: 1)
  private let lineColor = UIColor(red: 0.859, green: 0.816, blue: 0.769, alpha: 1)
  private let coralColor = UIColor(red: 0.863, green: 0.439, blue: 0.294, alpha: 1)
  private let sageColor = UIColor(red: 0.231, green: 0.392, blue: 0.298, alpha: 1)
  private var guidanceText = "Preparing character reader" {
    didSet { if oldValue != guidanceText { renderGuidance() } }
  }
  private static var registeredFontNames: [String: String] = [:]
  private var dockLayoutKey: String?
  private var controlHeightConstraint: NSLayoutConstraint?
  private var previousWidthConstraint: NSLayoutConstraint?
  private var nextWidthConstraint: NSLayoutConstraint?
  private var dockBottomConstraint: NSLayoutConstraint?

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
  private var pageFinished = false

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
    scannedPageMode: Bool = false,
    onComplete: @escaping (CharacterReaderResult) -> Void
  ) {
    self.pages = pages
    self.storyMode = storyMode
    self.scannedPageMode = scannedPageMode && storyMode && pages.count == 1
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
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.setTitleColor(inkColor, for: .normal)
    closeButton.tintColor = inkColor
    closeButton.backgroundColor = paperColor
    closeButton.layer.cornerRadius = 26
    closeButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
    closeButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
    closeButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
    closeButton.titleLabel?.font = readerFont("NunitoSans-Bold", size: 16, style: .headline)
    closeButton.titleLabel?.adjustsFontForContentSizeCategory = true
    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    view.addSubview(closeButton)

    arBadge.translatesAutoresizingMaskIntoConstraints = false
    let badgeIcon = NSTextAttachment()
    badgeIcon.image = UIImage(systemName: "cube")?.withTintColor(paperColor, renderingMode: .alwaysOriginal)
    badgeIcon.bounds = CGRect(x: 0, y: -3, width: 18, height: 18)
    let badgeText = NSMutableAttributedString(string: "  ")
    badgeText.append(NSAttributedString(attachment: badgeIcon))
    badgeText.append(NSAttributedString(string: "  STORY IN AR  "))
    arBadge.attributedText = badgeText
    arBadge.textColor = paperColor
    arBadge.backgroundColor = inkColor.withAlphaComponent(0.85)
    arBadge.font = readerFont("NunitoSans-Bold", size: 14, style: .caption1)
    arBadge.textAlignment = .center
    arBadge.layer.cornerRadius = 22
    arBadge.layer.masksToBounds = true
    arBadge.isAccessibilityElement = false
    view.addSubview(arBadge)

    dockView.translatesAutoresizingMaskIntoConstraints = false
    dockView.backgroundColor = paperColor
    dockView.layer.cornerRadius = 24
    dockView.layer.cornerCurve = .continuous
    dockView.layer.borderWidth = 1
    dockView.layer.borderColor = lineColor.cgColor
    dockView.clipsToBounds = true
    view.addSubview(dockView)

    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsVerticalScrollIndicator = false
    dockView.addSubview(scrollView)

    let contentStack = dockContentStack
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 16
    contentStack.isLayoutMarginsRelativeArrangement = true
    contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    scrollView.addSubview(contentStack)

    placementStatusLabel.font = readerFont("NunitoSans-ExtraBold", size: 14, style: .caption1)
    placementStatusLabel.textColor = sageColor
    placementStatusLabel.numberOfLines = 0
    contentStack.addArrangedSubview(placementStatusLabel)

    dockTitleLabel.font = readerFont("SourceSerif4-SemiBold", size: 24, style: .title2)
    dockTitleLabel.textColor = inkColor
    dockTitleLabel.numberOfLines = 0
    dockTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    headingStack.axis = .horizontal
    headingStack.alignment = .center
    headingStack.spacing = 12
    headingStack.addArrangedSubview(dockTitleLabel)
    configurePageControls()
    headingStack.addArrangedSubview(pageLabel)
    contentStack.addArrangedSubview(headingStack)

    guidanceLabel.numberOfLines = 0
    guidanceLabel.textColor = mutedColor
    guidanceLabel.font = readerFont("NunitoSans-Regular", size: 16, style: .body)
    configureWaveBadge()
    let statusStack = UIStackView(arrangedSubviews: [waveStack, guidanceLabel])
    statusStack.axis = .horizontal
    statusStack.alignment = .center
    statusStack.spacing = 10
    contentStack.addArrangedSubview(statusStack)

    readButton.translatesAutoresizingMaskIntoConstraints = false
    readButton.setTitle("Read", for: .normal)
    readButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    readButton.setTitleColor(inkColor, for: .normal)
    readButton.tintColor = inkColor
    readButton.backgroundColor = coralColor
    readButton.layer.cornerRadius = 28
    readButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    readButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
    readButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
    readButton.titleLabel?.font = readerFont("NunitoSans-ExtraBold", size: 16, style: .headline)
    readButton.titleLabel?.adjustsFontForContentSizeCategory = true
    readButton.titleLabel?.numberOfLines = 0
    readButton.titleLabel?.textAlignment = .center
    readButton.isHidden = true
    readButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    controlsStack.axis = .horizontal
    controlsStack.alignment = .fill
    controlsStack.spacing = 12
    controlsStack.addArrangedSubview(previousButton)
    controlsStack.addArrangedSubview(readButton)
    controlsStack.addArrangedSubview(nextButton)
    controlsStack.isHidden = true
    contentStack.addArrangedSubview(controlsStack)

    if scannedPageMode {
      scanNextButton.setTitle(scanLabel("Scan next page", "Quét trang tiếp"), for: .normal)
      scanNextButton.setImage(UIImage(systemName: "doc.viewfinder"), for: .normal)
      scanNextButton.setTitleColor(inkColor, for: .normal)
      scanNextButton.tintColor = inkColor
      scanNextButton.titleLabel?.font = readerFont("NunitoSans-Bold", size: 16, style: .headline)
      scanNextButton.titleLabel?.adjustsFontForContentSizeCategory = true
      scanNextButton.titleLabel?.numberOfLines = 0
      scanNextButton.titleLabel?.textAlignment = .center
      scanNextButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
      scanNextButton.layer.cornerRadius = 26
      scanNextButton.layer.borderWidth = 1
      scanNextButton.layer.borderColor = lineColor.cgColor
      scanNextButton.addTarget(self, action: #selector(scanNext), for: .touchUpInside)
      contentStack.addArrangedSubview(scanNextButton)
      scanNextButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    for label in [guidanceLabel, dockTitleLabel, placementStatusLabel, pageLabel, arBadge] {
      label.adjustsFontForContentSizeCategory = true
      label.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
    }
    readButton.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
    let dockWidth = dockView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32)
    dockWidth.priority = .defaultHigh
    let scrollHeight = scrollView.heightAnchor.constraint(equalTo: contentStack.heightAnchor)
    scrollHeight.priority = .defaultHigh
    let readHeight = readButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
    let waveWidth = waveStack.widthAnchor.constraint(equalToConstant: 20)
    let previousWidth = previousButton.widthAnchor.constraint(equalToConstant: 52)
    let nextWidth = nextButton.widthAnchor.constraint(equalToConstant: 52)
    let dockBottom = dockView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
    controlHeightConstraint = readHeight
    previousWidthConstraint = previousWidth
    nextWidthConstraint = nextWidth
    dockBottomConstraint = dockBottom
    for constraint in [readHeight, waveWidth, previousWidth, nextWidth] {
      constraint.priority = UILayoutPriority(999)
    }

    NSLayoutConstraint.activate([
      arView.topAnchor.constraint(equalTo: view.topAnchor),
      arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
      arBadge.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      arBadge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      arBadge.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      dockView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      dockView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      dockView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      dockView.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
      dockWidth,
      dockBottom,
      dockView.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.65),
      scrollView.topAnchor.constraint(equalTo: dockView.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: dockView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: dockView.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: dockView.bottomAnchor),
      contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      scrollHeight,
      readHeight,
      waveWidth,
      waveStack.heightAnchor.constraint(equalToConstant: 24),
      previousWidth,
      nextWidth,
    ])
    updateAccessibleLayout()
    renderGuidance()

    let placementTap = UITapGestureRecognizer(target: self, action: #selector(placeCharacter))
    placementTap.isEnabled = false
    arView.addGestureRecognizer(placementTap)
    self.placementTap = placementTap
  }

  /// Page controls exist only in story mode; the scan-any-page flow has a single clip and no
  /// pages to move between, so they stay hidden and unreachable there.
  private func configurePageControls() {
    for (button, symbol, label, action) in [
      (previousButton, "chevron.left", "Previous page", #selector(goToPreviousPage)),
      (nextButton, "chevron.right", "Next page", #selector(goToNextPage)),
    ] {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.setImage(UIImage(systemName: symbol), for: .normal)
      button.tintColor = inkColor
      button.accessibilityLabel = label
      button.backgroundColor = paperColor
      button.layer.cornerRadius = 26
      button.layer.borderWidth = 1
      button.layer.borderColor = lineColor.cgColor
      button.isHidden = true
      button.addTarget(self, action: action, for: .touchUpInside)
    }

    pageLabel.translatesAutoresizingMaskIntoConstraints = false
    pageLabel.textAlignment = .right
    pageLabel.textColor = mutedColor
    pageLabel.font = readerFont("NunitoSans-Bold", size: 14, style: .subheadline)
    pageLabel.numberOfLines = 0
    pageLabel.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
    pageLabel.isHidden = true
  }

  private func configureWaveBadge() {
    waveStack.translatesAutoresizingMaskIntoConstraints = false
    waveStack.axis = .horizontal
    waveStack.alignment = .center
    waveStack.distribution = .fillEqually
    waveStack.spacing = 3
    waveStack.isHidden = true
    waveStack.isAccessibilityElement = false

    for (index, bar) in waveBars.enumerated() {
      bar.backgroundColor = sageColor
      bar.layer.cornerRadius = 2
      bar.translatesAutoresizingMaskIntoConstraints = false
      bar.heightAnchor.constraint(equalToConstant: index == 1 ? 18 : 10).isActive = true
      waveStack.addArrangedSubview(bar)
    }
  }

  private func readerFont(_ asset: String, size: CGFloat, style: UIFont.TextStyle) -> UIFont {
    if Self.registeredFontNames[asset] == nil {
      let key = FlutterDartProject.lookupKey(forAsset: "assets/fonts/\(asset).ttf")
      let framework = Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework")
      if let bundle = Bundle(url: framework),
         let url = bundle.url(forResource: key, withExtension: nil),
         let provider = CGDataProvider(url: url as CFURL),
         let font = CGFont(provider),
         let name = font.postScriptName as String?
      {
        CTFontManagerRegisterGraphicsFont(font, nil)
        Self.registeredFontNames[asset] = name
      }
    }
    let fallback = UIFont.systemFont(ofSize: size, weight: asset.contains("Bold") ? .bold : .regular)
    let font = Self.registeredFontNames[asset].flatMap { UIFont(name: $0, size: size) } ?? fallback
    return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateAccessibleLayout()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    closeButton.layer.cornerRadius = closeButton.bounds.height / 2
    readButton.layer.cornerRadius = readButton.bounds.height / 2
    updateDockLayout()
    updateAccessibleLayout()
  }

  private func updateAccessibleLayout() {
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    headingStack.axis = largeText ? .vertical : .horizontal
    headingStack.alignment = largeText ? .leading : .center
    arBadge.isHidden = largeText || closeButton.intrinsicContentSize.width + arBadge.intrinsicContentSize.width + 48
      > view.safeAreaLayoutGuide.layoutFrame.width
  }

  private func updateDockLayout() {
    let tablet = view.safeAreaLayoutGuide.layoutFrame.width >= 600
    let key = "\(tablet)-\(isPlaced)-\(traitCollection.preferredContentSizeCategory.rawValue)"
    guard key != dockLayoutKey else { return }
    dockLayoutKey = key
    let padding: CGFloat = tablet ? (isPlaced ? 24 : 28) : 20
    dockContentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: padding, leading: padding, bottom: padding, trailing: padding
    )
    dockContentStack.spacing = tablet ? (isPlaced ? 20 : 12) : 16
    dockView.layer.cornerRadius = tablet ? 28 : 24
    dockBottomConstraint?.constant = tablet ? -32 : -24
    controlsStack.spacing = tablet ? 16 : 12
    controlHeightConstraint?.constant = tablet ? 60 : 56
    previousWidthConstraint?.constant = tablet ? 60 : 52
    nextWidthConstraint?.constant = tablet ? 60 : 52
    previousButton.layer.cornerRadius = tablet ? 30 : 26
    nextButton.layer.cornerRadius = tablet ? 30 : 26
    dockTitleLabel.font = readerFont("SourceSerif4-SemiBold", size: tablet ? (isPlaced ? 28 : 32) : 24, style: .title2)
    pageLabel.font = readerFont("NunitoSans-Bold", size: tablet ? 16 : 14, style: .subheadline)
    guidanceLabel.font = readerFont("NunitoSans-Regular", size: tablet && !isPlaced ? 18 : 16, style: .body)
    readButton.titleLabel?.font = readerFont("NunitoSans-ExtraBold", size: tablet ? 18 : 16, style: .headline)
  }

  private func renderGuidance() {
    placementStatusLabel.isHidden = isPlaced
    dockTitleLabel.text = isPlaced ? "Story time" : "Find a spot for your story."
    guidanceLabel.textColor = isPlaced && playbackState == .playing ? sageColor : mutedColor
    guidanceLabel.text = playbackState == .paused && guidanceText == "Reading aloud" ? "Reading paused" : guidanceText
    if !isPlaced {
      switch guidanceText {
      case "Loading character":
        placementStatusLabel.text = "GETTING READY"
      case "Table found - Tap to place the character":
        placementStatusLabel.text = "TABLE FOUND"
        dockTitleLabel.text = "Make room for a little magic."
        guidanceLabel.text = scannedPageMode
          ? scanLabel("Hold still — placing your character.", "Giữ yên — đang đặt nhân vật.")
          : "Tap the table to place your character."
      case "Move the iPad slowly to find a table":
        placementStatusLabel.text = "LOOKING FOR A TABLE"
        guidanceLabel.text = scannedPageMode
          ? scanLabel("Keep the page in view. Move slowly to find its surface.", "Giữ trang sách trong khung hình. Di chuyển chậm để tìm mặt phẳng.")
          : "Move your device slowly to find a table."
      default:
        placementStatusLabel.text = "GETTING READY"
      }
    }
    updateDockLayout()
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
    guidanceText = "Loading character"
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
      guidanceText = "Character reader paused"
    }
  }

  private func activateARSession(_ configuration: ARWorldTrackingConfiguration) {
    arView.session.run(configuration)
    placementTap?.isEnabled = !isPlaced && !scannedPageMode
    if !isPlaced {
      guidanceText = "Move the iPad slowly to find a table"
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
    guard isApplicationActive else { return }
    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    let result = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal).first
      ?? (scannedPageMode ? nil : arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first)
    currentRaycastResult = result

    guard let result else {
      reticleEntity?.isEnabled = false
      guidanceText = "Move the iPad slowly to find a table"
      return
    }
    guidanceText = "Table found - Tap to place the character"
    let anchor = reticleAnchor ?? makeReticleAnchor()
    anchor.transform.matrix = result.worldTransform
    reticleEntity?.isEnabled = true
    if scannedPageMode, let frame = arView.session.currentFrame,
       case .normal = frame.camera.trackingState {
      placeCharacter()
    }
  }

  private func makeReticleAnchor() -> AnchorEntity {
    let anchor = AnchorEntity(world: matrix_identity_float4x4)
    let material = UnlitMaterial(color: paperColor)
    let reticle = ModelEntity()
    for index in 0..<24 {
      let angle = Float(index) * 2 * .pi / 24
      let dash = ModelEntity(mesh: .generatePlane(width: 0.008, depth: 0.002), materials: [material])
      dash.position = SIMD3(cos(angle) * 0.06, 0, sin(angle) * 0.06)
      dash.orientation = simd_quatf(angle: -angle - .pi / 2, axis: SIMD3(0, 1, 0))
      reticle.addChild(dash)
    }
    let crossSizes: [(Float, Float)] = [(0.024, 0.002), (0.002, 0.024)]
    for (width, depth) in crossSizes {
      reticle.addChild(ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [material]))
    }
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
    guidanceText = "Character ready"
    readButton.isHidden = false
    controlsStack.isHidden = false
    previousButton.isHidden = !storyMode || scannedPageMode
    nextButton.isHidden = !storyMode || scannedPageMode
    pageLabel.isHidden = !storyMode || scannedPageMode
    syncPageControls()
    renderPlaybackState()

    if !playFirstAnimation(in: model) {
      bobBaseY = model.position.y
      bobStartTime = CACurrentMediaTime()
    }
    if scannedPageMode, isApplicationActive, !startCurrentClip() {
      showPlaybackRetry()
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
    guard isPlaced else { return }
    if scannedPageMode && pageFinished {
      clipIndex = 0
      guard loadCurrentClip() else {
        showPlaybackRetry()
        return
      }
      pageFinished = false
    } else if scannedPageMode && playbackState == .retry {
      guard loadCurrentClip() else {
        showPlaybackRetry()
        return
      }
    }
    guard let audioPlayer else { return }
    if playbackState == .playing {
      audioPlayer.pause()
      playbackState = .paused
      guidanceText = "Reading paused"
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
      guidanceText = "Reading aloud"
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
      guidanceText = "Reading aloud"
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
      guidanceText = "Character ready"
      renderPlaybackState()
    }
  }

  private func syncPageControls() {
    guard storyMode else { return }
    pageLabel.text = "Page \(pageIndex + 1) of \(pages.count)"
    previousButton.isEnabled = pageIndex > 0
    nextButton.isEnabled = pageIndex < pages.count - 1
    previousButton.alpha = previousButton.isEnabled ? 1.0 : 0.35
    nextButton.alpha = nextButton.isEnabled ? 1.0 : 0.35
  }

  private func showPlaybackRetry() {
    audioPlayer?.pause()
    playbackState = .retry
    deactivateOwnedAudioSession()
    guidanceText = "Audio couldn't play - Tap Retry"
    renderPlaybackState()
  }

  private func renderPlaybackState() {
    switch playbackState {
    case .ready:
      readButton.setTitle(scannedPageMode && pageFinished ? scanLabel("Replay", "Đọc lại") : "Read", for: .normal)
      readButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    case .playing:
      readButton.setTitle("Pause", for: .normal)
      readButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
    case .paused:
      readButton.setTitle("Resume", for: .normal)
      readButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    case .retry:
      readButton.setTitle("Retry", for: .normal)
      readButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
    }
    waveStack.isHidden = playbackState != .playing
    renderGuidance()
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

  private func scanLabel(_ en: String, _ vi: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("vi") == true ? vi : en
  }

  @objc private func scanNext() {
    guard scannedPageMode else { return }
    finish(.scanNext(progress))
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
      guidanceText = "Reading paused"
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
        self.guidanceText = "Audio stopped - Tap Retry"
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
      self.pageFinished = true
      self.playbackState = .ready
      self.guidanceText = self.storyMode && self.pageIndex < self.pages.count - 1
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
