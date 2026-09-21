import 'dart:io';
import '../models/attendance.dart';
import '../models/worker.dart';
import 'image_helper.dart';

/// 출근에 별도로 지정한 사진을 우선 사용하고, 없으면 연결된 근로자 사진을 참조합니다.
class AttendancePhotos {
  final File? front;
  final File? back;
  final File? safetyTraining;
  final File? healthCertificate;

  AttendancePhotos._(
      this.front, this.back, this.safetyTraining, this.healthCertificate);

  factory AttendancePhotos.resolve(
      Attendance attendance, Iterable<Worker> workers) {
    Worker? worker;
    if (attendance.workerId != null && attendance.workerId!.isNotEmpty) {
      for (final candidate in workers) {
        if (candidate.id == attendance.workerId) {
          worker = candidate;
          break;
        }
      }
    }
    File? resolve(String? savedPath, String? workerPath) =>
        ImageHelper.getFileFromPath(savedPath) ??
        ImageHelper.getFileFromPath(workerPath);
    return AttendancePhotos._(
      resolve(attendance.idPhotoPath, worker?.idPhotoPath),
      resolve(attendance.idPhotoBackPath, worker?.idPhotoBackPath),
      resolve(
          attendance.safetyTrainingPhotoPath, worker?.safetyTrainingPhotoPath),
      resolve(attendance.healthCertificatePhotoPath,
          worker?.healthCertificatePhotoPath),
    );
  }
}
