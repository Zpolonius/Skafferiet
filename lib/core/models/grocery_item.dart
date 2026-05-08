class GroceryItem {
  final String id;
  final String name;
  final String category;
  final String quantity;
  final String? unit;
  final String? imageUrl;
  final bool isChecked;
  final String source; // 'manual' or 'meal_plan'
  final DateTime createdAt;
  final int sortOrder;

  GroceryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    this.unit,
    this.imageUrl,
    this.isChecked = false,
    required this.source,
    required this.createdAt,
    int? sortOrder,
  }) : sortOrder = sortOrder ?? createdAt.millisecondsSinceEpoch;

  GroceryItem copyWith({
    String? id,
    String? name,
    String? category,
    String? quantity,
    String? unit,
    String? imageUrl,
    bool? isChecked,
    String? source,
    DateTime? createdAt,
    int? sortOrder,
  }) {
    return GroceryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
      isChecked: isChecked ?? this.isChecked,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'imageUrl': imageUrl,
      'isChecked': isChecked,
      'source': source,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'sortOrder': sortOrder,
    };
  }

  factory GroceryItem.fromMap(Map<String, dynamic> map, String id) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
    );
    return GroceryItem(
      id: id,
      name: map['name'] ?? '',
      category: map['category'] ?? 'Andet',
      quantity: map['quantity'] ?? '',
      unit: map['unit'],
      imageUrl: map['imageUrl'],
      isChecked: map['isChecked'] ?? false,
      source: map['source'] ?? 'manual',
      createdAt: createdAt,
      sortOrder: map['sortOrder'] ?? createdAt.millisecondsSinceEpoch,
    );
  }
}
