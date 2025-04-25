import 'dart:convert';

import '../_index.dart';

extension ReadiumDownloadTaskExtension on Task {
  OPDSPublication? getOpdsPublication() {
    final jsonMap = json.decode(metaData) as Map<String, dynamic>;

    return OPDSPublication.fromJson(jsonMap);
  }

  Task setOpdsPublication(final OPDSPublication pub) {
    final pubMap = pub.toJson();
    if (pubMap['metadata'] != null) {
      // books with large metadata can cause the app to crash
      // so we remove all metadata except the title and identifier
      pubMap['metadata'] = {
        'title': pubMap['metadata']['title'],
        'identifier': pubMap['metadata']['identifier'],
      };
    }
    return copyWith(metaData: json.encode(pubMap));
  }
}

extension ReadiumTaskRecordExtension on TaskRecord {
  DownloadProgress toDownloadProgress() => DownloadProgress(
        taskId: taskId,
        status: DownloadStatus.values[status.index],
        progress: (progress * 100).round(),
        opdsPublication: task.getOpdsPublication()!,
      );
}
