/// The four media sections shown on the home screen.
class MediaCat {
  static const photo = 'photo';
  static const video = 'video';
  static const web = 'web';
  static const audio = 'audio';

  static const all = [photo, video, web, audio];

  static String title(String c) {
    switch (c) {
      case video:
        return 'Safe Video';
      case web:
        return 'Safe Web Image';
      case audio:
        return 'Safe Audio';
      default:
        return 'Safe Photo';
    }
  }

  static String noun(String c) {
    switch (c) {
      case video:
        return 'videos';
      case web:
        return 'web images';
      case audio:
        return 'audio files';
      default:
        return 'photos';
    }
  }

  /// Storage type used for a category ('photo' | 'video' | 'audio').
  static String typeOf(String c) {
    switch (c) {
      case video:
        return 'video';
      case audio:
        return 'audio';
      default:
        return 'photo';
    }
  }
}

/// One hidden photo, video, web image or audio file in the vault.
///
/// The actual bytes live in an encrypted file on disk (`<id>.enc`); videos may
/// also have an encrypted thumbnail (`<id>.thumb`). This object is just the
/// metadata, kept in an encrypted index.
class MediaItem {
  final String id;
  final String type; // 'photo' | 'video' | 'audio'
  final String category; // MediaCat.*
  final String folder; // '' = the main folder
  final String name; // original file name
  final int addedAt; // epoch ms
  final int sizeBytes; // original (plaintext) size
  final int deletedAt; // 0 = active; >0 = in recycle bin (epoch ms)
  final bool fav; // marked as favourite
  /// '' = the real vault, 'decoy' = the fake vault opened by the fake PIN.
  final String space;

  MediaItem({
    required this.id,
    required this.type,
    required this.name,
    required this.addedAt,
    required this.sizeBytes,
    String? category,
    this.folder = '',
    this.deletedAt = 0,
    this.fav = false,
    this.space = '',
  }) : category = category ??
            (type == 'video'
                ? MediaCat.video
                : type == 'audio'
                    ? MediaCat.audio
                    : MediaCat.photo);

  bool get isVideo => type == 'video';
  bool get isAudio => type == 'audio';
  bool get isImage => type == 'photo';
  bool get inTrash => deletedAt > 0;

  MediaItem copyWith(
          {int? deletedAt, String? folder, String? name, bool? fav}) =>
      MediaItem(
        id: id,
        type: type,
        category: category,
        folder: folder ?? this.folder,
        name: name ?? this.name,
        addedAt: addedAt,
        sizeBytes: sizeBytes,
        deletedAt: deletedAt ?? this.deletedAt,
        fav: fav ?? this.fav,
        space: space,
      );

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        type: (j['type'] ?? 'photo') as String,
        category: j['category'] as String?,
        folder: (j['folder'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        addedAt: (j['addedAt'] ?? 0) as int,
        sizeBytes: (j['sizeBytes'] ?? 0) as int,
        deletedAt: (j['deletedAt'] ?? 0) as int,
        fav: (j['fav'] ?? false) as bool,
        space: (j['space'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'category': category,
        'folder': folder,
        'name': name,
        'addedAt': addedAt,
        'sizeBytes': sizeBytes,
        'deletedAt': deletedAt,
        if (fav) 'fav': true,
        if (space.isNotEmpty) 'space': space,
      };
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
