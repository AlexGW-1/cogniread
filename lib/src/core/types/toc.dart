enum TocMode {
  official,
  generated,
}

enum TocSource {
  nav,
  ncx,
  headings,
  spine,
  fb2,
}

class TocNode {
  const TocNode({
    required this.id,
    required this.parentId,
    required this.label,
    required this.href,
    required this.fragment,
    required this.level,
    required this.order,
    required this.source,
  });

  final String id;
  final String? parentId;
  final String label;
  final String? href;
  final String? fragment;
  final int level;
  final int order;
  final TocSource source;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'parentId': parentId,
        'label': label,
        'href': href,
        'fragment': fragment,
        'level': level,
        'order': order,
        'source': source.name,
      };

  static TocNode fromMap(Map<String, Object?> map) {
    return TocNode(
      id: map['id'] as String? ?? '',
      parentId: map['parentId'] as String?,
      label: map['label'] as String? ?? '',
      href: map['href'] as String?,
      fragment: map['fragment'] as String?,
      level: (map['level'] as num?)?.toInt() ?? 0,
      order: (map['order'] as num?)?.toInt() ?? 0,
      source: TocSource.values.firstWhere(
        (value) => value.name == map['source'],
        orElse: () => TocSource.nav,
      ),
    );
  }
}
