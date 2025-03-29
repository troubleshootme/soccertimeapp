import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/match_log_screen.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _matchDurationController = TextEditingController(text: "90");
  final _targetDurationController = TextEditingController(text: "16");
  
  bool _enableMatchDuration = true;
  bool _enableTargetDuration = true;
  bool _enableSound = false;
  bool _enableVibration = true;
  String _matchSegments = "Halves";
  String _theme = "Dark";
  
  // Variables to track original values for change detection
  bool _originalEnableMatchDuration = true;
  bool _originalEnableTargetDuration = true;
  bool _originalEnableSound = false;
  bool _originalEnableVibration = true;
  String _originalMatchSegments = "Halves";
  String _originalMatchDuration = "90";
  String _originalTargetDuration = "16";
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    // Load values from AppState
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Set current values
    _enableMatchDuration = appState.session.enableMatchDuration;
    _enableTargetDuration = appState.session.enableTargetDuration;
    _enableSound = appState.session.enableSound;
    _enableVibration = appState.session.enableVibration;
    _matchSegments = appState.session.matchSegments == 2 ? "Halves" : "Quarters";
    _theme = appState.isDarkTheme ? "Dark" : "Light";
    _matchDurationController.text = (appState.session.matchDuration ~/ 60).toString();
    _targetDurationController.text = (appState.session.targetPlayDuration ~/ 60).toString();
    
    // Store original values for change detection
    _originalEnableMatchDuration = _enableMatchDuration;
    _originalEnableTargetDuration = _enableTargetDuration;
    _originalEnableSound = _enableSound;
    _originalEnableVibration = _enableVibration;
    _originalMatchSegments = _matchSegments;
    _originalMatchDuration = _matchDurationController.text;
    _originalTargetDuration = _targetDurationController.text;
    
    // Add listeners to detect changes
    _matchDurationController.addListener(_checkForChanges);
    _targetDurationController.addListener(_checkForChanges);
  }
  
  void _checkForChanges() {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDarkTheme = appState.isDarkTheme;
    
    final hasChanges = 
      _enableMatchDuration != _originalEnableMatchDuration ||
      _enableTargetDuration != _originalEnableTargetDuration ||
      _enableSound != _originalEnableSound ||
      _enableVibration != _originalEnableVibration ||
      _matchSegments != _originalMatchSegments ||
      _matchDurationController.text != _originalMatchDuration ||
      _targetDurationController.text != _originalTargetDuration ||
      (isDarkTheme ? "Dark" : "Light") != _theme;
    
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }
  
  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges) {
      final isDark = Provider.of<AppState>(context, listen: false).isDarkTheme;
      
      // Show confirmation dialog
      return await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
          title: Text(
            'Discard Changes?',
            style: TextStyle(
              color: isDark ? AppThemes.darkText : AppThemes.lightText,
              letterSpacing: 1.0,
            ),
          ),
          content: Text(
            'You have unsaved changes. Do you want to discard them?',
            style: TextStyle(
              color: isDark ? AppThemes.darkText : AppThemes.lightText,
              letterSpacing: 0.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Discard',
                style: TextStyle(
                  color: Colors.red,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ) ?? false; // Default to false if dialog is dismissed
    }
    
    return true; // Allow pop if no changes
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<AppState>(context).isDarkTheme;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final result = await _onWillPop();
          if (result) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
        appBar: AppBar(
          backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
          title: Text('Settings'),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _onWillPop()) {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 100), // Add padding at bottom for buttons
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Match Duration
                    _buildSettingRow(
                      "Match Duration",
                      Switch(
                        value: _enableMatchDuration,
                        activeColor: Colors.deepPurple,
                        activeTrackColor: Colors.deepPurple.withValues(alpha: 128),
                        onChanged: (value) {
                          setState(() {
                            _enableMatchDuration = value;
                          });
                          _checkForChanges();
                        },
                      ),
                      _enableMatchDuration ? TextField(
                        controller: _matchDurationController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          labelText: "Minutes",
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.deepPurple,
                            ),
                          ),
                        ),
                      ) : Container(),
                    ),
                    SizedBox(height: 8),
                    
                    // Match Segments - only visible when match duration is enabled
                    _enableMatchDuration ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Label (left side)
                        Expanded(
                          flex: 3,
                          child: Text(
                            "Match Segments",
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        // Empty space where the switch would be
                        SizedBox(width: 60),
                        // Dropdown aligned with the minutes field
                        Expanded(
                          flex: 2,
                          child: DropdownButton<String>(
                            value: _matchSegments,
                            isExpanded: true,
                            dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            underline: Container(
                              height: 1,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _matchSegments = newValue;
                                });
                                _checkForChanges();
                              }
                            },
                            items: <String>['Halves', 'Quarters']
                                .map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ) : Container(),
                    SizedBox(height: 8),
                    
                    // Target Play Duration
                    _buildSettingRow(
                      "Target Play\nDuration",
                      Switch(
                        value: _enableTargetDuration,
                        activeColor: Colors.deepPurple,
                        activeTrackColor: Colors.deepPurple.withValues(alpha: 128),
                        onChanged: (value) {
                          setState(() {
                            _enableTargetDuration = value;
                          });
                          _checkForChanges();
                        },
                      ),
                      _enableTargetDuration ? TextField(
                        controller: _targetDurationController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          labelText: "Minutes",
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.deepPurple,
                            ),
                          ),
                        ),
                      ) : Container(),
                    ),
                    SizedBox(height: 8),
                    
                    // Theme
                    _buildSettingRow(
                      "Dark Mode",
                      Switch(
                        value: Provider.of<AppState>(context).isDarkTheme,
                        activeColor: Colors.deepPurple,
                        activeTrackColor: Colors.deepPurple.withValues(alpha: 128),
                        onChanged: (value) {
                          setState(() {
                            // If current theme doesn't match desired value, toggle it
                            if (Provider.of<AppState>(context, listen: false).isDarkTheme != value) {
                              Provider.of<AppState>(context, listen: false).toggleTheme();
                              _theme = value ? "Dark" : "Light";
                            }
                          });
                          _checkForChanges();
                        },
                      ),
                      Container(), // No input field for theme
                    ),
                    SizedBox(height: 8),
                    
                    // Sound Settings
                    _buildSettingRow(
                      "Sound",
                      Switch(
                        value: _enableSound,
                        activeColor: Colors.deepPurple,
                        activeTrackColor: Colors.deepPurple.withValues(alpha: 128),
                        onChanged: (bool value) {
                          setState(() {
                            _enableSound = value;
                          });
                          _checkForChanges();
                        },
                      ),
                      Container(), // No input field for sound
                    ),
                    SizedBox(height: 8),

                    // Vibration Settings
                    _buildSettingRow(
                      "Vibration",
                      Switch(
                        value: _enableVibration,
                        activeColor: Colors.deepPurple,
                        activeTrackColor: Colors.deepPurple.withValues(alpha: 128),
                        onChanged: (bool value) {
                          setState(() {
                            _enableVibration = value;
                            // Update the session's vibration setting directly
                            final appState = Provider.of<AppState>(context, listen: false);
                            appState.session = appState.session.copyWith(enableVibration: value);
                          });
                          _checkForChanges();
                        },
                      ),
                      Container(), // No input field for vibration
                    ),
                    SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white24 : Colors.black12),
                    
                    // Match Log button
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.history),
                        label: Text(
                          "Match Log",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => MatchLogScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color.fromARGB(255, 0, 158, 179) : const Color.fromARGB(255, 0, 100, 100),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Fixed position Save Settings button at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SafeArea(
                  child: ElevatedButton(
                    onPressed: () {
                      // Save all settings
                      final appState = Provider.of<AppState>(context, listen: false);
                      
                      // Update match duration if the field has a valid value
                      final matchDuration = int.tryParse(_matchDurationController.text) ?? 90;
                      if (matchDuration > 0) {
                        appState.updateMatchDuration(matchDuration);
                      }
                      
                      // Update target duration if the field has a valid value
                      final targetDuration = int.tryParse(_targetDurationController.text) ?? 16;
                      if (targetDuration > 0) {
                        appState.updateTargetDuration(targetDuration);
                      }
                      
                      // Update other settings
                      appState.toggleMatchDuration(_enableMatchDuration);
                      appState.toggleTargetDuration(_enableTargetDuration);
                      appState.toggleSound(_enableSound);
                      appState.updateMatchSegments(_matchSegments == "Halves" ? 2 : 4);
                      
                      // Save all settings to the database
                      appState.saveSession();
                      
                      // Update original values to match current values
                      _originalEnableMatchDuration = _enableMatchDuration;
                      _originalEnableTargetDuration = _enableTargetDuration;
                      _originalEnableSound = _enableSound;
                      _originalEnableVibration = _enableVibration;
                      _originalMatchSegments = _matchSegments;
                      _originalMatchDuration = _matchDurationController.text;
                      _originalTargetDuration = _targetDurationController.text;
                      
                      // Reset the unsaved changes flag
                      setState(() {
                        _hasUnsavedChanges = false;
                      });
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Settings saved successfully"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 3,
                      minimumSize: Size(double.infinity, 60),
                    ),
                    child: Text(
                      "Save Settings",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingRow(String label, Widget toggle, Widget input) {
    final isDark = Provider.of<AppState>(context).isDarkTheme;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 16,
            ),
          ),
        ),
        toggle,
        Expanded(
          flex: 2,
          child: input,
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    // Remove listeners to prevent memory leaks
    _matchDurationController.removeListener(_checkForChanges);
    _targetDurationController.removeListener(_checkForChanges);
    
    // Dispose controllers
    _matchDurationController.dispose();
    _targetDurationController.dispose();
    super.dispose();
  }
}