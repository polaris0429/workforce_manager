class Worker {
  String  id;
  String  name;
  String  gender;
  String  residentNumber;
  String  phone;
  String  address;
  String  bankName;
  String  bankAccount;
  String  career;
  String  notes;
  String? idPhotoPath;
  String? idPhotoBackPath;
  bool    isBlacklisted;
  String? blacklistReason;
  DateTime createdAt;

  Worker({
    this.id             = '',
    required this.name,
    this.gender         = '',
    this.residentNumber = '',
    required this.phone,
    this.address        = '',
    this.bankName       = '',
    this.bankAccount    = '',
    this.career         = '',
    this.notes          = '',
    this.idPhotoPath,
    this.idPhotoBackPath,
    this.isBlacklisted   = false,
    this.blacklistReason,
    required this.createdAt,
  });

  factory Worker.fromMap(Map<String, dynamic> data, String docId) {
    return Worker(
      id:              docId.isNotEmpty ? docId : (data['id'] ?? ''),
      name:            data['name']             ?? '',
      gender:          data['gender']           ?? '',
      residentNumber:  data['resident_number']  ?? '',
      phone:           data['phone']            ?? '',
      address:         data['address']          ?? '',
      bankName:        data['bank_name']        ?? '',
      bankAccount:     data['bank_account']     ?? '',
      career:          data['career']           ?? '',
      notes:           data['notes']            ?? '',
      idPhotoPath:     data['id_photo_path'],
      idPhotoBackPath: data['id_photo_back_path'],
      // SQLite: INTEGER 0/1 → bool
      isBlacklisted:   _parseBool(data['is_blacklisted']),
      blacklistReason: data['blacklist_reason'],
      createdAt:       _parseDate(data['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id':                id,
      'name':              name,
      'gender':            gender,
      'resident_number':   residentNumber,
      'phone':             phone,
      'address':           address,
      'bank_name':         bankName,
      'bank_account':      bankAccount,
      'career':            career,
      'notes':             notes,
      'id_photo_path':     idPhotoPath,
      'id_photo_back_path': idPhotoBackPath,
      // bool → INTEGER (SQLite 호환)
      'is_blacklisted':    isBlacklisted ? 1 : 0,
      'blacklist_reason':  blacklistReason,
      'created_at':        createdAt.toIso8601String(),
    };
  }

  static bool _parseBool(dynamic v) {
    if (v == null)    return false;
    if (v is bool)    return v;
    if (v is int)     return v != 0;
    if (v is String)  return v == '1' || v.toLowerCase() == 'true';
    return false;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null)     return DateTime.now();
    if (value is DateTime) return value;
    if (value is String)   return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
