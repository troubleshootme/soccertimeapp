import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../hive_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class BackupManager {
  // Singleton pattern
  static final BackupManager _instance = BackupManager._internal();
  factory BackupManager() => _instance;
  BackupManager._internal();

  // Backup file name with format pattern for timestamps
  static const String backupFileNameBase = 'soccertime_backup';
  static const String backupFileExt = 'json';

  // Generate a backup filename with timestamp
  String _getBackupFileName() {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.millisecond.toString().padLeft(3, '0')}';
    return '${backupFileNameBase}_$timestamp.$backupFileExt';
  }

  /// Request storage permission for Android based on API level
  Future<bool> _requestStoragePermission() async {
    try {
      // Get device info to determine Android version
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;
      
      if (sdkVersion >= 33) { // Android 13 (Tiramisu) and above
        // For Android 13+, we need these media permissions
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        final audio = await Permission.audio.request();
        
        // For full storage access (writes to Download folder) we need MANAGE_EXTERNAL_STORAGE
        final manageStorage = await Permission.manageExternalStorage.request();
        
        print('Android 13+ permissions: photos=${photos.isGranted}, videos=${videos.isGranted}, audio=${audio.isGranted}, manageStorage=${manageStorage.isGranted}');
        
        // If MANAGE_EXTERNAL_STORAGE is not granted, we need to show special dialog
        if (!manageStorage.isGranted) {
          return false;
        }
        
        return true;
      } 
      else if (sdkVersion >= 30) { // Android 11 and 12
        // For Android 11 & 12, we need MANAGE_EXTERNAL_STORAGE for write access
        final manageStorage = await Permission.manageExternalStorage.request();
        print('Android 11-12 permissions: manageStorage=${manageStorage.isGranted}');
        
        if (!manageStorage.isGranted) {
          return false;
        }
        
        return true;
      } 
      else { // Android 10 and below
        // For Android 10 and below, we use legacy storage permissions
        final storage = await Permission.storage.request();
        print('Android 10 or below permissions: storage=${storage.isGranted}');
        
        if (!storage.isGranted) {
          return false;
        }
        
        return true;
      }
    } catch (e) {
      print('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Creates a backup of all session data and saves it directly to the Downloads folder
  Future<String?> backupSessions(BuildContext context) async {
    try {
      // Request permission first
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Permission Required'),
            content: Text('Storage permission is required to access backup files. Please grant the permission in Settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).primaryColor,
                ),
                child: Text('Open Settings'),
              ),
            ],
          ),
        );
        throw Exception('Storage permission denied');
      }
      
      // Initialize the database
      await HiveSessionDatabase.instance.init();
      
      // Get all sessions
      final sessions = await HiveSessionDatabase.instance.getAllSessions();
      
      // For each session, get its players and settings
      final backupData = <Map<String, dynamic>>[];
      
      for (final session in sessions) {
        final sessionId = session['id'];
        final players = await HiveSessionDatabase.instance.getPlayersForSession(sessionId);
        final settings = await HiveSessionDatabase.instance.getSessionSettings(sessionId);
        
        backupData.add({
          'session': session,
          'players': players,
          'settings': settings,
        });
      }
      
      // Convert to JSON with nice formatting for better readability
      final jsonData = JsonEncoder.withIndent('  ').convert(backupData);
      
      // Generate a unique filename with timestamp
      final backupFileName = _getBackupFileName();
      
      // Primary locations to try saving the backup
      final primaryPaths = [
        '/storage/emulated/0/Download',
        '/sdcard/Download',
        '/storage/emulated/0/Downloads',
        '/sdcard/Downloads',
      ];
      
      // Try each path until one works
      String? filePath;
      Exception? lastError;
      bool backupSaved = false;
      
      for (final path in primaryPaths) {
        // Stop if we already saved the file
        if (backupSaved) break;
        
        try {
          final downloadDir = Directory(path);
          if (await downloadDir.exists()) {
            print('Trying to save backup to: $path');
            final backupFile = File('$path/$backupFileName');
            
            await backupFile.writeAsString(jsonData);
            filePath = backupFile.path;
            print('Backup saved to: $filePath');
            backupSaved = true;
            break; // Exit loop after successful save
          }
        } catch (e) {
          print('Failed to save to $path: $e');
          lastError = e as Exception;
        }
      }
      
      // If we couldn't save to any of the primary paths, try one more fallback location
      if (!backupSaved) {
        try {
          final documentsDir = await getApplicationDocumentsDirectory();
          print('Trying to save to documents directory: ${documentsDir.path}');
          final backupFile = File('${documentsDir.path}/$backupFileName');
          
          await backupFile.writeAsString(jsonData);
          filePath = backupFile.path;
          print('Backup saved to documents directory: $filePath');
          backupSaved = true;
        } catch (e) {
          print('Failed to save to documents directory: $e');
        }
      }
      
      // Check if we successfully saved the backup
      if (!backupSaved) {
        // If no file was saved, throw an error
        throw lastError ?? Exception('Could not save backup file to any location');
      }
      
      _showBackupSuccess(context, filePath!);
      return filePath;
    } catch (e) {
      print('Error creating backup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
  
  /// Shows a dialog to select which backup file to restore
  Future<Map<String, dynamic>?> _showBackupSelectionDialog(BuildContext context, List<File> backups) async {
    // Format date from filename for display
    String formatBackupDate(String filePath) {
      final fileName = filePath.split('/').last;
      
      // Match the new timestamp format that includes seconds and milliseconds
      final dateMatch = RegExp(r'(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_?(\d{3})?').firstMatch(fileName);
      
      if (dateMatch != null) {
        final year = dateMatch.group(1);
        final month = dateMatch.group(2);
        final day = dateMatch.group(3);
        final hour = dateMatch.group(4);
        final minute = dateMatch.group(5);
        final second = dateMatch.group(6);
        final millisecond = dateMatch.group(7) ?? '';
        
        if (millisecond.isNotEmpty) {
          return '$year-$month-$day $hour:$minute:$second.$millisecond';
        } else {
          return '$year-$month-$day $hour:$minute:$second';
        }
      }
      
      // Fallback if pattern doesn't match
      return fileName;
    }
    
    bool deleteOtherBackups = false;
    
    return await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Select Backup to Restore'),
          content: Container(
            width: double.maxFinite,
            height: 350, // Increased height to accommodate checkbox
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: backups.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final backup = backups[index];
                      final fileName = backup.path.split('/').last;
                      final formattedDate = formatBackupDate(fileName);
                      
                      // Get file size information for display
                      int fileSize = 0;
                      try {
                        fileSize = backup.lengthSync();
                      } catch (e) {
                        print('Error getting file size: $e');
                      }
                      
                      // Format file size
                      String formattedSize = '';
                      if (fileSize < 1024) {
                        formattedSize = '$fileSize B';
                      } else if (fileSize < 1024 * 1024) {
                        formattedSize = '${(fileSize / 1024).toStringAsFixed(1)} KB';
                      } else {
                        formattedSize = '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
                      }
                      
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text('Backup from $formattedDate'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fileName, 
                                  style: TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              Text('Size: $formattedSize',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.of(context).pop({
                            'backup': backup,
                            'deleteOthers': deleteOtherBackups
                          }),
                        ),
                      );
                    },
                  ),
                ),
                CheckboxListTile(
                  title: Text(
                    'Restore this backup and DELETE all other backups',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: deleteOtherBackups,
                  onChanged: (value) {
                    setState(() {
                      deleteOtherBackups = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Restores session data from a backup file in Downloads folder
  Future<bool> restoreSessions(BuildContext context) async {
    try {
      // Request permission first
      final hasPermission = await _requestStoragePermission();
      if (hasPermission) {
        
        // Find available backup files in all possible paths
        final availableBackups = await _findBackupFiles();
        
        if (availableBackups.isEmpty) {
          // Show error that no backup files were found
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No backup files found in Downloads folder.'),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        
        // Sort backups by date (newest first)
        availableBackups.sort((a, b) => b.path.compareTo(a.path));
        
        // Show dialog to select which backup to restore
        final result = await _showBackupSelectionDialog(context, availableBackups);
        if (result == null) {
          return false; // User canceled
        }
        
        final selectedBackup = result['backup'] as File;
        final deleteOtherBackups = result['deleteOthers'] as bool;
        
        // Read the selected backup file
        final backupContent = await selectedBackup.readAsString();
        
        // Parse JSON
        late List<dynamic> backupData;
        try {
          backupData = jsonDecode(backupContent);
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid backup file format. Please check the content and try again.')),
          );
          return false;
        }
        
        // Confirm with user before proceeding
        final shouldRestore = await _showRestoreConfirmation(context);
        if (!shouldRestore) {
          return false;
        }
        
        // Initialize database
        await HiveSessionDatabase.instance.init();
        
        // Clear existing data
        await HiveSessionDatabase.instance.clearAllSessions();
        
        // Restore each session with its players and settings
        int restoredSessions = 0;
        for (final item in backupData) {
          final session = item['session'];
          final players = item['players'];
          final settings = item['settings'];
          
          // Create session
          final sessionId = await HiveSessionDatabase.instance.insertSession(session['name']);
          
          // Restore players
          for (final player in players) {
            await HiveSessionDatabase.instance.insertPlayer(
              sessionId, 
              player['name'], 
              player['timer_seconds'] ?? 0,
            );
          }
          
          // Restore settings
          if (settings != null) {
            await HiveSessionDatabase.instance.saveSessionSettings(sessionId, settings);
          }
          
          restoredSessions++;
        }
        
        // Delete other backups if requested
        if (deleteOtherBackups) {
          final backups = await _findBackupFiles();
          int deletedCount = 0;
          
          // Get information about the selected backup file
          final selectedStat = await selectedBackup.stat();
          final selectedIdentifier = '${selectedStat.size}_${selectedStat.modified.millisecondsSinceEpoch}_${selectedStat.mode}';
          
          // Don't delete the backup we just restored from or its symlinks
          for (var backup in backups) {
            try {
              // Check if it's the same physical file as our selected backup
              final backupStat = await backup.stat();
              final backupIdentifier = '${backupStat.size}_${backupStat.modified.millisecondsSinceEpoch}_${backupStat.mode}';
              
              if (backup.path != selectedBackup.path) {
                // If it's not the same path AND it's not the same physical file, delete it
                if (backupIdentifier != selectedIdentifier) {
                  await backup.delete();
                  print('Deleted backup: ${backup.path}');
                  deletedCount++;
                } else {
                  print('Skipping deletion of backup at ${backup.path} as it\'s a symlink to the selected backup');
                }
              } else {
                print('Preserving the restored backup: ${backup.path}');
              }
            } catch (e) {
              print('Error checking or deleting backup ${backup.path}: $e');
            }
          }
          
          print('Deleted $deletedCount backup files, kept restored backup and its symlinks.');
        }
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(deleteOtherBackups
              ? 'Successfully restored $restoredSessions sessions and deleted ${availableBackups.length - 1} other backups'
              : 'Successfully restored $restoredSessions sessions'),
            duration: Duration(seconds: 1),
          ),
        );
        
        //print('Successfully restored $restoredSessions sessions');
        return true;
      }
      
      return false;
    } catch (e) {
      print('Error restoring backup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error restoring backup: $e')),
      );
      return false;
    }
  }
  
  /// Find all backup files in potential download folders
  Future<List<File>> _findBackupFiles() async {
    List<File> backups = [];
    Set<String> uniqueFilePaths = {}; // Track unique paths
    Set<String> uniqueFileIdentifiers = {}; // Track unique files by stat info
    
    // Try multiple paths for Downloads folder with more comprehensive options
    final paths = [
      '/storage/emulated/0/Download',    // Primary storage path
      '/sdcard/Download',                // Alternative path
      '/storage/emulated/0/Downloads',   // Another common path
      '/sdcard/Downloads',               // Alternative path
      '/storage/self/primary/Download',  // Another Android path variant
      '/storage/emulated/0/DCIM',        // DCIM folder
      '/sdcard/DCIM',                    // Alternative DCIM path
    ];
    
    // Try shared storage paths for Android 10+
    try {
      if (Platform.isAndroid) {
        // Try to get all available external storage directories
        final externalStorageDirs = await getExternalStorageDirectories();
        if (externalStorageDirs != null) {
          paths.addAll(externalStorageDirs.map((dir) => dir.path));
        }
      }
    } catch (e) {
      print('Error getting external storage directories: $e');
    }
    
    // Also try to get the app's documents directory
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      paths.add(documentsDir.path);
    } catch (e) {
      print('Error getting documents directory: $e');
    }
    
    // Check root paths
    try {
      final rootPaths = [
        '/storage/emulated/0',
        '/sdcard',
      ];
      paths.addAll(rootPaths);
    } catch (e) {
      print('Error adding root paths: $e');
    }
    
    // Helper to check if file is a duplicate or symlink
    Future<bool> isUniqueFile(File file) async {
      try {
        // Skip if we've already seen this exact path
        if (uniqueFilePaths.contains(file.path)) {
          print('Skipping duplicate path: ${file.path}');
          return false;
        }
        uniqueFilePaths.add(file.path);
        
        // Get file stats to identify unique files
        final stat = await file.stat();
        
        // Create a unique identifier using size, modified time and mode
        // This helps detect when two paths point to the same physical file
        final fileIdentifier = '${stat.size}_${stat.modified.millisecondsSinceEpoch}_${stat.mode}';
        
        if (uniqueFileIdentifiers.contains(fileIdentifier)) {
          print('Detected symlink or hard link: ${file.path}');
          return false;
        }
        
        uniqueFileIdentifiers.add(fileIdentifier);
        return true;
      } catch (e) {
        print('Error checking file uniqueness: $e');
        // If we can't check, treat as unique to be safe
        return true;
      }
    }
    
    // Check each path for backup files
    for (final path in paths) {
      try {
        print('Searching for backups in: $path');
        final dir = Directory(path);
        if (await dir.exists()) {
          // List all files in directory
          final entities = await dir.list().toList();
          
          // Filter for backup files
          for (final entity in entities) {
            if (entity is File && 
                entity.path.contains(backupFileNameBase) && 
                entity.path.endsWith(backupFileExt)) {
              
              // Only add the file if it's not a duplicate or symlink
              if (await isUniqueFile(entity)) {
                print('Found unique backup file: ${entity.path}');
                backups.add(entity);
              }
            }
          }
        }
      } catch (e) {
        print('Error listing files in $path: $e');
      }
    }
    
    // If no backups found, try a deeper search in the Downloads/DCIM folders
    if (backups.isEmpty) {
      final deepSearchPaths = paths.where((path) => 
          path.contains('Download') || 
          path.contains('DCIM') || 
          path.endsWith('/0') || 
          path.endsWith('sdcard')).toList();
      
      for (final path in deepSearchPaths) {
        try {
          print('Deep searching in: $path');
          final dir = Directory(path);
          if (await dir.exists()) {
            await _searchDirectoryForBackups(dir, backups, uniqueFilePaths, uniqueFileIdentifiers, 0, 2);
          }
        } catch (e) {
          print('Error deep searching in $path: $e');
        }
      }
    }
    
    print('Total unique backup files found: ${backups.length}');
    for (final backup in backups) {
      print('  ${backup.path}');
    }
    
    return backups;
  }
  
  // Helper to recursively search directories for backup files
  Future<void> _searchDirectoryForBackups(
    Directory dir, 
    List<File> backups, 
    Set<String> uniqueFilePaths,
    Set<String> uniqueFileIdentifiers,
    int currentDepth, 
    int maxDepth
  ) async {
    if (currentDepth > maxDepth) return;
    
    try {
      final entities = await dir.list().toList();
      
      // Helper to check if file is a duplicate or symlink
      Future<bool> isUniqueFile(File file) async {
        try {
          // Skip if we've already seen this exact path
          if (uniqueFilePaths.contains(file.path)) {
            print('Skipping duplicate path: ${file.path}');
            return false;
          }
          uniqueFilePaths.add(file.path);
          
          // Get file stats to identify unique files
          final stat = await file.stat();
          
          // Create a unique identifier using size, modified time and mode
          // This helps detect when two paths point to the same physical file
          final fileIdentifier = '${stat.size}_${stat.modified.millisecondsSinceEpoch}_${stat.mode}';
          
          if (uniqueFileIdentifiers.contains(fileIdentifier)) {
            print('Detected symlink or hard link: ${file.path}');
            return false;
          }
          
          uniqueFileIdentifiers.add(fileIdentifier);
          return true;
        } catch (e) {
          print('Error checking file uniqueness: $e');
          // If we can't check, treat as unique to be safe
          return true;
        }
      }
      
      // Check files in this directory
      for (final entity in entities) {
        if (entity is File && 
            entity.path.contains(backupFileNameBase) && 
            entity.path.endsWith(backupFileExt)) {
          
          // Only add the file if it's not a duplicate or symlink
          if (await isUniqueFile(entity)) {
            print('Found unique backup file in deep search: ${entity.path}');
            backups.add(entity);
          }
        }
      }
      
      // Recursively check subdirectories
      if (currentDepth < maxDepth) {
        for (final entity in entities) {
          if (entity is Directory) {
            // Skip system directories
            if (!entity.path.contains('.thumbnails') && 
                !entity.path.contains('.cache') &&
                !entity.path.contains('/Android/data') &&
                !entity.path.contains('/Android/obb')) {
              await _searchDirectoryForBackups(
                entity, 
                backups, 
                uniqueFilePaths,
                uniqueFileIdentifiers,
                currentDepth + 1, 
                maxDepth
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error searching directory ${dir.path}: $e');
    }
  }
  
  /// Shows a confirmation dialog before restoring
  Future<bool> _showRestoreConfirmation(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore Sessions'),
        content: Text(
          'Restoring from backup will replace all current sessions. This cannot be undone. Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text('Restore'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Shows a dialog when backup is successful
  void showBackupSuccess(BuildContext context, String filePath) {
    _showBackupSuccess(context, filePath);
  }
  
  /// Internal method to show backup success dialog
  void _showBackupSuccess(BuildContext context, String filePath) {
    final fileName = filePath.split('/').last;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Backup Successful'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your data has been backed up successfully to:'),
              SizedBox(height: 8),
              Text(
                filePath,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'You can copy this file to a safe location or share it using the buttons below.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final file = File(filePath);
                if (await file.exists()) {
                  Share.shareXFiles(
                    [XFile(filePath)],
                    subject: 'Soccer Time App Backup',
                    text: 'Backup file: $fileName',
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('File not found. It may have been moved or deleted.')),
                  );
                }
              } catch (e) {
                print('Error sharing file: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error sharing file: $e')),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
            ),
            child: Text('Share'),
          ),
        ],
      ),
    );
  }
  
  /// Restore sessions from a backup file
  Future<String> restoreFromBackup(File backupFile, {bool deleteOtherBackups = false}) async {
    try {
      print('Restoring from backup file: ${backupFile.path}');
      final String jsonContent = await backupFile.readAsString();
      final Map<String, dynamic> backupData = json.decode(jsonContent);
      
      // Initialize the database
      final db = HiveSessionDatabase.instance;
      await db.init();
      
      // Clear existing data
      await db.clearAllSessions();
      
      // Restore sessions, players and settings
      int sessionCount = 0;
      
      // Backup format depends on the version, handle different formats
      if (backupData.containsKey('sessions')) {
        // Format: {sessions: [...], players: [...], settings: [...]}
        final sessions = backupData['sessions'] as List;
        final players = backupData['players'] as List;
        final settings = backupData['settings'] as List;
        
        // First create all sessions
        for (final sessionData in sessions) {
          final sessionId = sessionData['id'];
          final sessionName = sessionData['name'] ?? 'Restored Session';
          await db.updateSession({
            'id': sessionId,
            'name': sessionName,
            'created_at': sessionData['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
          });
          sessionCount++;
        }
        
        // Then restore players
        for (final playerData in players) {
          final sessionId = playerData['session_id'];
          final playerName = playerData['name'] ?? 'Player';
          final timerSeconds = playerData['timer_seconds'] ?? 0;
          await db.insertPlayer(sessionId, playerName, timerSeconds);
        }
        
        // Finally restore settings
        for (final settingData in settings) {
          final sessionId = settingData['session_id'];
          await db.saveSessionSettings(sessionId, settingData);
        }
      } else {
        // Array format: [{session: {...}, players: [...], settings: [...]}]
        final backupItems = backupData['backupData'] ?? backupData as List;
        
        for (final item in backupItems) {
          // Process each session with its players and settings
          final sessionData = item['session'];
          final sessionId = sessionData['id'];
          final sessionName = sessionData['name'] ?? 'Restored Session';
          
          // Create session
          await db.updateSession({
            'id': sessionId,
            'name': sessionName,
            'created_at': sessionData['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
          });
          sessionCount++;
          
          // Add players
          for (final playerData in item['players']) {
            final playerName = playerData['name'] ?? 'Player';
            final timerSeconds = playerData['timer_seconds'] ?? 0;
            await db.insertPlayer(sessionId, playerName, timerSeconds);
          }
          
          // Add settings
          if (item['settings'] != null) {
            await db.saveSessionSettings(sessionId, item['settings']);
          }
        }
      }

      // Delete other backups if requested
      if (deleteOtherBackups) {
        final backups = await _findBackupFiles();
        int deletedCount = 0;
        
        // Get information about the selected backup file
        final selectedStat = await backupFile.stat();
        final selectedIdentifier = '${selectedStat.size}_${selectedStat.modified.millisecondsSinceEpoch}_${selectedStat.mode}';
        
        // Don't delete the backup we just restored from or its symlinks
        for (var backup in backups) {
          try {
            // Check if it's the same physical file as our selected backup
            final backupStat = await backup.stat();
            final backupIdentifier = '${backupStat.size}_${backupStat.modified.millisecondsSinceEpoch}_${backupStat.mode}';
            
            if (backup.path != backupFile.path) {
              // If it's not the same path AND it's not the same physical file, delete it
              if (backupIdentifier != selectedIdentifier) {
                await backup.delete();
                print('Deleted backup: ${backup.path}');
                deletedCount++;
              } else {
                print('Skipping deletion of backup at ${backup.path} as it\'s a symlink to the selected backup');
              }
            } else {
              print('Preserving the restored backup: ${backup.path}');
            }
          } catch (e) {
            print('Error checking or deleting backup ${backup.path}: $e');
          }
        }
        
        print('Deleted $deletedCount backup files, kept restored backup and its symlinks.');
      }

      return 'Restoration successful! $sessionCount sessions restored.';
    } catch (e) {
      print('Error restoring from backup: $e');
      return 'Error: $e';
    }
  }
} 