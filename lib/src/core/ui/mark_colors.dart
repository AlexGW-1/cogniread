import 'package:flutter/material.dart';

class MarkColorOption {
  const MarkColorOption({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}

const List<MarkColorOption> markColorOptions = <MarkColorOption>[
  MarkColorOption(key: 'yellow', label: 'Желтый', color: Color(0xFFFFF59D)),
  MarkColorOption(key: 'green', label: 'Зеленый', color: Color(0xFFC8E6C9)),
  MarkColorOption(key: 'pink', label: 'Розовый', color: Color(0xFFF8BBD0)),
  MarkColorOption(key: 'blue', label: 'Голубой', color: Color(0xFFBBDEFB)),
  MarkColorOption(key: 'orange', label: 'Оранжевый', color: Color(0xFFFFE0B2)),
  MarkColorOption(key: 'purple', label: 'Фиолетовый', color: Color(0xFFD1C4E9)),
];

Color markColorForKey(String key) {
  return markColorOptions
      .firstWhere(
        (option) => option.key == key,
        orElse: () => markColorOptions.first,
      )
      .color;
}

