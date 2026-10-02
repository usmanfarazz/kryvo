/// A single saved credential inside the vault.
///
/// The whole list of entries is serialized to JSON, encrypted with the
/// master-password-derived key, and only then written to storage. A plain
/// [VaultEntry] never touches the disk on its own.
class VaultEntry {
  String id;
  String title;
  String username;
  String password;
  String category; // Social / Bank / Cards / UPI / Email / Notes / Other
  String notes;
  bool pinned;
  int createdAt; // epoch ms
  int updatedAt; // epoch ms
  /// '' = the real vault, 'decoy' = the fake vault opened by the fake PIN.
  String space;

  VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.category = 'Other',
    this.notes = '',
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.space = '',
  });

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        password: (j['password'] ?? '') as String,
        category: (j['category'] ?? 'Other') as String,
        notes: (j['notes'] ?? '') as String,
        pinned: (j['pinned'] ?? false) as bool,
        createdAt: (j['createdAt'] ?? 0) as int,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        space: (j['space'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'category': category,
        'notes': notes,
        'pinned': pinned,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (space.isNotEmpty) 'space': space,
      };
}

/// The categories offered in the UI. Keep "Other" last as the fallback.
const List<String> kCategories = <String>[
  'Social',
  'Bank',
  'Cards',
  'UPI',
  'Email',
  'Notes',
  'Other',
];
