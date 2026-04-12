import Flutter
import UIKit
import CoreLocation
import Speech

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {

  /// Location manager for background & significant-change monitoring.
  private let locationManager = CLLocationManager()

  /// Method channel for background service (location).
  private var methodChannel: FlutterMethodChannel?

  /// Method channel for silent voice recognition.
  private var voiceChannel: FlutterMethodChannel?

  /// Native silent speech recognizer (no "ding" sounds).
  private let silentSpeech = SilentSpeechRecognizer()

  /// UserDefaults key — mirrors Android's safecircle_always_on_enabled.
  private let alwaysOnKey = "safecircle_always_on_enabled"
  private let lastLocationKey = "safecircle_last_known_location"

  /// Whether the always-on mode is enabled.
  private var isAlwaysOn: Bool {
    return UserDefaults.standard.bool(forKey: alwaysOnKey)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Configure location manager for background tracking
    locationManager.delegate = self
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.showsBackgroundLocationIndicator = true
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 50 // Update every 50 meters

    // Set up Method Channels
    if let controller = window?.rootViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(
        name: "com.safecircle.app/background",
        binaryMessenger: controller.binaryMessenger
      )
      voiceChannel = FlutterMethodChannel(
        name: "com.safecircle.app/voice",
        binaryMessenger: controller.binaryMessenger
      )
      setupMethodCallHandler()
      setupVoiceCallHandler()
    }

    // If the app was launched by a significant location change while killed,
    // re-enable tracking automatically
    if launchOptions?[.location] != nil {
      NSLog("[SafeCircle-iOS] App launched from significant location change")
      if isAlwaysOn {
        startLocationTracking()
      }
    }

    // If always-on was previously enabled, restart tracking
    if isAlwaysOn {
      startLocationTracking()
    }

    // Register for background fetch
    UIApplication.shared.setMinimumBackgroundFetchInterval(
      UIApplication.backgroundFetchIntervalMinimum
    )

    // Register plugins
    GeneratedPluginRegistrant.register(with: self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Method Channel

  private func setupMethodCallHandler() {
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }

      switch call.method {
      case "startForegroundService":
        // iOS doesn't have foreground services — we start background location instead
        self.startLocationTracking()
        UserDefaults.standard.set(true, forKey: self.alwaysOnKey)
        NSLog("[SafeCircle-iOS] Background location tracking started")
        result(true)

      case "stopForegroundService":
        self.stopLocationTracking()
        UserDefaults.standard.set(false, forKey: self.alwaysOnKey)
        NSLog("[SafeCircle-iOS] Background location tracking stopped")
        result(true)

      case "isServiceRunning":
        result(self.isAlwaysOn)

      case "requestBatteryOptimizationExemption":
        // Not applicable on iOS
        result(true)

      case "isBatteryOptimizationExempt":
        // Not applicable on iOS
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Voice Channel

  private func setupVoiceCallHandler() {
    // Wire native speech results → Flutter
    silentSpeech.onResult = { [weak self] text, isFinal in
      self?.voiceChannel?.invokeMethod("onSpeechResult", arguments: [
        "text": text,
        "isFinal": isFinal,
      ])
    }

    silentSpeech.onError = { [weak self] errorMsg in
      self?.voiceChannel?.invokeMethod("onSpeechError", arguments: [
        "error": errorMsg,
      ])
    }

    voiceChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }

      switch call.method {
      case "startVoiceDetection":
        SilentSpeechRecognizer.requestAuthorization { granted in
          if granted {
            let started = self.silentSpeech.start()
            NSLog("[SafeCircle-iOS] Voice detection started: \(started)")
            result(started)
          } else {
            NSLog("[SafeCircle-iOS] Speech recognition permission denied")
            result(false)
          }
        }

      case "stopVoiceDetection":
        self.silentSpeech.stop()
        NSLog("[SafeCircle-iOS] Voice detection stopped")
        result(true)

      case "isVoiceDetectionRunning":
        result(self.silentSpeech.isRunning)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Location Tracking

  /// Start continuous background location tracking.
  ///
  /// Uses two strategies:
  /// 1. `startUpdatingLocation()` — precise updates while app is active/background
  /// 2. `startMonitoringSignificantLocationChanges()` — wakes app from killed state (~500m movement)
  private func startLocationTracking() {
    let status: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }

    if status == .authorizedAlways {
      // Full background — continuous + significant change fallback
      locationManager.startUpdatingLocation()
      locationManager.startMonitoringSignificantLocationChanges()
      NSLog("[SafeCircle-iOS] Started continuous + significant location tracking")
    } else if status == .authorizedWhenInUse {
      // Limited — only while app is active
      locationManager.startUpdatingLocation()
      NSLog("[SafeCircle-iOS] Started WhenInUse location tracking (limited background)")
    } else {
      locationManager.requestAlwaysAuthorization()
      NSLog("[SafeCircle-iOS] Requesting Always authorization")
    }
  }

  /// Stop all location tracking.
  private func stopLocationTracking() {
    locationManager.stopUpdatingLocation()
    locationManager.stopMonitoringSignificantLocationChanges()
    NSLog("[SafeCircle-iOS] Stopped all location tracking")
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }

    // Persist last known location for SMS fallback
    let locationString = "\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.horizontalAccuracy),\(ISO8601DateFormatter().string(from: location.timestamp))"
    UserDefaults.standard.set(locationString, forKey: lastLocationKey)

    // Send to Flutter via MethodChannel
    methodChannel?.invokeMethod("onLocationUpdate", arguments: [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "altitude": location.altitude,
      "speed": location.speed,
      "heading": location.course,
      "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000),
    ])

    NSLog("[SafeCircle-iOS] Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("[SafeCircle-iOS] Location error: \(error.localizedDescription)")
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      status = manager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }

    NSLog("[SafeCircle-iOS] Authorization changed: \(status.rawValue)")

    if isAlwaysOn {
      startLocationTracking()
    }

    methodChannel?.invokeMethod("onPermissionChanged", arguments: [
      "status": status.rawValue,
      "isAlways": status == .authorizedAlways,
      "isWhenInUse": status == .authorizedWhenInUse,
    ])
  }

  // MARK: - App Lifecycle

  override func applicationDidEnterBackground(_ application: UIApplication) {
    if isAlwaysOn {
      NSLog("[SafeCircle-iOS] App entered background — tracking continues")
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    if isAlwaysOn {
      // Significant location changes will relaunch the app
      NSLog("[SafeCircle-iOS] App terminating — significant changes will relaunch")
    }
  }
}
