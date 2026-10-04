import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/media_item.dart';
import '../models/vault_entry.dart';
import '../services/backup_service.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/decoy_service.dart';
import '../services/disguise_service.dart';
import '../services/folder_lock_service.dart';
import '../services/full_backup_service.dart';
import '../services/intruder_service.dart';
import '../services/media_service.dart';
import '../services/pin_service.dart';
import '../services/quick_unlock_service.dart';
import '../services/recovery_service.dart';
import '../services/secure_store.dart';
import '../services/settings_service.dart';
import '../services/vault_store.dart';
import '../theme.dart';

enum VaultStatus { loading, needsSetup, locked, unlocked }

/// Central app state: owns the decrypted vault while unlocked, and clears it
/// from memory the moment the vault locks (auto-lock, app backgrounded, or
/// manual lock).
class AppState extends ChangeNotifier {
  VaultStatus status = VaultStatus.loading;
  String? errorMessage;

  // Held only while unlocked:
  SecretKey? _key;
  List<int>? _salt;
  List<VaultEntry> _entries = [];

  // Hidden photos/videos (metadata); actual bytes stay encrypted on disk.
  List<MediaItem> media = [];
  final Map<String, Uint8List> _photoCache = {};
  final Map<String, Uint8List> _thumbCache = {};

  // ---- Fake PIN (decoy vault) ----------------------------------------------
  //
  // The fake PIN / password opens a separate, harmless "decoy" vault: only
  // items and passwords added while in it are visible (space == 'decoy'),
  // and sensitive settings are hidden. Everything is reset on lock.
  bool decoy = false;
  String get space => decoy ? 'decoy' : '';

