import 'package:flutter/foundation.dart';

class SettingsProvider extends ChangeNotifier {
  String _primaryLanguage = 'en';
  String _secondaryLanguage = 'ja';

  String get primaryLanguage => _primaryLanguage;
  String get secondaryLanguage => _secondaryLanguage;

  void setPrimaryLanguage(String language) {
    if (_primaryLanguage != language) {
      _primaryLanguage = language;
      notifyListeners();
    }
  }

  void setSecondaryLanguage(String language) {
    if (_secondaryLanguage != language) {
      _secondaryLanguage = language;
      notifyListeners();
    }
  }

  List<String> get preferredLanguages => [_primaryLanguage, _secondaryLanguage];
}
