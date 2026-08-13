import AVFoundation
import CoreImage
import ImageIO
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
  private let sessionQueue = DispatchQueue(label: "storybook_ar.scan.session")
  private let processingQueue = DispatchQueue(label: "storybook_ar.scan.frames")
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
  private var captureQuad: NormalizedQuad?
  private var isCapturing = false
  private var didComplete = false
  private var currentCaptureOrientation: AVCaptureVideoOrientation?

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    requestCameraAccess()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
    rectangleLayer.frame = view.bounds
    updateConnectionsForCurrentOrientation()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopCaptureSession()
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
    sessionQueue.async { [weak self] in
      guard let self, !self.didComplete else { return }

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
        self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
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

        DispatchQueue.main.sync {
          self.updateConnectionsForCurrentOrientation()
        }
        self.captureSession.startRunning()
      } catch {
        self.complete(.failure(.cameraUnavailable))
      }
    }
  }

  private func updateConnectionsForCurrentOrientation() {
    let orientation = captureVideoOrientation
    let orientationChanged = orientation != currentCaptureOrientation
    currentCaptureOrientation = orientation
    if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = orientation
    }
    if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = orientation
    }
    if orientationChanged {
      processingQueue.async { [weak self] in
        self?.stabilityTracker.reset()
      }
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

  private func detectRectangle(
    in pixelBuffer: CVPixelBuffer,
    videoOrientation: AVCaptureVideoOrientation
  ) {
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
      self.captureStablePage(quad)
    }
    request.maximumObservations = 1
    request.minimumConfidence = 0.8
    request.minimumAspectRatio = 0.3
    request.minimumSize = 0.35

    do {
      try VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer,
        orientation: imageOrientation(for: videoOrientation)
      ).perform([request])
    } catch {
      stabilityTracker.reset()
      showRectangle(nil)
    }
  }

  private func captureStablePage(_ quad: NormalizedQuad) {
    guard !isCapturing, !didComplete else { return }
    isCapturing = true
    captureQuad = quad
    videoOutput.setSampleBufferDelegate(nil, queue: nil)

    DispatchQueue.main.async { [weak self] in
      self?.statusLabel.text = "Page found · Hold still for automatic capture"
      self?.cancelButton.isEnabled = false
    }

    let settings = AVCapturePhotoSettings()
    settings.flashMode = .off
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func processCapturedPhoto(_ photo: AVCapturePhoto) {
    guard let data = photo.fileDataRepresentation(), let quad = captureQuad else {
      complete(.failure(.captureFailed))
      return
    }

    autoreleasepool {
      guard let sourceImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
        complete(.failure(.captureFailed))
        return
      }

      let extent = sourceImage.extent
      func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
          x: extent.minX + point.x * extent.width,
          y: extent.minY + point.y * extent.height
        )
      }

      guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
        complete(.failure(.correctionFailed))
        return
      }
      filter.setValue(sourceImage, forKey: kCIInputImageKey)
      filter.setValue(CIVector(cgPoint: imagePoint(quad.topLeft)), forKey: "inputTopLeft")
      filter.setValue(CIVector(cgPoint: imagePoint(quad.topRight)), forKey: "inputTopRight")
      filter.setValue(CIVector(cgPoint: imagePoint(quad.bottomLeft)), forKey: "inputBottomLeft")
      filter.setValue(CIVector(cgPoint: imagePoint(quad.bottomRight)), forKey: "inputBottomRight")

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

  private func imageOrientation(for videoOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
    switch videoOrientation {
    case .portrait:
      return .right
    case .portraitUpsideDown:
      return .left
    case .landscapeLeft:
      return .up
    case .landscapeRight:
      return .down
    @unknown default:
      return .right
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
    processingQueue.async { [weak self] in
      guard let self, !self.didComplete else { return }
      self.didComplete = true
      self.captureQuad = nil
      self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
      self.sessionQueue.async {
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
  }

  private func stopCaptureSession() {
    sessionQueue.async { [weak self] in
      guard let self, self.captureSession.isRunning else { return }
      self.captureSession.stopRunning()
    }
  }

  @objc private func cancel() {
    complete(.failure(.cancelled))
  }
}

extension PageScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !isCapturing, !didComplete else { return }
    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if lastProcessedTime.isValid,
       CMTimeGetSeconds(presentationTime - lastProcessedTime) < 0.2 {
      return
    }
    lastProcessedTime = presentationTime
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    detectRectangle(in: pixelBuffer, videoOrientation: connection.videoOrientation)
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
    processingQueue.async { [weak self] in
      self?.processCapturedPhoto(photo)
    }
  }
}
