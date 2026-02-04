// TODO(phase1): Implement LocationService using the geolocator package
//
// Key responsibilities:
// - Check and request location permissions
// - Get current position (one-shot)
// - Start/stop continuous position stream
// - Configure accuracy level (high for recording, balanced for display)
// - Expose position as a Stream for reactive UI updates
// - Provide horizontal accuracy for the accuracy circle on the map
//
// Permission flow:
// 1. Check if location services are enabled
// 2. Check permission status
// 3. Request permission if needed
// 4. Handle "denied forever" case (direct user to settings)
//
// Battery considerations:
// - Use LocationAccuracy.high only during track recording
// - Use LocationAccuracy.balanced for passive location display
// - Allow user to configure GPS polling interval

class LocationService {
  // TODO(phase1): Implement
}
