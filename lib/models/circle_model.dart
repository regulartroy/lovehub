enum CircleType { relationship, household, social }

class Circle {
  final String id;
  final String name;
  final CircleType type;
  final List<String> members; // List of User UIDs

  Circle({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
  });

  // Convert Firestore document to Circle Object
  factory Circle.fromMap(Map<String, dynamic> data, String documentId) {
    return Circle(
      id: documentId,
      name: data['name'] ?? '',
      type: CircleType.values.firstWhere(
        (e) => e.toString() == 'CircleType.${data['type']}',
        orElse: () => CircleType.social,
      ),
      members: List<String>.from(data['members'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.toString().split('.').last,
      'members': members,
    };
  }
}
