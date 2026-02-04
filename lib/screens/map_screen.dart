import 'package:flutter/material.dart';

// TODO(phase1): Import mapbox_maps_flutter and set up MapWidget
// TODO(phase1): Add GPS location display with accuracy circle
// TODO(phase1): Add compass button and zoom-to-location button
// TODO(phase2): Add GPX track overlay
// TODO(phase3): Add offline indicator

/// Main screen of the app. The map fills the entire screen with
/// minimal control overlays.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // TODO(phase1): MapboxMap controller reference
  // TODO(phase1): Location service instance
  // TODO(phase1): Current position state

  @override
  void initState() {
    super.initState();
    // TODO(phase1): Initialize map service
    // TODO(phase1): Request location permissions and start GPS
  }

  @override
  void dispose() {
    // TODO(phase1): Clean up map controller and location subscriptions
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // TODO(phase1): Replace with MapWidget from mapbox_maps_flutter
          const Center(
            child: Text(
              'Map will be displayed here',
              style: TextStyle(color: Colors.white70),
            ),
          ),

          // TODO(phase1): Overlay controls (compass, zoom-to-location)
          // Keep controls minimal — positioned at edges, semi-transparent
        ],
      ),
    );
  }
}
