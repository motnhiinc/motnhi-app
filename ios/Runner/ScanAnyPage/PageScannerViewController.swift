import AVFoundation
import CoreImage
import UIKit
import Vision

enum PageScannerFailure: String, Error {
  case cameraDenied = "camera_denied"
  case cameraUnavailable = "camera_unavailable"
  case captureFailed = "capture_failed"
  case correctionFailed = "correction_failed"
  case ocrFailed = "ocr_failed"
  case noText = "no_text"
  case cancelled
}

final class PageScannerViewController: UIViewController {
  var onComplete: ((Result<String, PageScannerFailure>) -> Void)?

  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let photoOutput = AVCapturePhotoOutput()
  private let scannerQueue = DispatchQueue(label: "storybook_ar.scan.session")
  private let ciContext = CIContext()
  private let rectangleLayer = CAShapeLayer()
  private let guidanceLabel = UILabel()
  private let statusLabel = UILabel()
  private let cancelButton = UIButton(type: .system)

  private var previewLayer: AVCaptureVideoPreviewLayer!
  private var cameraDevice: AVCaptureDevice?
  private var stabilityTracker = RectangleStabilityTracker(
    requiredStableFrames: 5,
    tolerance: 0.02,
    minimumArea: 0.35
  )
  private var lastProcessedTime = CMTime.invalid
  private var lifecycle = ScannerLifecycleState<Result<String, PageScannerFailure>>()
  private var currentCaptureOrientation: AVCaptureVideoOrientation?

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureSessionRuntimeError),
      name: .AVCaptureSessionRuntimeError,
      object: captureSession
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureSessionWasInterrupted),
      name: .AVCaptureSessionWasInterrupted,
      object: captureSession
    )
    requestCameraAccess()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
    rectangleLayer.frame = view.bounds
    let orientation = captureVideoOrientation
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = orientation
    }
    updateConnections(for: orientation)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    complete(.failure(.cancelled))
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureView() {
    view.backgroundColor = .black

    previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    rectangleLayer.fillColor = UIColor.clear.cgColor
    rectangleLayer.strokeColor = UIColor.systemYellow.cgColor
    rectangleLayer.lineWidth = 4
    rectangleLayer.lineJoin = .round
    view.layer.addSublayer(rectangleLayer)

    guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
    guidanceLabel.numberOfLines = 0
    guidanceLabel.textAlignment = .center
    guidanceLabel.textColor = .white
    guidanceLabel.font = .preferredFont(forTextStyle: .headline)
    guidanceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    guidanceLabel.layer.cornerRadius = 12
    guidanceLabel.layer.masksToBounds = true
    guidanceLabel.text = "Hold over one page\nEnglish, Vietnamese, or both · Keep all corners visible"
    view.addSubview(guidanceLabel)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.textAlignment = .center
    statusLabel.textColor = .white
    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    statusLabel.layer.cornerRadius = 10
    statusLabel.layer.masksToBounds = true
    statusLabel.text = "Keep the page flat and well lit"
    view.addSubview(statusLabel)

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.setTitleColor(.white, for: .normal)
    cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    cancelButton.layer.cornerRadius = 12
    cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    view.addSubview(cancelButton)

    NSLayoutConstraint.activate([
      cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
      cancelButton.heightAnchor.constraint(equalToConstant: 48),
      guidanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      guidanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 16),
      guidanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      guidanceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
      guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
      statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
      statusLabel.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  private func requestCameraAccess() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureCaptureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        if granted {
          self.configureCaptureSession()
        } else {
          self.complete(.failure(.cameraDenied))
        }
      }
    case .denied, .restricted:
      complete(.failure(.cameraDenied))
    @unknown default:
      complete(.failure(.cameraDenied))
    }
  }

  private func configureCaptureSession() {
    scannerQueue.async { [weak self] in
      guard let self, !self.lifecycle.isTerminal else { return }

      guard let camera = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
      ) else {
        self.complete(.failure(.cameraUnavailable))
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: camera)
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .photo
        guard self.captureSession.canAddInput(input) else {
          self.captureSession.commitConfiguration()
          self.complete(.failure(.cameraUnavailable))
          return
        }
        self.captureSession.addInput(input)

        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.videoOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        self.videoOutput.setSampleBufferDelegate(self, queue: self.scannerQueue)
        guard self.captureSession.canAddOutput(self.videoOutput) else {
          self.captureSession.commitConfiguration()
          self.complete(.failure(.cameraUnavailable))
          return
        }
        self.captureSession.addOutput(self.videoOutput)

        guard self.captureSession.canAddOutput(self.photoOutput) else {
          self.captureSession.commitConfiguration()
          self.complete(.failure(.cameraUnavailable))
          return
        }
        self.captureSession.addOutput(self.photoOutput)
        self.cameraDevice = camera
        self.captureSession.commitConfiguration()

        self.applyCurrentOrientation()
        self.captureSession.startRunning()
      } catch {
        self.complete(.failure(.cameraUnavailable))
      }
    }
  }

  private func updateConnections(for orientation: AVCaptureVideoOrientation) {
    scannerQueue.async { [weak self] in
      guard let self, !self.lifecycle.isTerminal else { return }
      let orientationChanged = orientation != self.currentCaptureOrientation
      self.currentCaptureOrientation = orientation
      self.applyCurrentOrientation()
      if orientationChanged {
        self.stabilityTracker.reset()
        self.lastProcessedTime = .invalid
      }
    }
  }

  private func applyCurrentOrientation() {
    guard let orientation = currentCaptureOrientation else { return }
    if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = orientation
    }
    if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = orientation
    }
  }

  private var captureVideoOrientation: AVCaptureVideoOrientation {
    switch view.window?.windowScene?.interfaceOrientation {
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    case .portraitUpsideDown:
      return .portraitUpsideDown
    default:
      return .portrait
    }
  }

  private func detectRectangle(in pixelBuffer: CVPixelBuffer) {
    let request = VNDetectRectanglesRequest { [weak self] request, error in
      guard let self else { return }
      guard error == nil else {
        self.stabilityTracker.reset()
        self.showRectangle(nil)
        return
      }

      guard let observation = request.results?.first as? VNRectangleObservation else {
        self.stabilityTracker.reset()
        self.showRectangle(nil)
        return
      }

      let quad = NormalizedQuad(
        topLeft: observation.topLeft,
        topRight: observation.topRight,
        bottomLeft: observation.bottomLeft,
        bottomRight: observation.bottomRight
      )
      self.showRectangle(quad)

      let qualityAcceptable = self.cameraDevice.map {
        !$0.isAdjustingFocus && !$0.isAdjustingExposure
      } ?? false
      guard self.stabilityTracker.observe(quad, qualityAcceptable: qualityAcceptable) else {
        return
      }
      self.captureStablePage()
    }
    request.maximumObservations = 1
    request.minimumConfidence = 0.8
    request.minimumAspectRatio = 0.3
    request.minimumSize = 0.35

    do {
      try VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer,
        orientation: .up
      ).perform([request])
    } catch {
      stabilityTracker.reset()
      showRectangle(nil)
    }
  }

  private func captureStablePage() {
    guard lifecycle.beginCapture() else { return }
    videoOutput.setSampleBufferDelegate(nil, queue: nil)

    DispatchQueue.main.async { [weak self] in
      self?.statusLabel.text = "Page found · Hold still for automatic capture"
    }

    let settings = AVCapturePhotoSettings()
    settings.flashMode = .off
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func processCapturedPhoto(_ photo: AVCapturePhoto) {
    guard let data = photo.fileDataRepresentation() else {
      complete(.failure(.captureFailed))
      return
    }

    autoreleasepool {
      guard let sourceImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
        complete(.failure(.captureFailed))
        return
      }

      guard let normalizedCGImage = ciContext.createCGImage(sourceImage, from: sourceImage.extent) else {
        complete(.failure(.captureFailed))
        return
      }
      let normalizedImage = CIImage(cgImage: normalizedCGImage)

      let rectangleRequest = VNDetectRectanglesRequest()
      rectangleRequest.maximumObservations = 1
      rectangleRequest.minimumConfidence = 0.8
      rectangleRequest.minimumAspectRatio = 0.3
      rectangleRequest.minimumSize = 0.35
      do {
        try VNImageRequestHandler(cgImage: normalizedCGImage, orientation: .up)
          .perform([rectangleRequest])
      } catch {
        complete(.failure(.correctionFailed))
        return
      }
      guard let observation = rectangleRequest.results?.first as? VNRectangleObservation else {
        complete(.failure(.correctionFailed))
        return
      }
      let points = NormalizedQuad(
        topLeft: observation.topLeft,
        topRight: observation.topRight,
        bottomLeft: observation.bottomLeft,
        bottomRight: observation.bottomRight
      ).imagePoints(in: normalizedImage.extent)

      guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
        complete(.failure(.correctionFailed))
        return
      }
      filter.setValue(normalizedImage, forKey: kCIInputImageKey)
      filter.setValue(CIVector(cgPoint: points.topLeft), forKey: "inputTopLeft")
      filter.setValue(CIVector(cgPoint: points.topRight), forKey: "inputTopRight")
      filter.setValue(CIVector(cgPoint: points.bottomLeft), forKey: "inputBottomLeft")
      filter.setValue(CIVector(cgPoint: points.bottomRight), forKey: "inputBottomRight")

      guard
        let correctedImage = filter.outputImage,
        !correctedImage.extent.isEmpty,
        let cgImage = ciContext.createCGImage(correctedImage, from: correctedImage.extent)
      else {
        complete(.failure(.correctionFailed))
        return
      }
      recognizeText(in: cgImage)
    }
  }

  private func recognizeText(in image: CGImage) {
    let request = VNRecognizeTextRequest { [weak self] request, error in
      guard let self else { return }
      guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
        self.complete(.failure(.ocrFailed))
        return
      }

      let lines = observations.compactMap { observation -> RecognizedLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return RecognizedLine(text: text, boundingBox: observation.boundingBox)
      }
      let text = TextObservationSorter.join(lines).trimmingCharacters(in: .whitespacesAndNewlines)
      self.complete(text.isEmpty ? .failure(.noText) : .success(text))
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "vi-VN"]
    request.usesLanguageCorrection = true

    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    } catch {
      complete(.failure(.ocrFailed))
    }
  }

  private func showRectangle(_ quad: NormalizedQuad?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let quad else {
        self.rectangleLayer.path = nil
        self.statusLabel.text = "Keep the page flat and well lit"
        return
      }

      func layerPoint(_ point: CGPoint) -> CGPoint {
        self.previewLayer.layerPointConverted(
          fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y)
        )
      }
      let path = UIBezierPath()
      path.move(to: layerPoint(quad.topLeft))
      path.addLine(to: layerPoint(quad.topRight))
      path.addLine(to: layerPoint(quad.bottomRight))
      path.addLine(to: layerPoint(quad.bottomLeft))
      path.close()
      self.rectangleLayer.path = path.cgPath
      self.statusLabel.text = "Page found · Hold still for automatic capture"
    }
  }

  private func complete(_ result: Result<String, PageScannerFailure>) {
    scannerQueue.async { [weak self] in
      guard let self, self.lifecycle.finish(result) else { return }
      self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
      if self.captureSession.isRunning {
        self.captureSession.stopRunning()
      }
      DispatchQueue.main.async {
        self.rectangleLayer.path = nil
        self.onComplete?(result)
        self.onComplete = nil
      }
    }
  }

  func failPresentation() {
    complete(.failure(.cameraUnavailable))
  }

  @objc private func cancel() {
    complete(.failure(.cancelled))
  }

  @objc private func captureSessionRuntimeError(_ notification: Notification) {
    complete(.failure(.cameraUnavailable))
  }

  @objc private func captureSessionWasInterrupted(_ notification: Notification) {
    complete(.failure(.cameraUnavailable))
  }
}

extension PageScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !lifecycle.isCapturing, !lifecycle.isTerminal else { return }
    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if lastProcessedTime.isValid,
       CMTimeGetSeconds(presentationTime - lastProcessedTime) < 0.2 {
      return
    }
    lastProcessedTime = presentationTime
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    detectRectangle(in: pixelBuffer)
  }
}

extension PageScannerViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard error == nil else {
      complete(.failure(.captureFailed))
      return
    }
    scannerQueue.async { [weak self] in
      guard let self, !self.lifecycle.isTerminal else { return }
      self.processCapturedPhoto(photo)
    }
  }
}
