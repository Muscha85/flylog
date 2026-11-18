import 'package:flutter/material.dart';

import '../../models/event_item.dart';

/// Interaktivní lišta s 5 smajlíky pro hodnocení zážitku z výletu či dne.
class EventRatingBar extends StatelessWidget {
  const EventRatingBar({
    super.key,
    required this.selectedRating,
    required this.onRatingChanged,
    this.readOnly = false,
  });

  final int? selectedRating;
  final ValueChanged<int?> onRatingChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 5 smajlíků od nejhoršího po nejlepší
    final ratings = [
      EventRating.terrible, // 1
      EventRating.poor,     // 2
      EventRating.average,  // 3
      EventRating.great,    // 4
      EventRating.awesome,  // 5
    ];

    final current = EventRating.fromStars(selectedRating);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final r in ratings) ...[
              _buildSmileyButton(context, r, isSelected: selectedRating == r.stars),
            ],
          ],
        ),
        if (current != null) ...[
          const SizedBox(height: 6),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '${current.emoji} ${current.label}',
                key: ValueKey(current.stars),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _getColorForRating(current.stars, scheme),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSmileyButton(BuildContext context, EventRating rating, {required bool isSelected}) {
    final theme = Theme.of(context);
    final isHoverOrActive = isSelected;

    return InkWell(
      onTap: readOnly
          ? null
          : () {
              if (selectedRating == rating.stars) {
                // Opětovným klepnutím lze hodnocení zrušit
                onRatingChanged(null);
              } else {
                onRatingChanged(rating.stars);
              }
            },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isHoverOrActive
              ? _getColorForRating(rating.stars, theme.colorScheme).withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHoverOrActive
                ? _getColorForRating(rating.stars, theme.colorScheme)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isHoverOrActive
              ? [
                  BoxShadow(
                    color: _getColorForRating(rating.stars, theme.colorScheme).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.emoji,
              style: TextStyle(
                fontSize: isHoverOrActive ? 30 : 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForRating(int stars, ColorScheme scheme) {
    switch (stars) {
      case 5:
        return Colors.amber.shade700;
      case 4:
        return Colors.green.shade600;
      case 3:
        return Colors.blue.shade600;
      case 2:
        return Colors.orange.shade700;
      case 1:
        return Colors.red.shade600;
      default:
        return scheme.primary;
    }
  }
}

