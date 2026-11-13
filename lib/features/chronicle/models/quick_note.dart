/// Model rychlé průběžné poznámky v rozpracovaném záznamu (Draft).
class QuickNote {
  const QuickNote({
    required this.id,
    required this.timestamp,
    required this.text,
  });

  final String id;
  final DateTime timestamp;
  final String text;

  QuickNote copyWith({
    String? id,
    DateTime? timestamp,
    String? text,
  }) {
    return QuickNote(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'text': text,
      };

  factory QuickNote.fromJson(Map<String, dynamic> json) {
    return QuickNote(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      text: json['text'] as String? ?? '',
    );
  }
}
