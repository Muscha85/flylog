/// Oblíbené nebo často navštěvované místo s předvyplněnými GPS souřadnicemi.
class FavoritePlace {
  const FavoritePlace({
    required this.name,
    this.latitude,
    this.longitude,
    this.country = 'Česko',
  });

  final String name;
  final double? latitude;
  final double? longitude;
  final String country;

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'country': country,
      };

  factory FavoritePlace.fromJson(Map<String, dynamic> json) {
    return FavoritePlace(
      name: json['name'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      country: json['country'] as String? ?? 'Česko',
    );
  }

  /// Výchozí předdefinovaná rodinná místa
  static const List<FavoritePlace> defaults = [
    FavoritePlace(name: 'Olomouc', latitude: 49.5955, longitude: 17.2517),
    FavoritePlace(name: 'Havlíčkův Brod', latitude: 49.6079, longitude: 15.5807),
    FavoritePlace(name: 'Jeseníky', latitude: 50.0833, longitude: 17.2333),
    FavoritePlace(name: 'Chata Paprsek', latitude: 50.2114, longitude: 16.9932),
  ];
}
