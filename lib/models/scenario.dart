/// Scenario model — mirrors backend ScenarioInfo.
class Scenario {
  final String id;
  final String title;
  final String description;
  final int sourceCount;
  final List<String> tags;

  Scenario({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceCount,
    this.tags = const [],
  });

  factory Scenario.fromJson(Map<String, dynamic> json) => Scenario(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        sourceCount: json['source_count'] as int? ?? 0,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      );
}
