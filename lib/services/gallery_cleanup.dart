import 'package:photo_manager/photo_manager.dart';

/// Helpers for items picked with the phone's own picker (which only gives us
/// copies): find the originals in the gallery by file name, so we can take
/// their thumbnail and then ask Android to delete them (truly hidden).
class GalleryCleanup {
  static Future<bool> _access(RequestType type) async {
    final ps = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: type == RequestType.audio ? RequestType.audio : RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    return ps.hasAccess;
  }

  /// Map of file name -> gallery asset, for the given names.
  static Future<Map<String, AssetEntity>> findByNames(
      List<String> names, RequestType type) async {
    final found = <String, AssetEntity>{};
    if (names.isEmpty) return found;
    try {
      if (!await _access(type)) return found;
      final paths =
          await PhotoManager.getAssetPathList(type: type, onlyAll: true);
      if (paths.isEmpty) return found;
      final all = paths.first;
      final total = await all.assetCountAsync;
      final wanted = names.toSet();
      const chunk = 200;
      // Newest first; just-picked items are almost always recent.
      for (var start = 0;
          start < total && start < 3000 && found.length < wanted.length;
          start += chunk) {
        final end = (start + chunk) > total ? total : start + chunk;
        final list = await all.getAssetListRange(start: start, end: end);
        for (final a in list) {
          final t = a.title;
          if (t != null && wanted.contains(t) && !found.containsKey(t)) {
            found[t] = a;
          }
        }
      }
    } catch (_) {}
    return found;
  }

  /// Ask Android to delete these gallery items. Returns how many were removed.
  static Future<int> deleteIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final deleted = await PhotoManager.editor.deleteWithIds(ids);
      return deleted.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> removeOriginalsByName(
      List<String> names, RequestType type) async {
    final found = await findByNames(names, type);
    return deleteIds(found.values.map((a) => a.id).toList());
  }
}
