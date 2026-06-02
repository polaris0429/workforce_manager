class SmsPreset {
  String id;
  String name;
  String message;

  SmsPreset({this.id = '', required this.name, required this.message});

  Map<String, dynamic> toMap() => {'name': name, 'message': message};

  factory SmsPreset.fromMap(Map<String, dynamic> map, String id) {
    return SmsPreset(
      id: id,
      name: map['name'] ?? '',
      message: map['message'] ?? '',
    );
  }
}
