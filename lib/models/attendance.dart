class Attendance {
  String   id;
  String?  workerId;
  String   workerName;
  String   workerGender;
  String   workerResidentNumber;
  String   workerPhone;       // 휴대폰번호
  String   workerHomePhone;   // 집전화번호
  String   workerAddress;
  String   workerBankName;
  String   workerBankAccount;
  String   workerCareer;
  String?  clientId;
  String   clientName;
  String   clientAddress;
  String   clientContactPerson;
  String   clientPhone;        // 연락처
  String   clientOfficePhone;  // 회사번호
  String   clientEmail;
  String   clientNotes;
  DateTime workDate;
  double   dailyWage;
  double   commissionRate;
  double   commission;
  double   netWage;
  String   notes;
  String?  idPhotoPath;
  String?  idPhotoBackPath;
  bool     isPostpaid;
  bool     isSettled;
  DateTime createdAt;

  Attendance({
    this.id                    = '',
    this.workerId,
    required this.workerName,
    this.workerGender          = '',
    this.workerResidentNumber  = '',
    this.workerPhone           = '',
    this.workerHomePhone       = '',
    this.workerAddress         = '',
    this.workerBankName        = '',
    this.workerBankAccount     = '',
    this.workerCareer          = '',
    this.clientId,
    required this.clientName,
    this.clientAddress         = '',
    this.clientContactPerson   = '',
    this.clientPhone           = '',
    this.clientOfficePhone     = '',
    this.clientEmail           = '',
    this.clientNotes           = '',
    required this.workDate,
    required this.dailyWage,
    required this.commissionRate,
    required this.commission,
    required this.netWage,
    this.notes                 = '',
    this.idPhotoPath,
    this.idPhotoBackPath,
    this.isPostpaid            = false,
    this.isSettled             = true,
    required this.createdAt,
  });

  factory Attendance.fromMap(Map<String, dynamic> data, String docId) {
    return Attendance(
      id:                   docId.isNotEmpty ? docId : (data['id'] ?? ''),
      workerId:             data['worker_id'],
      workerName:           data['worker_name']             ?? '',
      workerGender:         data['worker_gender']           ?? '',
      workerResidentNumber: data['worker_resident_number']  ?? '',
      workerPhone:          data['worker_phone']            ?? '',
      workerHomePhone:      data['worker_home_phone']       ?? '',
      workerAddress:        data['worker_address']          ?? '',
      workerBankName:       data['worker_bank_name']        ?? '',
      workerBankAccount:    data['worker_bank_account']     ?? '',
      workerCareer:         data['worker_career']           ?? '',
      clientId:             data['client_id'],
      clientName:           data['client_name']             ?? '',
      clientAddress:        data['client_address']          ?? '',
      clientContactPerson:  data['client_contact_person']   ?? '',
      clientPhone:          data['client_phone']            ?? '',
      clientOfficePhone:    data['client_office_phone']     ?? '',
      clientEmail:          data['client_email']            ?? '',
      clientNotes:          data['client_notes']            ?? '',
      workDate:             _parseDate(data['work_date']),
      dailyWage:            _toDouble(data['daily_wage']),
      commissionRate:       _toDouble(data['commission_rate']),
      commission:           _toDouble(data['commission']),
      netWage:              _toDouble(data['net_wage']),
      notes:                data['notes']                   ?? '',
      idPhotoPath:          data['id_photo_path'],
      idPhotoBackPath:      data['id_photo_back_path'],
      isPostpaid:           _parseBool(data['is_postpaid']),
      isSettled:            _parseBool(data['is_settled']),
      createdAt:            _parseDate(data['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id':                      id,
      'worker_id':               workerId,
      'worker_name':             workerName,
      'worker_gender':           workerGender,
      'worker_resident_number':  workerResidentNumber,
      'worker_phone':            workerPhone,
      'worker_home_phone':       workerHomePhone,
      'worker_address':          workerAddress,
      'worker_bank_name':        workerBankName,
      'worker_bank_account':     workerBankAccount,
      'worker_career':           workerCareer,
      'client_id':               clientId,
      'client_name':             clientName,
      'client_address':          clientAddress,
      'client_contact_person':   clientContactPerson,
      'client_phone':            clientPhone,
      'client_office_phone':     clientOfficePhone,
      'client_email':            clientEmail,
      'client_notes':            clientNotes,
      'work_date':               workDate.toIso8601String(),
      'daily_wage':              dailyWage,
      'commission_rate':         commissionRate,
      'commission':              commission,
      'net_wage':                netWage,
      'notes':                   notes,
      'id_photo_path':           idPhotoPath,
      'id_photo_back_path':      idPhotoBackPath,
      'is_postpaid':             isPostpaid ? 1 : 0,
      'is_settled':              isSettled  ? 1 : 0,
      'created_at':              createdAt.toIso8601String(),
    };
  }

  static double _toDouble(dynamic v) {
    if (v == null)   return 0.0;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static bool _parseBool(dynamic v) {
    if (v == null)   return false;
    if (v is bool)   return v;
    if (v is int)    return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null)     return DateTime.now();
    if (value is DateTime) return value;
    if (value is String)   return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