  // Recycle bin (all categories), newest deletion first.
  List<MediaItem> get trash =>
      media.where((m) => m.inTrash && m.space == space).toList()
        ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));

  /// Active items of a category (optionally in one folder).
  List<MediaItem> itemsOf(String cat, {String? folder}) => media
      .where((m) =>
          !m.inTrash &&
          m.space == space &&
          m.category == cat &&
          (folder == null || m.folder == folder))
      .toList();

  /// Favourite items of every category.
  List<MediaItem> get favorites => media
      .where((m) => m.fav && !m.inTrash && m.space == space)
      .toList()
    ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> setFavorite(Iterable<MediaItem> items, bool fav) async {
    await MediaService.updateMany(
        items.map((m) => m.id).toSet(), (m) => m.copyWith(fav: fav));
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  // ---- Folder lock -------------------------------------------------------------

  Map<String, String> _folderLocks = {};

  /// Locked folders opened with their PIN since the vault was unlocked.
  final Set<String> _openedFolders = {};

  String _flKey(String cat, String folder) =>
      FolderLockService.keyOf(space, cat, folder);

  bool isFolderLocked(String cat, String folder) =>
      _folderLocks.containsKey(_flKey(cat, folder));

  /// Locked and not yet opened in this session.
  bool needsFolderPin(String cat, String folder) =>
      isFolderLocked(cat, folder) && !_openedFolders.contains(_flKey(cat, folder));

  int _folderFails = 0;
  DateTime? _folderBlockedUntil;

  /// Check a folder PIN. After 5 wrong tries, folder PINs are refused for 30 s.
  Future<bool> openLockedFolder(String cat, String folder, String pin) async {
    final until = _folderBlockedUntil;
    if (until != null && DateTime.now().isBefore(until)) return false;
    final ok =
        await FolderLockService.check(_folderLocks, _flKey(cat, folder), pin);
    if (ok) {
      _folderFails = 0;
      _openedFolders.add(_flKey(cat, folder));
    } else if (++_folderFails >= 5) {
      _folderFails = 0;
      _folderBlockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return ok;
  }

  Future<void> lockFolder(String cat, String folder, String pin) async {
    _folderLocks = await FolderLockService.set(_flKey(cat, folder), pin);
    _openedFolders.remove(_flKey(cat, folder));
    notifyListeners();
  }

  Future<void> unlockFolderForGood(String cat, String folder) async {
    _folderLocks = await FolderLockService.remove(_flKey(cat, folder));
    notifyListeners();
  }

  /// Key of a category in [folders] (the decoy vault has its own folders).
  String _fk(String cat) => decoy ? 'decoy:$cat' : cat;

  // category -> user-created folder names ('' main folder is implicit)
  Map<String, List<String>> folders = {};

  /// Folders of a category: main folder first, then created ones, plus any
  /// folder names that items still use.
  List<String> foldersOf(String cat) {
    final list = <String>[''];
    for (final f in folders[_fk(cat)] ?? const <String>[]) {
      if (!list.contains(f)) list.add(f);
    }
    for (final m in itemsOf(cat)) {
      if (!list.contains(m.folder)) list.add(m.folder);
    }
    return list;
  }

  Timer? _autoLockTimer;

  // ---- Settings ------------------------------------------------------------
  String themeId = 'midnight';
  bool get isDark => SV.dark;
  int autoLockSeconds = 60;
  bool recoveryEnabled = false;

  // Gallery-style preferences
  int slideshowSecs = 3;
  int maxZoom = 4;
  bool hideGuide = false;
  bool detailView = true;
  bool fitSmall = true;
  bool hideFolderThumbs = false;
  bool vibration = true;
  bool shakeLock = false;
  String lang = 'en';
  bool onboarded = true;
  bool faceDownLock = false;
  bool pinMode = false;
  String pinHint = '';

  List<VaultEntry> get entries =>
      List.unmodifiable(_entries.where((e) => e.space == space));
  bool get isUnlocked => status == VaultStatus.unlocked;

  Future<void> init() async {
    // One bulk read of secure storage instead of a slow read per setting.
    await SecureStore.instance.preload();
    themeId = await SettingsService.readThemeId();
    SV.setTheme(themeId);
    autoLockSeconds = await SettingsService.readAutoLockSeconds();
    // The auto-lock dropdown only offers these values; snap anything else
    // (e.g. an old default of 90s) to a valid one so the dropdown never crashes.
    const allowed = [30, 60, 120, 300, 600, 0]; // 0 = never
    if (!allowed.contains(autoLockSeconds)) {
      autoLockSeconds = 60;
      await SettingsService.writeAutoLockSeconds(60);
    }
    recoveryEnabled = await RecoveryService.isEnabled();
    slideshowSecs = await SettingsService.getInt(PrefKeys.slideshowSecs, 3);
    maxZoom = await SettingsService.getInt(PrefKeys.maxZoom, 4);
    hideGuide = await SettingsService.getBool(PrefKeys.hideGuide, false);
    detailView = await SettingsService.getBool(PrefKeys.detailView, true);
    fitSmall = await SettingsService.getBool(PrefKeys.fitSmall, true);
    hideFolderThumbs =
        await SettingsService.getBool(PrefKeys.hideFolderThumbs, false);
    vibration = await SettingsService.getBool(PrefKeys.vibration, true);
    shakeLock = await SettingsService.getBool(PrefKeys.shakeLock, false);
    lang = await SettingsService.getString(PrefKeys.lang) ?? 'en';
    setCurrentLang(lang);
    onboarded = await SettingsService.getBool(PrefKeys.onboarded, false);
    faceDownLock = await SettingsService.getBool(PrefKeys.faceDownLock, false);
    pinMode = await PinService.isPinMode();
    pinHint = await PinService.hint();
    appIcon = await DisguiseService.currentIcon();
    intruderEnabled = await IntruderService.isEnabled();
    fakePinSet = await DecoyService.isSet();
    _folderLocks = await FolderLockService.load();
    // Photos / videos / audio shared to Kryvo from another app.
    _mediaCh.setMethodCallHandler((call) async {
      if (call.method == 'sharedReady' && isUnlocked) await pullShared();
    });
    status =
        (await VaultStore.exists()) ? VaultStatus.locked : VaultStatus.needsSetup;
    notifyListeners();
  }

  Future<void> setTheme(String id) async {
    themeId = id;
    SV.setTheme(id);
    await SettingsService.writeThemeId(id);
    notifyListeners();
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    autoLockSeconds = seconds;
    await SettingsService.writeAutoLockSeconds(seconds);
    registerActivity();
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    await SettingsService.setBool(PrefKeys.onboarded, true);
    notifyListeners();
  }

  /// Show the tour again (Settings → Usage).
  void replayOnboarding() {
    onboarded = false;
    notifyListeners();
  }

  Future<void> setLang(String code) async {
    setCurrentLang(code);
    lang = currentLang;
    await SettingsService.setString(PrefKeys.lang, lang);
    notifyListeners();
  }

  Future<void> setIntPref(String key, int v) async {
    switch (key) {
      case PrefKeys.slideshowSecs:
        slideshowSecs = v;
      case PrefKeys.maxZoom:
        maxZoom = v;
    }
    await SettingsService.setInt(key, v);
    notifyListeners();
  }

  Future<void> setBoolPref(String key, bool v) async {
    switch (key) {
      case PrefKeys.hideGuide:
        hideGuide = v;
      case PrefKeys.detailView:
        detailView = v;
      case PrefKeys.fitSmall:
        fitSmall = v;
      case PrefKeys.hideFolderThumbs:
        hideFolderThumbs = v;
      case PrefKeys.vibration:
        vibration = v;
      case PrefKeys.shakeLock:
        shakeLock = v;
      case PrefKeys.faceDownLock:
        faceDownLock = v;
    }
    await SettingsService.setBool(key, v);
    notifyListeners();
  }

  // ---- Break-in log / intruder selfie ----------------------------------------------

  bool intruderEnabled = false;
  int _wrongInRow = 0;
  int _photosThisSeries = 0;

  /// Failed attempts since the owner last looked (shown once after unlock).
  int newIntrusions = 0;

  Future<void> setIntruderEnabled(bool on) async {
    await IntruderService.setEnabled(on);
    intruderEnabled = on;
    notifyListeners();
  }

  /// Called by the lock screen after a wrong PIN / password.
  void noteWrongAttempt(String method) {
    _wrongInRow++;
    final take = _wrongInRow >= IntruderService.threshold &&
        _photosThisSeries < IntruderService.maxPhotosPerSeries;
    if (take) _photosThisSeries++;
    // Not awaited: the lock screen must never wait for the camera.
    IntruderService.record(method, takePhoto: take);
  }

  /// Returns the pending count once (for the alert after unlocking).
  int takeNewIntrusions() {
    final n = newIntrusions;
    if (n > 0) clearNewIntrusions();
    return n;
  }

  void clearNewIntrusions() {
    newIntrusions = 0;
    IntruderService.markSeen();
  }

  bool fakePinSet = false;

  /// Set the fake PIN / password. Returns an error message, or null.
  Future<String?> setFakePin(String code) async {
    if (code.trim().length < 4) return 'Use at least 4 characters';
    // It must not open the real vault.
    if (pinMode && await PinService.quickVerify(code) != null) {
      return 'This is your real PIN — choose a different one';
    }
    final blob = await VaultStore.readBlob();
    if (blob != null &&
        await QuickUnlockService.keyFor(code, CryptoService.saltFromBlob(blob)) !=
            null) {
      return 'This is your real password — choose a different one';
    }
    await DecoyService.set(code);
    fakePinSet = true;
    notifyListeners();
    return null;
  }

  Future<void> clearFakePin() async {
    await DecoyService.clear();
    fakePinSet = false;
    notifyListeners();
  }

  /// Open the decoy vault: same encrypted storage, but only decoy items and
  /// passwords are shown. Uses the vault key cached by the last real unlock.
  Future<bool> _unlockDecoy() async {
    final blob = await VaultStore.readBlob();
    if (blob == null) return false;
    final salt = CryptoService.saltFromBlob(blob);
    final key = await QuickUnlockService.cachedKey(salt);
    if (key == null) return false;
    try {
      final json = await CryptoService.decryptString(blob, key);
      _entries = (jsonDecode(json) as List)
          .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return false;
    }
    _key = key;
    _salt = salt;
    decoy = true;
    status = VaultStatus.unlocked;
    errorMessage = null;
    await loadMedia();
    registerActivity();
    notifyListeners();
    await pullShared();
    return true;
  }

  // ---- App icon / disguise -----------------------------------------------------

  /// Current launcher icon id (see DisguiseService).
  String appIcon = 'default';
  bool get disguised => DisguiseService.isDisguise(appIcon);

  /// With a disguise icon, the lock screen stays hidden behind the disguise
  /// app until the secret code is entered there. Reset on every lock.
  bool disguiseRevealed = false;

  Future<void> setAppIcon(String id) async {
    await DisguiseService.setIcon(id);
    appIcon = id;
    notifyListeners();
  }

  /// Called by a disguise app with a code-like entry. Opens the vault straight
  /// away for the PIN, or shows the lock screen for the secret code. Returns
  /// true if the entry was accepted.
  Future<bool> tryDisguiseCode(String code) async {
    code = code.trim();
    if (status != VaultStatus.locked || !DisguiseService.looksLikeCode(code)) {
      return false;
    }
    if (await DisguiseService.lockedOut()) return false;
    if (await DecoyService.matches(code)) return _unlockDecoy();
    if (pinMode && await tryQuickPin(code)) {
      await DisguiseService.resetFails();
      return true;
    }
    if (await DisguiseService.checkCode(code)) {
      await DisguiseService.resetFails();
      disguiseRevealed = true;
      notifyListeners();
      return true;
    }
    await DisguiseService.noteFail();
    return false;
  }

  /// Back from the lock screen to the disguise app.
  void hideLockScreen() {
    if (!disguised || status != VaultStatus.locked) return;
    disguiseRevealed = false;
    notifyListeners();
  }

  // ---- PIN lock ---------------------------------------------------------------

  /// Switch to PIN lock. Returns an error message or null on success.
  Future<String?> enablePin(String pin, String masterPassword) async {
    if (pin.length < 4) return 'PIN must be at least 4 digits.';
    if (!await verifyMasterPassword(masterPassword)) {
      return 'Wrong master password.';
    }
    await PinService.enable(pin, masterPassword);
    pinMode = true;
    notifyListeners();
    return null;
  }

  Future<void> disablePin() async {
    await PinService.disable();
    pinMode = false;
    notifyListeners();
  }

  Future<void> setPinHint(String h) async {
    await PinService.setHint(h);
    pinHint = h.trim();
    notifyListeners();
  }

  /// Unlock with a PIN. Returns null on success, else a message.
  Future<String?> unlockWithPin(String pin) async {
    final wait = await PinService.lockoutLeft();
    if (wait > 0) return 'Too many tries. Wait $wait s.';
    if (await DecoyService.matches(pin)) {
      return await _unlockDecoy() ? null : 'Could not unlock';
    }
    final mp = await PinService.verify(pin);
    if (mp == null) {
      final w = await PinService.lockoutLeft();
      return w > 0 ? 'Too many tries. Wait $w s.' : 'Wrong PIN';
    }
    final ok = await unlock(mp);
    return ok ? null : 'Could not unlock';
  }

  /// Silent PIN check while typing; unlocks and returns true if [pin] is right.
  Future<bool> tryQuickPin(String pin) async {
    if (status != VaultStatus.locked || pin.length < 4) return false;
    if (await DecoyService.matches(pin)) return _unlockDecoy();
    final mp = await PinService.quickVerify(pin);
    if (mp == null) return false;
    return unlock(mp);
  }

  /// Security-question recovery for a forgotten PIN: unlock the vault and
  /// return true; the UI then asks for a new PIN.
  Future<bool> unlockWithAnswer(String answer) async {
    if (!await PinService.checkAnswer(answer)) return false;
    final mp = await PinService.storedMasterPassword();
    if (mp == null) return false;
    return unlock(mp);
  }

  // ---- Recovery key --------------------------------------------------------

  /// Turn on recovery: verify the master password, then store it encrypted
  /// under a freshly generated recovery key. Returns the recovery key to show
  /// the user once, or null if the password was wrong.
  Future<String?> enableRecovery(String masterPassword) async {
    if (!await verifyMasterPassword(masterPassword)) return null;
    final recoveryKey = RecoveryService.generateRecoveryKey();
    await RecoveryService.enable(masterPassword, recoveryKey);
    recoveryEnabled = true;
    notifyListeners();
    return recoveryKey;
  }

  Future<void> disableRecovery() async {
    await RecoveryService.disable();
    recoveryEnabled = false;
    notifyListeners();
  }

  /// Re-wrap the (new) master password under an EXISTING recovery key, so the
  /// same recovery key the user just used keeps working after they reset their
  /// password. Used by the recover-then-set-new-password flow.
  Future<void> setRecoveryWithKey(
      String masterPassword, String recoveryKey) async {
    await RecoveryService.enable(masterPassword, recoveryKey);
    recoveryEnabled = true;
    notifyListeners();
  }

  /// Recover using a recovery key: decrypt the stored master password and
  /// unlock the vault with it. Returns the recovered master password on
  /// success (so the UI can prompt for a new one), or null if the key is wrong.
  Future<String?> recoverWithKey(String recoveryKey) async {
    final mp = await RecoveryService.recoverMasterPassword(recoveryKey);
    if (mp == null) return null;
    final ok = await unlock(mp);
    return ok ? mp : null;
  }

  /// Wipe the vault completely and return to first-run setup. Used when the
  /// user forgot the password and has no recovery key — the only option left.
  Future<void> resetVault() async {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _key = null;
    _salt = null;
    _entries = [];
    media = [];
    _photoCache.clear();
    _thumbCache.clear();
    _photoFut.clear();
    _thumbFut.clear();
    await VaultStore.wipe();
    await MediaService.wipeAll();
    await BiometricService.disable();
    await RecoveryService.disable();
    await PinService.wipe();
    await QuickUnlockService.clear();
    // Without a vault there is no secret code, so drop any disguise too.
    await DisguiseService.clearCode();
    await DecoyService.clear();
    fakePinSet = false;
    await FolderLockService.clear();
    // Starting fresh: show the welcome tour again.
    onboarded = false;
    await SettingsService.setBool(PrefKeys.onboarded, false);
    _folderLocks = {};
    await IntruderService.clear();
    await IntruderService.setEnabled(false);
    intruderEnabled = false;
    if (disguised) {
      try {
        await DisguiseService.setIcon('default');
        appIcon = 'default';
      } catch (_) {}
    }
    disguiseRevealed = false;
    pinMode = false;
    pinHint = '';
    folders = {};
    recoveryEnabled = false;
    status = VaultStatus.needsSetup;
    notifyListeners();
  }

  // ---- Auto-lock -----------------------------------------------------------

  // While > 0, automatic locking (timer / app going to background) is paused.
  // Used while a system screen we opened is on top (photo picker, delete
  // confirmation, fingerprint prompt, save dialog) or while a video plays.
  int _lockHolds = 0;
  bool get lockSuspended => _lockHolds > 0;

  void holdLock() {
    _lockHolds++;
    _autoLockTimer?.cancel();
  }

  void releaseLock() {
    if (_lockHolds > 0) _lockHolds--;
    if (_lockHolds == 0) registerActivity();
  }

  void registerActivity() {
    if (status != VaultStatus.unlocked || lockSuspended) return;
    _autoLockTimer?.cancel();
    if (autoLockSeconds <= 0) return; // "Never": lock only manually / on leaving
    _autoLockTimer = Timer(Duration(seconds: autoLockSeconds), lock);
  }

  /// Lock the vault. Automatic callers (timer, backgrounding) are ignored
  /// while a hold is active; pass [force] for an explicit "Lock now".
  void lock({bool force = false}) {
    if (lockSuspended && !force) return;
    if (force) _lockHolds = 0;
    disguiseRevealed = false;
    decoy = false;
    _openedFolders.clear();
    // Shared files nobody confirmed must not stay unencrypted.
    if (pendingShared.isNotEmpty) discardShared();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _key = null;
    _salt = null;
    _entries = [];
    media = [];
    _photoCache.clear();
    _thumbCache.clear();
    _photoFut.clear();
    _thumbFut.clear();
    if (status != VaultStatus.needsSetup) {
      status = VaultStatus.locked;
    }
    notifyListeners();
  }

  // ---- Media (hidden photos / videos) --------------------------------------

  Future<void> loadMedia() async {
    media = await MediaService.loadIndex();
    folders = await MediaService.loadFolders();
    notifyListeners();
  }

  /// Add images (photos or web images) held as decodable bytes.
  /// Each item is (fileName, bytes).
  Future<int> addImages(List<(String, Uint8List)> items,
      {String category = MediaCat.photo, String folder = ''}) async {
    final added = <MediaItem>[];
    for (final it in items) {
      added.add(await MediaService.addPhotoBytes(
          bytes: it.$2,
          name: it.$1,
          category: category,
          folder: folder,
          space: space,
          save: false));
    }
    await MediaService.appendMany(added); // one index write for all
    media = await MediaService.loadIndex();
    notifyListeners();
    return items.length;
  }

  /// Add videos / audio from FILES, streamed in chunks (any size).
  /// Each item is (fileName, file, thumbnailJpegBytes).
  Future<int> addFiles(
    List<(String, File, Uint8List)> items, {
    required String category,
    String folder = '',
    void Function(int index, double progress)? onProgress,
  }) async {
    final added = <MediaItem>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      added.add(await MediaService.addStreamedFile(
        src: it.$2,
        type: MediaCat.typeOf(category),
        category: category,
        folder: folder,
        name: it.$1,
        thumbBytes: it.$3,
        onProgress: (p) => onProgress?.call(i, p),
        space: space,
        save: false,
      ));
    }
    await MediaService.appendMany(added); // one index write for all
    media = await MediaService.loadIndex();
    notifyListeners();
    return items.length;
  }

  // ---- Folders -----------------------------------------------------------------

  Future<String?> createFolder(String cat, String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Enter a folder name';
    if (foldersOf(cat).contains(n)) return 'A folder with this name exists';
    final k = _fk(cat);
    folders = {...folders, k: [...?folders[k], n]};
    await MediaService.saveFolders(folders);
    notifyListeners();
    return null;
  }

  Future<String?> renameFolder(String cat, String from, String to) async {
    final n = to.trim();
    if (n.isEmpty) return 'Enter a folder name';
    if (from.isEmpty) return 'The main folder cannot be renamed';
    if (foldersOf(cat).contains(n)) return 'A folder with this name exists';
    final k = _fk(cat);
    folders = {
      ...folders,
      k: [for (final f in folders[k] ?? const <String>[]) f == from ? n : f],
    };
    if (!(folders[k] ?? const []).contains(n)) {
      folders[k] = [...?folders[k], n];
    }
    await MediaService.saveFolders(folders);
    final ids = media
        .where((m) =>
            m.space == space && m.category == cat && m.folder == from)
        .map((m) => m.id)
        .toSet();
    await MediaService.updateMany(ids, (m) => m.copyWith(folder: n));
    _folderLocks = await FolderLockService.rename(_flKey(cat, from), _flKey(cat, n));
    media = await MediaService.loadIndex();
    notifyListeners();
    return null;
  }

  /// Delete a folder: its items go to the Recycle Bin.
  Future<String?> deleteFolder(String cat, String name) async {
    if (name.isEmpty) return 'The main folder cannot be deleted';
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = itemsOf(cat, folder: name).map((m) => m.id).toSet();
    await MediaService.updateMany(
        ids, (m) => m.copyWith(deletedAt: now, folder: ''));
    final k = _fk(cat);
    folders = {
      ...folders,
      k: [for (final f in folders[k] ?? const <String>[]) if (f != name) f],
    };
    await MediaService.saveFolders(folders);
    _folderLocks = await FolderLockService.remove(_flKey(cat, name));
    media = await MediaService.loadIndex();
    notifyListeners();
    return null;
  }

  Future<void> moveToFolder(Iterable<MediaItem> items, String folder) async {
    await MediaService.updateMany(
        items.map((m) => m.id).toSet(), (m) => m.copyWith(folder: folder));
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  // ---- Unhide / scan ---------------------------------------------------------------

  /// Put photos / videos / audio back on the phone and remove them from the
  /// vault. Returns how many were restored.
  Future<int> unhide(Iterable<MediaItem> items,
      {void Function(int done, int total)? onProgress}) async {
    final list = items.toList();
    final done = <MediaItem>[];
    holdLock();
    try {
      for (final m in list) {
        onProgress?.call(done.length, list.length);
        if (await MediaService.restoreToGallery(m)) {
          done.add(m);
          _forget(m.id);
        }
      }
      await MediaService.purgeMany(done); // one index write for all
    } finally {
      releaseLock();
    }
    final n = done.length;
    media = await MediaService.loadIndex();
    notifyListeners();
    return n;
  }

  /// Recover lost media: bring back encrypted files missing from the index,
  /// drop broken entries and remove leftover temp files.
  Future<RecoverReport> recoverLostMedia() async {
    holdLock(); // can take a while on a big vault
    try {
      final r = await MediaService.recoverLost();
      _photoCache.clear();
      _thumbCache.clear();
      _photoFut.clear();
      _thumbFut.clear();
      await loadMedia();
      return r;
    } finally {
      releaseLock();
    }
  }


  void _forget(String id) {
    _photoCache.remove(id);
    _thumbCache.remove(id);
    _photoFut.remove(id);
    _thumbFut.remove(id);
  }

  /// Move an item to the recycle bin (soft delete).
  Future<void> deleteMedia(MediaItem item) async {
    await MediaService.setDeleted(
        item.id, DateTime.now().millisecondsSinceEpoch);
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  /// Restore an item from the recycle bin.
  Future<void> restoreMedia(MediaItem item) async {
    await MediaService.setDeleted(item.id, 0);
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  /// Permanently delete a single trashed item.
  Future<void> purgeMedia(MediaItem item) async {
    await MediaService.purge(item);
    _photoCache.remove(item.id);
    _thumbCache.remove(item.id);
    _photoFut.remove(item.id);
    _thumbFut.remove(item.id);
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  /// "Delete permanently" from the Recycle Bin. The files are kept (still
  /// encrypted) for MediaService.keepErasedDays and can be brought back from
  /// Recover lost media until then.
  Future<void> eraseMedia(List<MediaItem> items) async {
    await MediaService.eraseMany(items);
    for (final item in items) {
      _forget(item.id);
    }
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  /// Empty the Recycle Bin (recoverable for a while, see [eraseMedia]).
  Future<void> emptyTrash() => eraseMedia(trash);

  /// Bring items deleted from the Recycle Bin back into it.
  Future<void> restoreErased(List<MediaItem> items) async {
    await MediaService.restoreErased(items);
    media = await MediaService.loadIndex();
    registerActivity();
    notifyListeners();
  }

  // The same Future is returned for an id, so FutureBuilders don't restart
  // (and flash blank) every time the grid rebuilds.
  final Map<String, Future<Uint8List>> _photoFut = {};
  final Map<String, Future<Uint8List>> _thumbFut = {};

  /// Decrypted full bytes for a photo, cached in memory while unlocked.
  Future<Uint8List> photoBytes(MediaItem item) =>
      _photoFut.putIfAbsent(item.id, () async {
        final cached = _photoCache[item.id];
        if (cached != null) return cached;
        final b = await MediaService.readBytes(item);
        _photoCache[item.id] = b;
        return b;
      });

  /// Grid thumbnail bytes (the photo itself, or a video's stored thumbnail).
  Future<Uint8List> thumbBytes(MediaItem item) =>
      _thumbFut.putIfAbsent(item.id, () async {
        final cached = _thumbCache[item.id];
        if (cached != null) return cached;
        final b = await MediaService.readThumb(item);
        _thumbCache[item.id] = b;
        return b;
      });

  /// Decrypt a video to a temp file for playback (caller deletes it).
  Future<File> decryptVideoToTemp(MediaItem item) =>
      MediaService.decryptToTemp(item);

  Future<File> decryptToTemp(MediaItem item) =>
      MediaService.decryptToTemp(item);

  // ---- Create / unlock -----------------------------------------------------

  Future<bool> createVault(String masterPassword) async {
    errorMessage = null;
    try {
      final salt = CryptoService.newSalt();
      final key = await CryptoService.deriveKey(masterPassword, salt);
      _key = key;
      _salt = salt;
      _entries = [];
      await _persist();
      await QuickUnlockService.remember(masterPassword, salt, key);
      status = VaultStatus.unlocked;
      await loadMedia();
      registerActivity();
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Could not create vault: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlock(String masterPassword) async {
    errorMessage = null;
    if (await DecoyService.matches(masterPassword)) return _unlockDecoy();
    try {
      final blob = await VaultStore.readBlob();
      if (blob == null) {
        status = VaultStatus.needsSetup;
        notifyListeners();
        return false;
      }
      if (await _unlockWithBlob(blob, masterPassword, quickOnly: false)) {
        return true;
      }
    } catch (_) {}
    errorMessage = 'Wrong master password.';
    notifyListeners();
    return false;
  }

  /// Silent, instant unlock attempt used while the user is still typing: only
  /// the cached-key path (no slow key derivation, no error message).
  Future<bool> tryQuickUnlock(String masterPassword) async {
    if (status != VaultStatus.locked || masterPassword.isEmpty) return false;
    if (await DecoyService.matches(masterPassword)) return _unlockDecoy();
    try {
      final blob = await VaultStore.readBlob();
      if (blob == null) return false;
      return await _unlockWithBlob(blob, masterPassword, quickOnly: true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _unlockWithBlob(Map<String, dynamic> blob, String masterPassword,
      {required bool quickOnly}) async {
    final salt = CryptoService.saltFromBlob(blob);
    String? json;
    var key = await QuickUnlockService.keyFor(masterPassword, salt);
    if (key != null) {
      try {
        json = await CryptoService.decryptString(blob, key);
      } catch (_) {
        json = null; // stale cache — fall back to the full derivation
      }
    }
    if (json == null) {
      if (quickOnly) return false;
      key = await CryptoService.deriveKey(masterPassword, salt);
      json = await CryptoService.decryptString(blob, key); // throws if wrong
      await QuickUnlockService.remember(masterPassword, salt, key);
    }
    if (status == VaultStatus.unlocked) return true; // another path won
    final list = (jsonDecode(json) as List)
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    _key = key;
    _salt = salt;
    _entries = list;
    decoy = false;
    status = VaultStatus.unlocked;
    errorMessage = null;
    _wrongInRow = 0;
    _photosThisSeries = 0;
    newIntrusions = await IntruderService.unseen();
    // Really delete Recycle-Bin deletions older than the keep period.
    await MediaService.expireErased();
    await loadMedia();
    registerActivity();
    notifyListeners();
    await pullShared();
    // A wrong try just before the right one may still be taking its photo;
    // once it is saved, refresh so the photo and the alert show up.
    IntruderService.idle().then((_) async {
      if (!isUnlocked) return;
      final n = await IntruderService.unseen();
      media = await MediaService.loadIndex();
      if (n > newIntrusions) newIntrusions = n;
      notifyListeners();
    });
    return true;
  }

  /// Verify a master password against the stored vault without changing state.
  /// Used when enabling biometric unlock.
  Future<bool> verifyMasterPassword(String masterPassword) async {
    try {
      final blob = await VaultStore.readBlob();
      if (blob == null) return false;
      final salt = CryptoService.saltFromBlob(blob);
      final key = await CryptoService.deriveKey(masterPassword, salt);
      await CryptoService.decryptString(blob, key); // throws if wrong
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Change the master password: verify the current one, then re-encrypt the
  /// vault with a fresh key derived from the new password + a new salt.
  /// Returns null on success, or an error message.
  Future<String?> changeMasterPassword(String current, String newPw) async {
    if (newPw.length < 8) return 'New password must be at least 8 characters.';
    try {
      // Decrypt the stored vault with the current password. This both verifies
      // the current password AND gives us the real entries to re-encrypt, so
      // we never depend on (possibly cleared) in-memory state — an auto-lock
      // mid-flow can no longer wipe data.
      final blob = await VaultStore.readBlob();
      if (blob == null) return 'No vault to change.';
      final oldSalt = CryptoService.saltFromBlob(blob);
      final oldKey = await CryptoService.deriveKey(current, oldSalt);
      String json;
      try {
        json = await CryptoService.decryptString(blob, oldKey);
      } catch (_) {
        return 'Current password is wrong.';
      }
      final entries = (jsonDecode(json) as List)
          .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      // Re-encrypt the SAME entries under a fresh key + salt.
      final newSalt = CryptoService.newSalt();
      final newKey = await CryptoService.deriveKey(newPw, newSalt);
      final newBlob = await CryptoService.encryptString(json, newKey, newSalt);
      await VaultStore.writeBlob(newBlob);
      await QuickUnlockService.remember(newPw, newSalt, newKey);

      // Keep in-memory state consistent if the vault is (or was) unlocked.
      _key = newKey;
      _salt = newSalt;
      _entries = entries;

      // If biometric unlock is on, update the stored password too.
      if (await BiometricService.isEnabled()) {
        await BiometricService.enable(newPw);
      }
      await PinService.updateMasterPassword(newPw);
      // The recovery blob wrapped the OLD password, so it is now stale.
      // Turn recovery off; the user can set up a fresh recovery key.
      if (await RecoveryService.isEnabled()) {
        await RecoveryService.disable();
        recoveryEnabled = false;
      }
      registerActivity();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Could not change password: $e';
    }
  }

  Future<void> _persist() async {
    if (_key == null || _salt == null) return;
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    final blob = await CryptoService.encryptString(json, _key!, _salt!);
    await VaultStore.writeBlob(blob);
  }

  // ---- Entry CRUD ----------------------------------------------------------

  Future<void> upsertEntry(VaultEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx < 0) entry.space = space;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (idx >= 0) {
      _entries[idx] = entry;
    } else {
      _entries.add(entry);
    }
    await _persist();
    registerActivity();
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _persist();
    registerActivity();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final e = _entries.firstWhere((x) => x.id == id);
    e.pinned = !e.pinned;
    await _persist();
    registerActivity();
    notifyListeners();
  }

  /// Entries filtered by category ('All' = every) and search query,
  /// pinned first, then most-recently-updated.
  List<VaultEntry> view({String category = 'All', String query = ''}) {
    final q = query.trim().toLowerCase();
    final list = _entries.where((e) {
      if (e.space != space) return false;
      final catOk = category == 'All' || e.category == category;
      final qOk = q.isEmpty ||
          e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q);
      return catOk && qOk;
    }).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  // ---- Backup --------------------------------------------------------------

  /// Replace the password vault with an OLD passwords-only backup file. The
  /// user then unlocks with that backup's master password.
  Future<bool> restoreOldBackupFile(File file) async {
    final blob = await BackupService.readOldBackup(file);
    if (blob == null) return false;
    await VaultStore.writeBlob(blob);
    lock(force: true);
    status = VaultStatus.locked;
    notifyListeners();
    return true;
  }

  // ---- Full backup (passwords + all media) -----------------------------------------

  static const _mediaCh = MethodChannel('kryvo/media');

  // ---- Share to Kryvo -----------------------------------------------------------

  /// Files shared from another app, waiting for the user to confirm.
  /// Each is (path in Kryvo's cache, file name, mime type).
  List<(String, String, String)> pendingShared = [];

  Future<void> pullShared() async {
    try {
      final list = await _mediaCh.invokeMethod<List<Object?>>('takeShared') ?? [];
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        pendingShared.add((m['path'] as String, m['name'] as String,
            (m['mime'] as String?) ?? ''));
      }
      if (list.isNotEmpty) notifyListeners();
    } catch (_) {}
  }

  static String _catForShared(String mime, String name) {
    final n = name.toLowerCase();
    if (mime.startsWith('video/') ||
        RegExp(r'\.(mp4|mkv|mov|3gp|webm|avi)$').hasMatch(n)) {
      return MediaCat.video;
    }
    if (mime.startsWith('audio/') ||
        RegExp(r'\.(mp3|m4a|aac|wav|ogg|opus|flac|amr)$').hasMatch(n)) {
      return MediaCat.audio;
    }
    return MediaCat.photo;
  }

  /// Encrypt the shared files into the vault (photos → Safe Photo, etc.).
  /// Returns how many were added.
  Future<int> importShared({void Function(String status)? onProgress}) async {
    final files = List.of(pendingShared);
    pendingShared = [];
    final byCat = <String, List<(String, File, Uint8List)>>{};
    for (final f in files) {
      byCat
          .putIfAbsent(_catForShared(f.$3, f.$2), () => [])
          .add((f.$2, File(f.$1), Uint8List(0)));
    }
    var n = 0;
    holdLock();
    try {
      for (final e in byCat.entries) {
        n += await addFiles(e.value,
            category: e.key,
            onProgress: (i, p) => onProgress?.call(
                'Encrypting ${n + i + 1} of ${files.length}…'));
      }
    } finally {
      releaseLock();
      await _deleteShared(files);
    }
    return n;
  }

  /// Throw away shared files the user didn't want.
  Future<void> discardShared() async {
    final files = List.of(pendingShared);
    pendingShared = [];
    await _deleteShared(files);
    notifyListeners();
  }

  Future<void> _deleteShared(List<(String, String, String)> files) async {
    for (final f in files) {
      try {
        await File(f.$1).delete();
      } catch (_) {}
    }
  }

  /// Make a full encrypted backup and let the user choose where to save it
  /// (Google Drive, Downloads…). Returns null on success, else a message.
  Future<String?> createFullBackup(
      {void Function(String status)? onProgress}) async {
    if (_key == null) return 'Unlock the vault first';
    holdLock();
    File? tmp;
    try {
      await _persist();
      final blob = await VaultStore.readBlob();
      if (blob == null) return 'Nothing to back up';
      tmp = await FullBackupService.create(
        vaultBlob: blob,
        vaultKey: _key!,
        media: await MediaService.loadIndex(),
        folders: folders,
        onProgress: (d, t) => onProgress?.call('Packing $d of $t files…'),
      );
      onProgress?.call('Choose where to save…');
      final d = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final saved = await _mediaCh.invokeMethod<bool>('saveFile', {
        'path': tmp.path,
        'name': 'kryvo-backup-${d.year}-${two(d.month)}-${two(d.day)}.kryvo',
      });
      return saved == true ? null : 'Backup not saved';
    } catch (e) {
      return 'Backup failed: $e';
    } finally {
      if (tmp != null && await tmp.exists()) await tmp.delete();
      releaseLock();
    }
  }

  /// Merge a full backup into this vault. Returns a summary; throws
  /// WrongPassword / FormatException.
  Future<String> restoreFullBackup(File file, String password,
      {void Function(String status)? onProgress}) async {
    holdLock();
    try {
      onProgress?.call('Checking the password…');
      final b = await FullBackupService.open(file, password);

      // Passwords: add the ones this vault doesn't have yet.
      final have = {for (final e in _entries) e.id};
      final newEntries = b.entries.where((e) => !have.contains(e.id)).toList();
      if (newEntries.isNotEmpty) {
        _entries = [..._entries, ...newEntries];
        await _persist();
      }

      // Media.
      final existing = {for (final m in await MediaService.loadIndex()) m.id};
      final added = await FullBackupService.importMedia(b,
          existing: existing,
          onProgress: (d, t) => onProgress?.call('Restoring $d of $t files…'));
      await MediaService.appendMany(added);

      // Folders.
      final merged = {for (final e in folders.entries) e.key: [...e.value]};
      for (final e in b.folders.entries) {
        final list = merged[e.key] ??= [];
        for (final f in e.value) {
          if (!list.contains(f)) list.add(f);
        }
      }
      folders = merged;
      await MediaService.saveFolders(folders);
      await loadMedia();
      return 'Restored ${added.length} file${added.length == 1 ? '' : 's'} and '
          '${newEntries.length} password${newEntries.length == 1 ? '' : 's'} ✔';
    } finally {
      releaseLock();
    }
  }
}
