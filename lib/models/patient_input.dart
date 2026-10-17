enum Sex {
  female('Female', 'female'),
  male('Male', 'male');

  const Sex(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

/// Architecture step 1.1: what the user types in before the scan.
class PatientInput {
  final int age;
  final Sex sex;

  const PatientInput({required this.age, required this.sex});

  static const minAge = 1;
  static const maxAge = 120;

  PatientInput copyWith({int? age, Sex? sex}) =>
      PatientInput(age: age ?? this.age, sex: sex ?? this.sex);
}
