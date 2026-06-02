class Client {
  String   id;
  String   name;
  String   address;
  String   contactPerson;
  String   phone;
  String   email;
  String   notes;
  DateTime createdAt;

  Client({
    this.id            = '',
    required this.name,
    this.address       = '',
    this.contactPerson = '',
    this.phone         = '',
    this.email         = '',
    this.notes         = '',
    required this.createdAt,
  });

  factory Client.fromMap(Map<String, dynamic> data, String docId) {
    return Client(
      id:            docId.isNotEmpty ? docId : (data['id'] ?? ''),
      name:          data['name']           ?? '',
      address:       data['address']        ?? '',
      contactPerson: data['contact_person'] ?? '',
      phone:         data['phone']          ?? '',
      email:         data['email']          ?? '',
      notes:         data['notes']          ?? '',
      createdAt:     _parseDate(data['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id':             id,
      'name':           name,
      'address':        address,
      'contact_person': contactPerson,
      'phone':          phone,
      'email':          email,
      'notes':          notes,
      'created_at':     createdAt.toIso8601String(),
    };
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null)     return DateTime.now();
    if (value is DateTime) return value;
    if (value is String)   return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
