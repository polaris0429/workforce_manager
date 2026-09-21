import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class DocumentPhotoPicker extends StatelessWidget {
  final String label;
  final File? file;
  final double height;
  final ValueChanged<File> onChanged;

  const DocumentPhotoPicker(
      {super.key,
      required this.label,
      this.file,
      this.height = 100,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(children: [
        InkWell(
          onTap: () async {
            final result =
                await FilePicker.platform.pickFiles(type: FileType.image);
            final path = result?.files.single.path;
            if (context.mounted && path != null) onChanged(File(path));
          },
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4)),
            child: file == null
                ? const Center(
                    child: Icon(Icons.camera_alt, color: Colors.grey))
                : Image.file(file!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined)),
          ),
        ),
        Text(label,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      ]);
}

class CertificatePhotos extends StatelessWidget {
  final File? safetyTraining;
  final File? healthCertificate;
  final void Function(File)? onSafetyChanged;
  final void Function(File)? onHealthChanged;
  final bool compact;
  final Size thumbnailSize;
  final double pickerHeight;

  const CertificatePhotos(
      {super.key,
      this.safetyTraining,
      this.healthCertificate,
      this.onSafetyChanged,
      this.onHealthChanged,
      this.compact = false,
      this.thumbnailSize = const Size(90, 56),
      this.pickerHeight = 100});

  Widget _photo(BuildContext context, String label, File? file,
      void Function(File)? onChanged) {
    if (!compact && onChanged != null) {
      return DocumentPhotoPicker(
          label: label, file: file, height: pickerHeight, onChanged: onChanged);
    }
    return SizedBox(
        width: compact
            ? (thumbnailSize.width < 70 ? 70 : thumbnailSize.width)
            : null,
        child: Column(children: [
          InkWell(
            onTap: () async {
              if (onChanged != null) {
                final result =
                    await FilePicker.platform.pickFiles(type: FileType.image);
                final path = result?.files.single.path;
                if (context.mounted && path != null) onChanged(File(path));
              } else if (file != null) {
                showDocumentPhotoViewer(context, file: file, label: label);
              }
            },
            child: Container(
              width: compact ? thumbnailSize.width : double.infinity,
              height: compact ? thumbnailSize.height : 100,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4)),
              child: file == null
                  ? Center(
                      child: Text(onChanged == null ? '미등록' : '사진 선택 (선택사항)',
                          style: TextStyle(
                              fontSize: compact ? 11 : 12, color: Colors.grey)))
                  : Image.file(file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined)),
            ),
          ),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:
                      compact ? (thumbnailSize.width < 70 ? 9 : 11) : 12)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final safety = _photo(context, '안전교육 이수증', safetyTraining, onSafetyChanged);
    final health = _photo(context, '보건증', healthCertificate, onHealthChanged);
    return Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) safety else Expanded(child: safety),
          SizedBox(width: compact ? 8 : 10),
          if (compact) health else Expanded(child: health),
        ]);
  }
}

Future<void> showDocumentPhotoViewer(BuildContext context,
    {required File file, required String label}) async {
  await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
            title: Text(label),
            content: SizedBox(
                width: 700,
                height: 500,
                child: InteractiveViewer(
                    child: Image.file(file, fit: BoxFit.contain))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
              ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('다른 위치에 저장'),
                  onPressed: () => _saveImageToExternal(context, file)),
            ],
          ));
}

Future<void> _saveImageToExternal(BuildContext context, File file) async {
  try {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final destination = p.join(directory, p.basename(file.path));
    // 원본과 같은 위치를 선택하면 파일을 다시 쓰지 않습니다.
    final isOriginal = await File(destination).exists() &&
        await FileSystemEntity.identical(file.path, destination);
    if (!isOriginal) await file.copy(destination);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 완료: $destination')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }
}
