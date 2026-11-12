/// 导出：把整库倒成一份 JSON，写到临时目录，再交给系统分享。
///
/// 为什么是分享而不是"保存到下载目录"：
/// Android 的公共目录读写要走 SAF，权限与路径在各家 ROM 上行为不一。
/// 分享面板让用户自己决定存到哪（文件管理器、网盘、聊天窗口），
/// 我们只需要生成文件——少一层权限，也少一类兼容问题。
library;

import 'dart:io';

import 'package:exp_ledger/data/repository/maintenance_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportService {
  ExportService({required MaintenanceRepository maintenance})
      : _maintenance = maintenance;

  final MaintenanceRepository _maintenance;

  /// 生成导出文件并返回路径。文件名带日期，方便用户自己区分。
  Future<File> writeJson({bool pretty = true}) async {
    final String json = await _maintenance.exportJson(pretty: pretty);
    final Directory dir = await getTemporaryDirectory();
    final String stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final File file = File(p.join(dir.path, 'exp_ledger_$stamp.json'));
    await file.writeAsString(json);
    return file;
  }

  /// 调起系统分享面板。返回是否成功发起（不代表用户真的发出去了）。
  Future<bool> share() async {
    final File file = await writeJson();
    final ShareResult result = await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/json')],
      subject: '经验账本导出 · ${DateTime.now().toIso8601String().substring(0, 10)}',
      text: '本地导出的全部记录。文件里没有账号信息，也没有任何联网上传。',
    );
    return result.status != ShareResultStatus.unavailable;
  }
}
