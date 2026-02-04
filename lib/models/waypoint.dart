/// A named point of interest (from GPX or user-created).
class Waypoint {
  final String id;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final double? elevation;
  final String symbol; // 'summit', 'hut', 'parking', 'water', 'generic'
  final String? routeId;
  final DateTime createdAt;

  const Waypoint({
    required this.id,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.symbol = 'generic',
    this.routeId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'desc': description,
        'lat': latitude,
        'lon': longitude,
        if (elevation != null) 'ele': elevation,
        'sym': symbol,
        if (routeId != null) 'routeId': routeId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['desc'] as String?,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        elevation: json['ele'] != null ? (json['ele'] as num).toDouble() : null,
        symbol: json['sym'] as String? ?? 'generic',
        routeId: json['routeId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
