class PatientInput {
  final int age;
  final String sex;
  final String userId;
  final DateTime timestamp;

  PatientInput({
    required this.age,
    required this.sex,
    required this.userId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'age': age,
      'sex': sex,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PatientInput.fromJson(Map<String, dynamic> json) {
    return PatientInput(
      age: json['age'] as int? ?? 25,
      sex: json['sex'] as String? ?? 'Male',
      userId: json['user_id'] as String? ?? 'anon_user',
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'] as String) 
          : DateTime.now(),
    );
  }
}
